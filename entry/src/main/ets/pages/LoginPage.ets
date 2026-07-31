import { router } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import cloud, { VerifyCodeAction } from '@hw-agconnect/cloud';
import dataPreferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { AuthSessionService, EchoingUser } from '../service/AuthSessionService';
import { EchoColors, EchoRadius, EchoSpacing } from '../utils/EchoTheme';

// 登录模式
type LoginTab = 'huawei' | 'email';
type EmailMode = 'signin' | 'signup';

// AGC 接口声明
interface EmailSignInCredential { kind: 'email'; email: string; password: string; }
interface EmailSignInParams { credentialInfo: EmailSignInCredential; }
interface EmailCreateUserParams { kind: 'email'; email: string; password: string; verifyCode: string; }
interface EmailVerifyCodeType { email: string; kind: 'email'; }
interface RequestEmailVerifyCodeParams {
  action: VerifyCodeAction; lang: string; sendInterval: number; verifyCodeType: EmailVerifyCodeType;
}

@Entry
@Component
struct LoginPage {
  @State activeTab: LoginTab = 'huawei';
  @State statusMsg: string = '';
  @State isError: boolean = false;
  @State isLoading: boolean = false;
  @State emailMode: EmailMode = 'signin';
  @State email: string = '';
  @State password: string = '';
  @State confirmPassword: string = '';
  @State verifyCode: string = '';
  @State canSendCode: boolean = true;
  @State countdown: number = 60;

  // ---- 全局登录状态：通过 AppStorage 与其他页面共享 ----
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false;
  @StorageLink('userNickname') nickname: string = '';
  @StorageLink('userBio') bio: string = '';
  @StorageLink('currentAccountKey') currentAccountKey: string = '';

  private showStatus(msg: string, isErr: boolean = false): void {
    this.statusMsg = msg;
    this.isError = isErr;
  }

  private clearStatus(): void {
    this.statusMsg = '';
    this.isError = false;
  }

  private profileKey(accountKey: string, field: string): string {
    return 'profile.' + accountKey + '.' + field;
  }

