import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { initialize } from '@hw-agconnect/hmcore';
import dataPreferences from '@ohos.data.preferences';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    // 初始化 AppStorage 中的全局登录状态（默认值）
    AppStorage.setOrCreate<boolean>('isLoggedIn', false);
    AppStorage.setOrCreate<string>('userNickname', '');
    AppStorage.setOrCreate<string>('userBio', '');
    AppStorage.setOrCreate<string>('currentAccountKey', '');
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 设置窗口为沉浸式全屏布局（解决全面屏下顶部状态栏和底部导航条呈现白边的问题）
    windowStage.getMainWindow((err, data) => {
      if (!err.code) {
        let windowClass = data;
        
        // 设置窗口背景色为深色，防止任何瞬间出现白色闪烁/白底
        windowClass.setWindowBackgroundColor('#050810', (colorErr) => {
          if (colorErr.code) {
            hilog.error(DOMAIN, 'testTag', 'Failed to set window background color. Cause: %{public}s', JSON.stringify(colorErr));
          } else {
            hilog.info(DOMAIN, 'testTag', 'Succeeded in setting window background color.');
          }
        });

        // 启用沉浸式全屏布局
        windowClass.setWindowLayoutFullScreen(true, (fullErr) => {
          if (fullErr.code) {
            hilog.error(DOMAIN, 'testTag', 'Failed to set full-screen. Cause: %{public}s', JSON.stringify(fullErr));
          } else {
            hilog.info(DOMAIN, 'testTag', 'Succeeded in setting full-screen layout.');
            
            // 将状态栏和导航栏背景设为全透明，同时强制状态栏文字与图标为白色（高对比度）
            let sysBarProps: window.SystemBarProperties = {
              statusBarColor: '#00000000',
              navigationBarColor: '#00000000',
              statusBarContentColor: '#FFFFFF',
              navigationBarContentColor: '#FFFFFF'
            };
            windowClass.setWindowSystemBarProperties(sysBarProps, (barErr) => {
              if (barErr.code) {
                hilog.error(DOMAIN, 'testTag', 'Failed to set system bar properties. Cause: %{public}s', JSON.stringify(barErr));
              } else {
                hilog.info(DOMAIN, 'testTag', 'Succeeded in setting system bar properties.');
              }
            });
          }
        });
      } else {
        hilog.error(DOMAIN, 'testTag', 'Failed to obtain main window. Cause: %{public}s', JSON.stringify(err));
      }
    });

    // 初始化 AGC SDK：必须手动读取 agconnect-services.json 传入
    try {
      let resMgr = this.context.resourceManager;
      hilog.info(DOMAIN, 'testTag', 'Step1: got resourceManager');
      let jsonUint8 = resMgr.getRawFileContentSync('agconnect-services.json');
      hilog.info(DOMAIN, 'testTag', 'Step2: rawfile read, length=%{public}d', jsonUint8.byteLength);
      let decoder = new util.TextDecoder('utf-8');
      let jsonStr = decoder.decode(jsonUint8);
      hilog.info(DOMAIN, 'testTag', 'Step3: decoded, length=%{public}d', jsonStr.length);
      let jsonObj: ESObject = JSON.parse(jsonStr) as ESObject;
      hilog.info(DOMAIN, 'testTag', 'Step4: parsed JSON, calling initialize...');
      initialize(this.context, jsonObj);
      hilog.info(DOMAIN, 'testTag', 'Step5: AGC SDK initialized successfully!');
    } catch (err) {
      let errMsg = (err instanceof Error) ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, 'testTag', 'AGC init FAILED: %{public}s', errMsg);
    }

    // 从 Preferences 恢复登录状态到 AppStorage
    // Restore App user state before choosing the first page.
    this.restoreLoginState().then((profileReady: boolean) => {
      const startPage: string = profileReady ? 'pages/Index' : 'pages/LoginPage';
      windowStage.loadContent(startPage, (err) => {
        if (err.code) {
          hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
          return;
        }
        hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content: %{public}s', startPage);
      });
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'Failed to choose initial page. Cause: %{public}s', err.message);
      windowStage.loadContent('pages/LoginPage', (loadErr) => {
        if (loadErr.code) {
          hilog.error(DOMAIN, 'testTag', 'Failed to load fallback content. Cause: %{public}s', JSON.stringify(loadErr));
        }
      });
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  private async restoreLoginState(): Promise<boolean> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'echoing_user');
      const logged: dataPreferences.ValueType = await prefs.get('isLoggedIn', false);
      const accountKey: dataPreferences.ValueType = await prefs.get('accountKey', '');
      const normalizedLogged: boolean = logged === true;
      const normalizedAccountKey: string = typeof accountKey === 'string' ? accountKey : String(accountKey);
      const nick: dataPreferences.ValueType = normalizedAccountKey.length > 0 ?
        await prefs.get('profile.' + normalizedAccountKey + '.nickname', '') : '';
      const bio: dataPreferences.ValueType = normalizedAccountKey.length > 0 ?
        await prefs.get('profile.' + normalizedAccountKey + '.bio', '') : '';
      const normalizedNick: string = typeof nick === 'string' ? nick : String(nick);
      const normalizedBio: string = typeof bio === 'string' ? bio : String(bio);
      AppStorage.setOrCreate<boolean>('isLoggedIn', normalizedLogged);
      AppStorage.setOrCreate<string>('userNickname', normalizedNick);
      AppStorage.setOrCreate<string>('userBio', normalizedBio);
      AppStorage.setOrCreate<string>('currentAccountKey', normalizedAccountKey);
      hilog.info(DOMAIN, 'testTag', 'Restored login state: isLoggedIn=%{public}s, nick=%{public}s',
        String(normalizedLogged), normalizedNick);
      return normalizedLogged && normalizedAccountKey.length > 0 && normalizedNick.trim().length > 0;
    } catch (err) {
      AppStorage.setOrCreate<boolean>('isLoggedIn', false);
      AppStorage.setOrCreate<string>('userNickname', '');
      AppStorage.setOrCreate<string>('userBio', '');
      AppStorage.setOrCreate<string>('currentAccountKey', '');
      hilog.error(DOMAIN, 'testTag', 'Failed to restore login state: %{public}s', JSON.stringify(err));
      return false;
    }
  }
}
