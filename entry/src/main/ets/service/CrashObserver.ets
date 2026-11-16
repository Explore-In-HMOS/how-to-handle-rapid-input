import { common, errorManager } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../common/Constants';

/**
 * Persists uncaught JS errors so the next launch can tell the user the
 * previous session crashed (instead of silently restarting).
 */
export class CrashObserver {
  private static observerId: number = -1;

  static register(context: common.Context): void {
    if (CrashObserver.observerId !== -1) {
      return;
    }
    const observer: errorManager.ErrorObserver = {
      onUnhandledException: (errMsg: string) => {
        hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'Unhandled exception: %{public}s', errMsg);
        try {
          const prefs = preferences.getPreferencesSync(context, { name: Constants.PREFS_NAME });
          prefs.putSync(Constants.KEY_LAST_CRASH, `${new Date().toLocaleString()} · ${errMsg}`);
          prefs.flushSync();
        } catch (err) {
          hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'Saving crash failed: %{public}s', JSON.stringify(err));
        }
      }
    };
    try {
      CrashObserver.observerId = errorManager.on('error', observer);
    } catch (err) {
      hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'errorManager.on failed: %{public}s', JSON.stringify(err));
    }
  }

  static unregister(): void {
    if (CrashObserver.observerId === -1) {
      return;
    }
    try {
      errorManager.off('error', CrashObserver.observerId);
    } catch (err) {
      hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'errorManager.off failed: %{public}s', JSON.stringify(err));
    }
    CrashObserver.observerId = -1;
  }

  /** Returns the crash recorded by the previous session (if any) and clears it. */
  static consumeLastCrash(context: common.Context): string {
    try {
      const prefs = preferences.getPreferencesSync(context, { name: Constants.PREFS_NAME });
      const message = prefs.getSync(Constants.KEY_LAST_CRASH, '') as string;
      if (message.length > 0) {
        prefs.deleteSync(Constants.KEY_LAST_CRASH);
        prefs.flushSync();
      }
      return message;
    } catch (err) {
      hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'Reading crash failed: %{public}s', JSON.stringify(err));
      return '';
    }
  }
}
