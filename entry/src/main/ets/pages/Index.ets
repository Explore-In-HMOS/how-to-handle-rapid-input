import { common } from '@kit.AbilityKit';
import BuildProfile from 'BuildProfile';
import { Constants } from '../common/Constants';
import { Debouncer } from '../common/Debouncer';
import { LogEntry, Logger, LogLevel } from '../common/Logger';
import { ReentrancyGuard } from '../common/ReentrancyGuard';
import { Throttler } from '../common/Throttler';
import { InputSource, SavePhase, TapStats } from '../model/TapStats';
import { CrashObserver } from '../service/CrashObserver';
import { SaveService } from '../service/SaveService';

const CROWN_PAD_ID: string = 'crownPad';

@Component
struct StatRow {
  @Prop label: Resource;
  @Prop value: string;
  @Prop valueColor: ResourceColor;

  build() {
    Row() {
      Text(this.label)
        .fontSize(13)
        .fontColor('#C7C7CC')
      Blank()
      Text(this.value)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.valueColor)
    }
    .width('76%')
    .height(24)
  }
}

@Entry
@Component
struct Index {
  @State protectionOn: boolean = true;
  @State stats: TapStats = new TapStats();
  @State phase: SavePhase = SavePhase.IDLE;
  @State logs: LogEntry[] = [];
  @State crashBanner: string = '';
  @State stressRunning: boolean = false;
  @State crownFocused: boolean = false;

  private saveService?: SaveService;
  private context?: common.UIAbilityContext;
  private throttler: Throttler = new Throttler(Constants.THROTTLE_MS);
  private crownDebouncer: Debouncer = new Debouncer(Constants.DEBOUNCE_MS);
  private guard: ReentrancyGuard = new ReentrancyGuard();
  // Async work that settles after the page is gone must not touch @State.
  private isAlive: boolean = false;
  private stressTimerId: number = -1;
  private errorTimerId: number = -1;

  aboutToAppear(): void {
    this.isAlive = true;
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.saveService = new SaveService(this.context);
    this.checkPreviousCrash();
    this.addLog('App started, protection ON');
  }

  onPageShow(): void {
    this.checkPreviousCrash();
  }

  aboutToDisappear(): void {
    this.isAlive = false;
    this.stopStressTest();
    if (this.errorTimerId !== -1) {
      clearTimeout(this.errorTimerId);
      this.errorTimerId = -1;
    }
    this.crownDebouncer.cancel();
    this.saveService?.dispose();
  }

  // ---------- Input handling ----------

  private handleInput(source: InputSource): void {
    this.stats.inputs++;

    if (!this.protectionOn) {
      // Repro path: every input starts a new job, overlapping freely.
      this.executeSave(source).catch((e: Error) => this.onSaveError(e, source));
      return;
    }

    if (source === InputSource.CROWN) {
      // Crown rotation is a stream of events; only the final position matters.
      if (this.crownDebouncer.isPending()) {
        this.stats.ignored++;
      }
      this.crownDebouncer.call(() => this.runGuarded(source));
      return;
    }

    const accepted = this.throttler.tryRun(() => this.runGuarded(source));
    if (!accepted) {
      this.stats.ignored++;
      this.addLog(`${source}: dropped by throttle`, LogLevel.WARN);
    }
  }

  private runGuarded(source: InputSource): void {
    this.guard.run(() => this.executeSave(source))
      .then((ran: boolean) => {
        if (!ran && this.isAlive) {
          this.stats.ignored++;
          this.addLog(`${source}: rejected, a save is already running`, LogLevel.WARN);
        }
      })
      .catch((e: Error) => this.onSaveError(e, source));
  }

  private async executeSave(source: InputSource): Promise<void> {
    const service = this.saveService;
    if (service === undefined) {
      return;
    }
    this.stats.jobStarted();
    this.refreshPhase();
    try {
      await service.save();
      if (this.isAlive) {
        this.addLog(`${source}: saved, count=${service.readCount()}`);
      }
    } finally {
      if (this.isAlive) {
        this.stats.jobFinished();
        this.stats.lostUpdates = service.lostUpdates();
        this.refreshPhase();
      }
    }
  }