  private async restoreProfileForAccount(accountKey: string): Promise<boolean> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(ctx, 'echoing_user');
      const nick: dataPreferences.ValueType = await prefs.get(this.profileKey(accountKey, 'nickname'), '');
      const bio: dataPreferences.ValueType = await prefs.get(this.profileKey(accountKey, 'bio'), '');
      const storedNickname = typeof nick === 'string' ? nick : String(nick);
      const storedBio = typeof bio === 'string' ? bio : String(bio);
      if (storedNickname.length > 0) {
        this.nickname = storedNickname;
      }
      if (storedBio.length > 0) {
        this.bio = storedBio;
      }
      return this.nickname.trim().length > 0;
    } catch (err) {
      console.error('testTag', 'Restore account profile failed: ' + JSON.stringify(err));
      this.nickname = '';
      this.bio = '';
      return false;
    }
  }

  // ---- 持久化登录状态到 Preferences ----
  private async persistLoginState(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(ctx, 'echoing_user');
      await prefs.put('isLoggedIn', true);
      await prefs.put('hasSession', true);
      await prefs.put('userId', this.currentAccountKey);
      await prefs.delete('accountKey');
      await prefs.put('nickname', this.nickname);
      await prefs.put('bio', this.bio);
      if (this.currentAccountKey.length > 0) {
        await prefs.put(this.profileKey(this.currentAccountKey, 'nickname'), this.nickname);
        await prefs.put(this.profileKey(this.currentAccountKey, 'bio'), this.bio);
      }
      await prefs.flush();
      console.info('testTag', '登录状态已持久化');
    } catch (err) {
      console.error('testTag', `持久化登录状态失败: ${JSON.stringify(err)}`);
    }
  }

  private async persistLogoutState(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const prefs = await dataPreferences.getPreferences(ctx, 'echoing_user');
      await prefs.put('isLoggedIn', false);
      await prefs.flush();
      console.info('testTag', 'App user logout state persisted');
    } catch (err) {
      console.error('testTag', 'Persist logout state failed: ' + JSON.stringify(err));
    }
  }

  private goHome(): void {
    router.replaceUrl({ url: 'pages/Index' });
  }

  private async logout(): Promise<void> {
    await AuthSessionService.getInstance().logout();
    this.isLoggedIn = false;
    this.currentAccountKey = '';
    await this.persistLogoutState();
    this.showStatus('\u5df2\u9000\u51fa\u767b\u5f55');
  }

  private completeSignIn(user: EchoingUser): void {
    if (user.id.length <= 0) {
      this.showStatus('登录失败：缺少账号标识', true);
      return;
    }
    this.currentAccountKey = user.id;
    this.nickname = user.nickname;
    this.bio = user.bio;
    this.restoreProfileForAccount(user.id).then((profileReady: boolean) => {
      this.isLoggedIn = true;
      if (!profileReady) {
        this.showStatus('登录成功，请设置你的资料');
        return;
      }
      this.persistLoginState().then(() => {
        this.showStatus('登录成功');
        setTimeout(() => { this.goHome(); }, 300);
      });
    });
  }


  // ---- 华为账号登录 ----
  private doHuaweiSignIn(): void {
    this.isLoading = true;
    this.showStatus('正在拉起华为账号…');
    AuthSessionService.getInstance().signInWithHuawei().then((user: EchoingUser) => {
      this.completeSignIn(user);
    }).catch((err: BusinessError) => {
      const code = Number(err?.code ?? 0);
      const message = String(err?.message ?? '未知错误');
      console.error('HuaweiLogin', `code=${code}, message=${message}`);
      if (code === 1001502001 || message.toLowerCase().indexOf('cancel') >= 0) {
        this.showStatus(`已取消（${code}）`);
      } else if (code === 1001500001) {
        this.showStatus(`登录失败：应用签名指纹未配置（${code}）`, true);
      } else if (code === 1001502002) {
        this.showStatus(`登录失败：应用未授权（${code}）`, true);
      } else if (code === 1001502005) {
        this.showStatus(`登录失败：网络错误（${code}）`, true);
      } else if (code === 1001502009) {
        this.showStatus(`登录失败：华为账号服务内部错误（${code}）`, true);
      } else if (code === 1001500003) {
        this.showStatus(`登录失败：当前账号或地区不支持（${code}）`, true);
      } else {
        this.showStatus(`登录失败（错误码 ${code}）：${message}`, true);
      }
    }).finally(() => { this.isLoading = false; });
  }

  // ---- 邮箱登录 ----
  private doEmailSignIn(): void {
    if (!this.email || !this.password) { this.showStatus('请填写邮箱和密码', true); return; }
    this.isLoading = true;
    this.showStatus('正在登录…');
    const params: EmailSignInParams = {
      credentialInfo: { kind: 'email', email: this.email, password: this.password }
    };
    cloud.auth().signIn(params).then(() => {
      return AuthSessionService.getInstance().signInWithAgc();
    }).then((user: EchoingUser) => {
      this.completeSignIn(user);
    }).catch((err: BusinessError) => {
      this.showStatus(`登录失败：${err.message}`, true);
    }).finally(() => { this.isLoading = false; });
  }

  private sendRegisterCode(): void {
    if (!this.email) { this.showStatus('请先填写邮箱', true); return; }
    this.canSendCode = false;
    this.showStatus('正在发送…');
    const params: RequestEmailVerifyCodeParams = {
      action: VerifyCodeAction.REGISTER_LOGIN, lang: 'zh_CN', sendInterval: 60,
      verifyCodeType: { email: this.email, kind: 'email' }
    };
    cloud.auth().requestVerifyCode(params).then(() => {
      this.showStatus('验证码已发送');
      this.countdown = 60;
      const interval = setInterval(() => {
        this.countdown--;
        if (this.countdown <= 0) { clearInterval(interval); this.canSendCode = true; this.countdown = 60; }
      }, 1000);
    }).catch((err: BusinessError) => {
      this.showStatus(`发送失败：${err.message}`, true);
      this.canSendCode = true;
    });
  }

  private doEmailSignUp(): void {
    if (!this.email || !this.password || !this.verifyCode) { this.showStatus('请填写完整信息', true); return; }
    if (this.password !== this.confirmPassword) { this.showStatus('两次密码不一致', true); return; }
    this.isLoading = true;
    this.showStatus('正在注册…');
    const params: EmailCreateUserParams = {
      kind: 'email', email: this.email, password: this.password, verifyCode: this.verifyCode
    };
    cloud.auth().createUser(params).then(() => {
      this.showStatus('注册成功，正在登录…');
      this.doEmailSignIn();
    }).catch((err: BusinessError) => {
      this.showStatus(`注册失败：${err.message}`, true);
      this.isLoading = false;
    });
  }

  // ---- 保存用户资料并持久化 ----
  private async saveProfile(): Promise<void> {
    const trimmedNickname: string = this.nickname.trim();
    const trimmedBio: string = this.bio.trim();
    if (!trimmedNickname) { this.showStatus('\u8bf7\u8f93\u5165\u6635\u79f0', true); return; }
    if (this.currentAccountKey.length <= 0) { this.showStatus('缺少账号标识，请重新登录', true); return; }
    this.nickname = trimmedNickname;
    this.bio = trimmedBio;
    try {
      await AuthSessionService.getInstance().updateProfile(trimmedNickname, trimmedBio);
      await this.persistLoginState();
      this.showStatus('\u8d44\u6599\u5df2\u4fdd\u5b58');
      setTimeout(() => { this.goHome(); }, 500);
    } catch (error) {
      this.showStatus('资料保存失败，请重新登录', true);
    }
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(28)
          .fontWeight(600)
          .fontColor(EchoColors.TEXT_PRIMARY)
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .borderRadius(EchoRadius.PILL)
          .backgroundColor(EchoColors.SURFACE)
          .border({ width: 1, color: EchoColors.BORDER })
          .onClick(() => { router.back(); })
      }
      .width('100%')
      .padding({ left: EchoSpacing.PAGE, right: EchoSpacing.PAGE, top: 16 })

      Scroll() {
        Column({ space: EchoSpacing.LARGE }) {
          Row({ space: EchoSpacing.MEDIUM }) {
            Column() {
              Image($r('app.media.echoing_icon'))
                .width(44)
                .height(44)
                .borderRadius(EchoRadius.MEDIUM)
            }
            .width(56)
            .height(56)
            .borderRadius(EchoRadius.LARGE)
            .backgroundColor(EchoColors.PRIMARY_SOFT)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)

            Column({ space: 4 }) {
              Text(this.isLoggedIn ? '完善个人资料' : '欢迎回来')
                .fontSize(28)
                .fontWeight(700)
                .fontColor(EchoColors.TEXT_PRIMARY)
              Text(this.isLoggedIn ? '留下一个自然的称呼，继续你的记录' : '登录后，在不同设备间延续你的回声')
                .fontSize(13)
                .fontColor(EchoColors.TEXT_SECONDARY)
                .maxLines(2)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Column({ space: 16 }) {
            if (this.isLoggedIn) {
              this.ProfileSection()
            } else {
              this.LoginFormSection()
            }

            if (this.statusMsg.length > 0) {
              Text(this.statusMsg)
                .fontSize(12)
                .fontWeight(500)
                .fontColor(this.isError ? EchoColors.PINK_TEXT : EchoColors.MINT_TEXT)
                .textAlign(TextAlign.Center)
                .width('100%')
                .padding({ top: 10, bottom: 10, left: 12, right: 12 })
                .backgroundColor(this.isError ? EchoColors.PINK_SOFT : EchoColors.MINT_SOFT)
                .borderRadius(EchoRadius.SMALL)
            }
          }
          .width('100%')
          .padding(EchoSpacing.LARGE)
          .borderRadius(EchoRadius.LARGE)
          .backgroundColor(EchoColors.SURFACE)
          .border({ width: 1, color: EchoColors.BORDER })

          Text('登录即代表你已阅读并同意服务协议与隐私政策')
            .fontSize(11)
            .fontColor(EchoColors.TEXT_TERTIARY)
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ bottom: 24 })
        }
        .width('100%')
        .padding({ left: EchoSpacing.PAGE, right: EchoSpacing.PAGE, top: 24 })
        .alignItems(HorizontalAlign.Center)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EchoColors.PAGE)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  LoginFormSection() {
    Column({ space: 16 }) {
      Row() {
        this.LoginTabItem('华为账号', this.activeTab === 'huawei', () => {
          this.activeTab = 'huawei';
          this.clearStatus();
        })
        this.LoginTabItem('邮箱', this.activeTab === 'email', () => {
          this.activeTab = 'email';
          this.clearStatus();
        })
      }
      .width('100%')
      .padding(4)
      .backgroundColor(EchoColors.SURFACE_MUTED)
      .borderRadius(EchoRadius.MEDIUM)

      if (this.activeTab === 'huawei') {
        Column({ space: EchoSpacing.MEDIUM }) {
          Column({ space: 6 }) {
            Text('使用华为账号继续')
              .fontSize(17)
              .fontWeight(600)
              .fontColor(EchoColors.TEXT_PRIMARY)
            Text('快速登录并安全同步你的个人记录')
              .fontSize(13)
              .fontColor(EchoColors.TEXT_SECONDARY)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Button(this.isLoading ? '正在连接…' : '使用华为账号登录')
            .width('100%')
            .height(50)
            .fontSize(15)
            .fontWeight(600)
            .fontColor('#FFFFFF')
            .backgroundColor(EchoColors.PRIMARY)
            .borderRadius(EchoRadius.MEDIUM)
            .enabled(!this.isLoading)
            .onClick(() => { this.doHuaweiSignIn(); })
        }
        .width('100%')
      } else {
        this.EmailSection()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  LoginTabItem(label: string, selected: boolean, onClick: () => void) {
    Text(label)
      .layoutWeight(1)
      .height(40)
      .textAlign(TextAlign.Center)
      .fontSize(14)
      .fontWeight(600)
      .fontColor(selected ? EchoColors.PRIMARY_DARK : EchoColors.TEXT_SECONDARY)
      .backgroundColor(selected ? EchoColors.SURFACE : 'transparent')
      .borderRadius(EchoRadius.SMALL)
      .onClick(onClick)
  }

  @Builder
  EmailSection() {
    Column({ space: 12 }) {
      Row() {
        this.EmailModeItem('登录', this.emailMode === 'signin', () => {
          this.emailMode = 'signin';
          this.clearStatus();
        })
        this.EmailModeItem('注册', this.emailMode === 'signup', () => {
          this.emailMode = 'signup';
          this.clearStatus();
        })
      }
      .width('100%')
      .padding(3)
      .backgroundColor(EchoColors.PAGE)
      .borderRadius(EchoRadius.MEDIUM)

      this.SoftInput('邮箱地址', InputType.Email, (v: string) => { this.email = v; })
      this.SoftInput('密码', InputType.Password, (v: string) => { this.password = v; })

      if (this.emailMode === 'signup') {
        this.SoftInput('确认密码', InputType.Password, (v: string) => { this.confirmPassword = v; })
        Row({ space: EchoSpacing.SMALL }) {
          TextInput({ placeholder: '验证码' })
            .type(InputType.Number)
            .maxLength(6)
            .layoutWeight(1)
            .height(48)
            .borderRadius(EchoRadius.SMALL)
            .backgroundColor(EchoColors.PAGE)
            .fontColor(EchoColors.TEXT_PRIMARY)
            .placeholderColor(EchoColors.TEXT_TERTIARY)
            .border({ width: 1, color: EchoColors.BORDER })
            .onChange((v: string) => { this.verifyCode = v; })

          Button(this.canSendCode ? '发送验证码' : `${this.countdown}s`)
            .width(96)
            .height(48)
            .fontSize(12)
            .fontWeight(600)
            .borderRadius(EchoRadius.SMALL)
            .enabled(this.canSendCode)
            .backgroundColor(this.canSendCode ? EchoColors.PRIMARY_SOFT : EchoColors.SURFACE_MUTED)
            .fontColor(this.canSendCode ? EchoColors.PRIMARY_DARK : EchoColors.TEXT_TERTIARY)
            .onClick(() => { this.sendRegisterCode(); })
        }
        .width('100%')
      }

      Button(this.isLoading ? '请稍候…' : (this.emailMode === 'signin' ? '登录' : '创建账号'))
        .width('100%')
        .height(50)
        .fontSize(15)
        .fontWeight(600)
        .fontColor('#FFFFFF')
        .backgroundColor(EchoColors.PRIMARY)
        .borderRadius(EchoRadius.MEDIUM)
        .enabled(!this.isLoading)
        .margin({ top: 4 })
        .onClick(() => {
          if (this.emailMode === 'signin') { this.doEmailSignIn(); }
          else { this.doEmailSignUp(); }
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  EmailModeItem(label: string, selected: boolean, onClick: () => void) {
    Text(label)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .fontSize(13)
      .fontWeight(600)
      .fontColor(selected ? EchoColors.PRIMARY_DARK : EchoColors.TEXT_SECONDARY)
      .backgroundColor(selected ? EchoColors.PRIMARY_SOFT : 'transparent')
      .borderRadius(EchoRadius.SMALL)
      .height(34)
      .onClick(onClick)
  }

  @Builder
  ProfileSection() {
    Column({ space: 16 }) {
      Column({ space: 4 }) {
        Text(this.nickname.trim().length > 0 ? this.nickname : '设置个人资料')
          .fontSize(20)
          .fontWeight(700)
          .fontColor(EchoColors.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('昵称和签名会与你的账号一起保存')
          .fontSize(12)
          .fontColor(EchoColors.TEXT_SECONDARY)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      this.ProfileInput('昵称', '给自己取个名字吧', this.nickname, (v: string) => { this.nickname = v; })
      this.ProfileInput('一句话签名', '说点什么（选填）', this.bio, (v: string) => { this.bio = v; })

      Button('保存并进入')
        .width('100%')
        .height(50)
        .fontSize(15)
        .fontWeight(600)
        .fontColor('#FFFFFF')
        .backgroundColor(EchoColors.PRIMARY)
        .borderRadius(EchoRadius.MEDIUM)
        .margin({ top: 4 })
        .onClick(() => { this.saveProfile(); })

      Text('退出登录')
        .fontSize(13)
        .fontWeight(500)
        .fontColor(EchoColors.PINK_TEXT)
        .padding({ top: 6, bottom: 2 })
        .onClick(() => { this.logout(); })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  ProfileInput(label: string, placeholder: string, value: string, onChange: (v: string) => void) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(12)
        .fontColor(EchoColors.TEXT_SECONDARY)
        .fontWeight(500)
        .width('100%')
      TextInput({ placeholder: placeholder, text: value })
        .width('100%')
        .height(48)
        .borderRadius(EchoRadius.SMALL)
        .backgroundColor(EchoColors.PAGE)
        .fontColor(EchoColors.TEXT_PRIMARY)
        .fontWeight(500)
        .placeholderColor(EchoColors.TEXT_TERTIARY)
        .border({ width: 1, color: EchoColors.BORDER })
        .onChange(onChange)
    }
    .width('100%')
  }

  @Builder
  SoftInput(placeholder: string, type: InputType, onChange: (v: string) => void) {
    TextInput({ placeholder: placeholder })
      .type(type)
      .width('100%')
      .height(48)
      .borderRadius(EchoRadius.SMALL)
      .backgroundColor(EchoColors.PAGE)
      .fontColor(EchoColors.TEXT_PRIMARY)
      .fontWeight(500)
      .placeholderColor(EchoColors.TEXT_TERTIARY)
      .border({ width: 1, color: EchoColors.BORDER })
      .onChange(onChange)
  }
}
