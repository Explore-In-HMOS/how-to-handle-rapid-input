/**
 * Leading-edge throttler: the first call runs immediately, further calls
 * within `intervalMs` are dropped.
 */
export class Throttler {
  private intervalMs: number;
  private lastRunAt: number = 0;

  constructor(intervalMs: number) {
    this.intervalMs = intervalMs;
  }

  /** Returns false when the call was dropped. */
  tryRun(fn: () => void): boolean {
    const now = Date.now();
    if (now - this.lastRunAt < this.intervalMs) {
      return false;
    }
    this.lastRunAt = now;
    fn();
    return true;
  }

  reset(): void {
    this.lastRunAt = 0;
  }
}