  private onSaveError(e: Error, source: InputSource): void {
    if (!this.isAlive) {
      return;
    }
    this.stats.errors++;
    this.addLog(`${source}: ${e.name}: ${e.message}`, LogLevel.ERROR);
    if (!this.protectionOn) {
      this.addLog('Uncaught, this error would crash and restart the app', LogLevel.WARN);
    }
    this.phase = SavePhase.ERROR;
    if (this.errorTimerId !== -1) {
      clearTimeout(this.errorTimerId);
    }
    this.errorTimerId = setTimeout(() => {
      this.errorTimerId = -1;
      this.phase = SavePhase.IDLE;
      this.refreshPhase();
    }, Constants.ERROR_DISPLAY_MS);
  }

  private refreshPhase(): void {
    if (this.phase === SavePhase.ERROR) {
      return;
    }
    this.phase = this.stats.running > 0 ? SavePhase.BUSY : SavePhase.IDLE;
  }

  // ---------- Controls ----------

  private onProtectionChange(isOn: boolean): void {
    this.protectionOn = isOn;
    this.throttler.reset();
    this.crownDebouncer.cancel();
    this.addLog(`Protection ${isOn ? 'ON' : 'OFF'}`, isOn ? LogLevel.INFO : LogLevel.WARN);
  }

  private runStressTest(): void {
    if (this.stressRunning) {
      return;
    }
    this.stressRunning = true;
    this.addLog(`Stress test: ${Constants.STRESS_TAP_COUNT} taps in ${Constants.STRESS_DURATION_MS} ms`);
    let fired = 0;
    const interval = Math.floor(Constants.STRESS_DURATION_MS / Constants.STRESS_TAP_COUNT);
    this.stressTimerId = setInterval(() => {
      this.handleInput(InputSource.STRESS);
      fired++;
      if (fired >= Constants.STRESS_TAP_COUNT) {
        this.stopStressTest();
        this.addLog('Stress test finished');
      }
    }, interval);
  }

  private stopStressTest(): void {
    if (this.stressTimerId !== -1) {
      clearInterval(this.stressTimerId);
      this.stressTimerId = -1;
    }
    this.stressRunning = false;
  }

  private async resetAll(): Promise<void> {
    try {
      await this.saveService?.reset();
    } catch (err) {
      this.addLog(`Reset failed: ${JSON.stringify(err)}`, LogLevel.ERROR);
      return;
    }
    if (!this.isAlive) {
      return;
    }
    this.stats.reset();
    this.throttler.reset();
    this.phase = SavePhase.IDLE;
    this.logs = [];
    this.addLog('Counters reset');
  }

  private crashForReal(): void {
    this.addLog('Throwing an uncaught error…', LogLevel.ERROR);
    setTimeout(() => {
      throw new Error('Intentional crash from TapGuard debug button');
    }, 100);
  }

  private checkPreviousCrash(): void {
    if (this.context === undefined) {
      return;
    }
    const crash = CrashObserver.consumeLastCrash(this.context);
    if (crash.length > 0) {
      this.crashBanner = crash;
      this.addLog(`Previous crash: ${crash}`, LogLevel.ERROR);
    }
  }

  private addLog(message: string, level: LogLevel = LogLevel.INFO): void {
    const entry = Logger.log(message, level);
    this.logs = [entry, ...this.logs].slice(0, Constants.LOG_LIMIT);
  }

  // ---------- View helpers ----------

  private saveLabel(): Resource {
    switch (this.phase) {
      case SavePhase.BUSY:
        return $r('app.string.btn_saving');
      case SavePhase.ERROR:
        return $r('app.string.btn_error');
      default:
        return $r('app.string.btn_save');
    }
  }

  private saveColor(): ResourceColor {
    switch (this.phase) {
      case SavePhase.BUSY:
        return $r('app.color.neutral');
      case SavePhase.ERROR:
        return $r('app.color.error');
      default:
        return $r('app.color.accent');
    }
  }

  private logColor(level: LogLevel): ResourceColor {
    switch (level) {
      case LogLevel.ERROR:
        return $r('app.color.error');
      case LogLevel.WARN:
        return $r('app.color.warning');
      default:
        return '#AEAEB2';
    }
  }

  private countColor(value: number, bad: ResourceColor): ResourceColor {
    return value > 0 ? bad : $r('app.color.success');
  }

