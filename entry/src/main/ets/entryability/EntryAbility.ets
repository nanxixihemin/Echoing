import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { initialize } from '@hw-agconnect/hmcore';
import dataPreferences from '@ohos.data.preferences';
import { AuthSessionService, EchoingUser } from '../service/AuthSessionService';

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
    AuthSessionService.getInstance().initialize(this.context).then((authenticated: boolean) => {
      return this.restoreLoginState(authenticated);
    }).then((profileReady: boolean) => {
      const startPage: string = profileReady ? 'pages/Index' : 'pages/LoginPage';
      windowStage.loadContent(startPage, (err) => {
        if (err.code) {
          hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
          return;
        }
        hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content: %{public}s', startPage);
        this.configureMainWindow(windowStage);
      });
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'Failed to choose initial page. Cause: %{public}s', err.message);
      windowStage.loadContent('pages/LoginPage', (loadErr) => {
        if (loadErr.code) {
          hilog.error(DOMAIN, 'testTag', 'Failed to load fallback content. Cause: %{public}s', JSON.stringify(loadErr));
          return;
        }
        this.configureMainWindow(windowStage);
      });
    });
  }

  private async configureMainWindow(windowStage: window.WindowStage): Promise<void> {
    try {
      const mainWindow: window.Window = await windowStage.getMainWindow();
      mainWindow.setWindowBackgroundColor('#050810');
      await mainWindow.setWindowLayoutFullScreen(true);
      const systemBarProperties: window.SystemBarProperties = {
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: '#FFFFFF',
        navigationBarContentColor: '#FFFFFF'
      };
      await mainWindow.setWindowSystemBarProperties(systemBarProperties);
      hilog.info(DOMAIN, 'testTag', 'Succeeded in configuring the main window.');
    } catch (err) {
      const message: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, 'testTag', 'Failed to configure the main window. Cause: %{public}s', message);
    }
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

  private async restoreLoginState(authenticated: boolean): Promise<boolean> {
    try {
      const currentUser: EchoingUser | null = AuthSessionService.getInstance().getCurrentUser();
      if (!authenticated || currentUser === null) {
        return false;
      }
      const prefs = await dataPreferences.getPreferences(this.context, 'echoing_user');
      const nick: dataPreferences.ValueType = await prefs.get(
        'profile.' + currentUser.id + '.nickname', currentUser.nickname);
      const bio: dataPreferences.ValueType = await prefs.get(
        'profile.' + currentUser.id + '.bio', currentUser.bio);
      const normalizedNick: string = typeof nick === 'string' ? nick : currentUser.nickname;
      const normalizedBio: string = typeof bio === 'string' ? bio : currentUser.bio;
      AppStorage.setOrCreate<boolean>('isLoggedIn', true);
      AppStorage.setOrCreate<string>('userNickname', normalizedNick);
      AppStorage.setOrCreate<string>('userBio', normalizedBio);
      AppStorage.setOrCreate<string>('currentAccountKey', currentUser.id);
      hilog.info(DOMAIN, 'testTag', 'Restored login state: isLoggedIn=%{public}s, nick=%{public}s',
        String(true), normalizedNick);
      return normalizedNick.trim().length > 0;
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
