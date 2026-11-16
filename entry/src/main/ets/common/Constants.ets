export class Constants {
  // Duration of the fake save job. Long enough that rapid taps overlap.
  static readonly SAVE_DURATION_MS: number = 800;
  // Leading-edge throttle window for the SAVE button.
  static readonly THROTTLE_MS: number = 500;
  // Trailing-edge debounce window for crown rotation.
  static readonly DEBOUNCE_MS: number = 300;
  static readonly STRESS_TAP_COUNT: number = 30;
  static readonly STRESS_DURATION_MS: number = 1000;
  static readonly ERROR_DISPLAY_MS: number = 2000;
  static readonly LOG_LIMIT: number = 20;

  static readonly PREFS_NAME: string = 'tapguard';
  static readonly KEY_SAVED_COUNT: string = 'savedCount';
  static readonly KEY_LAST_CRASH: string = 'lastCrash';

  static readonly LOG_DOMAIN: number = 0x0002;
  static readonly LOG_TAG: string = 'TapGuard';
}
