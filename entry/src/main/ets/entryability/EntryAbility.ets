import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { Constants } from '../common/Constants';
import { CrashObserver } from '../service/CrashObserver';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (err) {
      hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'Failed to set colorMode: %{public}s', JSON.stringify(err));
    }
    CrashObserver.register(this.context);
    hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'Ability onCreate, lastExitReason=%{public}d',
      launchParam.lastExitReason);
  }

  onDestroy(): void {
    CrashObserver.unregister();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'Failed to load content: %{public}s', JSON.stringify(err));
      }
    });
  }
}
