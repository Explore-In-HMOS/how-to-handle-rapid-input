/**
 * Trailing-edge debouncer: only the last call within `delayMs` runs.
 */
export class Debouncer {
  private delayMs: number;
  private timerId: number = -1;

  constructor(delayMs: number) {
    this.delayMs = delayMs;
  }

  call(fn: () => void): void {
    this.cancel();
    this.timerId = setTimeout(() => {
      this.timerId = -1;
      fn();
    }, this.delayMs);
  }

  isPending(): boolean {
    return this.timerId !== -1;
  }

  cancel(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }
}
