/**
 * Allows at most one async task at a time. The lock is taken synchronously,
 * so a second call made in the same frame is already rejected.
 */
export class ReentrancyGuard {
  private locked: boolean = false;

  isLocked(): boolean {
    return this.locked;
  }

  /** Resolves to false when the task was rejected because another one is running. */
  async run(task: () => Promise<void>): Promise<boolean> {
    if (this.locked) {
      return false;
    }
    this.locked = true;
    try {
      await task();
    } finally {
      this.locked = false;
    }
    return true;
  }
}
