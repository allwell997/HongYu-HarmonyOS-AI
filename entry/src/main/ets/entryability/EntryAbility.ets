import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN: number = 0x0000;
const TAG: string = 'HongYuAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.publishSystemTheme(this.context.config.colorMode);
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    this.publishSystemTheme(newConfig.colorMode);
  }

  private publishSystemTheme(colorMode: ConfigurationConstant.ColorMode | undefined): void {
    AppStorage.setOrCreate('systemDark', colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      windowStage.getMainWindow().then((mainWindow: window.Window) => {
        mainWindow.setWindowSystemBarProperties({
          statusBarColor: '#F4F5F9',
          statusBarContentColor: '#1A1D26',
          navigationBarColor: '#F4F5F9',
          navigationBarContentColor: '#1A1D26'
        });
      }).catch((error: Error) => {
        hilog.warn(DOMAIN, TAG, 'Failed to set system bar: %{public}s', error.message);
      });
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'WindowStage destroyed');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }
}
