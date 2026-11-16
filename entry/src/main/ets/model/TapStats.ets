export enum InputSource {
  TAP = 'tap',
  CROWN = 'crown',
  KEY = 'key',
  STRESS = 'stress'
}

export enum SavePhase {
  IDLE,
  BUSY,
  ERROR
}

@Observed
export class TapStats {
  inputs: number = 0;
  running: number = 0;
  peakRunning: number = 0;
  ignored: number = 0;
  errors: number = 0;
  // Updates that were written but overwritten by a concurrent job (read-modify-write race).
  lostUpdates: number = 0;

  jobStarted(): void {
    this.running++;
    this.peakRunning = Math.max(this.peakRunning, this.running);
  }

  jobFinished(): void {
    this.running = Math.max(0, this.running - 1);
  }

  reset(): void {
    this.inputs = 0;
    this.running = 0;
    this.peakRunning = 0;
    this.ignored = 0;
    this.errors = 0;
    this.lostUpdates = 0;
  }
}
