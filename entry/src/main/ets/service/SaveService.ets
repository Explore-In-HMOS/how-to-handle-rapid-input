import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../common/Constants';

/**
 * A short-lived resource owned by one save job (think: a DB transaction or a
 * file handle). Committing it twice, or committing a cleared one, is a bug.
 */
class SaveSession {
  readonly id: number;
  private closed: boolean = false;

  constructor(id: number) {
    this.id = id;
  }

  commit(): void {
    if (this.closed) {
      throw new Error(`Session #${this.id} is already closed`);
    }
    this.closed = true;
  }
}

/**
 * Fake "save" that increments a persisted counter with a read-modify-write
 * cycle. It is deliberately NOT safe to run concurrently, which is exactly
 * what rapid input does when nothing guards it:
 *  - concurrent jobs read the same value, so increments are lost;
 *  - jobs share `activeSession`, so a late job finds it cleared and throws
 *    a TypeError. Left uncaught, that error kills and restarts the app.
 */
export class SaveService {
  private prefs: preferences.Preferences;
  private activeSession: SaveSession | null = null;
  private nextSessionId: number = 1;
  private pendingTimers: Set<number> = new Set();
  private baseline: number;
  private writes: number = 0;

  constructor(context: common.Context) {
    this.prefs = preferences.getPreferencesSync(context, { name: Constants.PREFS_NAME });
    this.baseline = this.readCount();
  }

  readCount(): number {
    try {
      return this.prefs.getSync(Constants.KEY_SAVED_COUNT, 0) as number;
    } catch (err) {
      hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'readCount failed: %{public}s', JSON.stringify(err));
      return 0;
    }
  }

  /** Increments written by jobs but missing from storage because a concurrent job overwrote them. */
  lostUpdates(): number {
    return this.writes - (this.readCount() - this.baseline);
  }

  async save(): Promise<void> {
    this.activeSession = new SaveSession(this.nextSessionId++);

    const current = await this.prefs.get(Constants.KEY_SAVED_COUNT, 0) as number;
    await this.delay(Constants.SAVE_DURATION_MS);
    await this.prefs.put(Constants.KEY_SAVED_COUNT, current + 1);
    await this.prefs.flush();
    this.writes++;

    // Bug pattern under test: the shared field is used instead of a local
    // reference. With overlapping jobs another job may already have cleared it.
    (this.activeSession as SaveSession).commit();
    this.activeSession = null;
  }

  async reset(): Promise<void> {
    await this.prefs.put(Constants.KEY_SAVED_COUNT, 0);
    await this.prefs.flush();
    this.baseline = 0;
    this.writes = 0;
  }

  /** Cancels in-flight jobs; their promises never settle, so they cannot touch the UI. */
  dispose(): void {
    this.pendingTimers.forEach((id: number) => clearTimeout(id));
    this.pendingTimers.clear();
    this.activeSession = null;
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      const id = setTimeout(() => {
        this.pendingTimers.delete(id);
        resolve();
      }, ms);
      this.pendingTimers.add(id);
    });
  }
}