  build() {
    Scroll() {
      Column({ space: 6 }) {
        if (this.crashBanner.length > 0) {
          Column() {
            Text($r('app.string.previous_crash'))
              .fontSize(12)
              .fontColor(Color.Black)
              .fontWeight(FontWeight.Bold)
            Text(this.crashBanner)
              .fontSize(11)
              .fontColor(Color.Black)
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('70%')
          .padding(8)
          .borderRadius(12)
          .backgroundColor($r('app.color.warning'))
          .onClick(() => {
            this.crashBanner = '';
          })
        }

        Row() {
          Text($r('app.string.protection'))
            .fontSize(16)
            .fontColor(Color.White)
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.protectionOn })
            .selectedColor($r('app.color.success'))
            .onChange((isOn: boolean) => this.onProtectionChange(isOn))
        }
        .width('62%')

        StatRow({
          label: $r('app.string.stat_inputs'),
          value: `${this.stats.inputs}`,
          valueColor: Color.White
        })
        StatRow({
          label: $r('app.string.stat_running'),
          value: `${this.stats.running} / ${this.stats.peakRunning}`,
          valueColor: this.stats.peakRunning > 1 ? $r('app.color.error') : $r('app.color.success')
        })
        StatRow({
          label: $r('app.string.stat_ignored'),
          value: `${this.stats.ignored}`,
          valueColor: this.stats.ignored > 0 ? $r('app.color.warning') : $r('app.color.neutral')
        })
        StatRow({
          label: $r('app.string.stat_lost'),
          value: `${this.stats.lostUpdates}`,
          valueColor: this.countColor(this.stats.lostUpdates, $r('app.color.error'))
        })
        StatRow({
          label: $r('app.string.stat_errors'),
          value: `${this.stats.errors}`,
          valueColor: this.countColor(this.stats.errors, $r('app.color.error'))
        })

        Button(this.saveLabel())
          .width(140)
          .height(56)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .backgroundColor(this.saveColor())
          // UI-level guard: while protected, the button cannot be pressed during a save.
          .enabled(!(this.protectionOn && this.stats.running > 0))
          .onClick(() => this.handleInput(InputSource.TAP))

        Row({ space: 8 }) {
          Button($r('app.string.btn_stress'))
            .height(40)
            .layoutWeight(1)
            .fontSize(14)
            .backgroundColor($r('app.color.card'))
            .enabled(!this.stressRunning)
            .onClick(() => this.runStressTest())
          Button($r('app.string.btn_reset'))
            .height(40)
            .layoutWeight(1)
            .fontSize(14)
            .backgroundColor($r('app.color.card'))
            .enabled(!this.stressRunning && this.stats.running === 0)
            .onClick(() => {
              this.resetAll();
            })
        }
        .width('70%')

        Text(this.crownFocused ? $r('app.string.crown_pad_focused') : $r('app.string.crown_pad_idle'))
          .id(CROWN_PAD_ID)
          .width('70%')
          .height(48)
          .fontSize(12)
          .textAlign(TextAlign.Center)
          .fontColor(this.crownFocused ? Color.White : $r('app.color.neutral'))
          .borderRadius(24)
          .borderWidth(1)
          .borderColor(this.crownFocused ? $r('app.color.accent') : '#3A3A3C')
          .focusable(true)
          .focusOnTouch(true)
          .onFocus(() => {
            this.crownFocused = true;
          })
          .onBlur(() => {
            this.crownFocused = false;
          })
          .onDigitalCrown((event: CrownEvent) => {
            event.stopPropagation();
            if (event.action === CrownAction.UPDATE) {
              this.handleInput(InputSource.CROWN);
            }
          })
          .onKeyEvent((event: KeyEvent) => {
            if (event.type === KeyType.Down) {
              this.handleInput(InputSource.KEY);
            }
          })

        if (BuildProfile.DEBUG) {
          Button($r('app.string.btn_crash'))
            .height(36)
            .fontSize(12)
            .fontColor($r('app.color.error'))
            .backgroundColor($r('app.color.card'))
            .onClick(() => this.crashForReal())
        }

        Text($r('app.string.event_log'))
          .fontSize(12)
          .fontColor($r('app.color.neutral'))
          .margin({ top: 6 })

        ForEach(this.logs, (entry: LogEntry) => {
          Text(`${entry.time}  ${entry.message}`)
            .width('76%')
            .fontSize(11)
            .fontColor(this.logColor(entry.level))
        }, (entry: LogEntry) => entry.id.toString())
      }
      .width('100%')
      .padding({ top: 40, bottom: 56 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor(Color.Black)
  }
}
