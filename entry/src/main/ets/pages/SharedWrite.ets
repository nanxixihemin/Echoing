// MainAbility/pages/SharedWrite.ets

import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AIResponseGenerator } from '../utils/AIResponseGenerator';
import { KeywordDetector, CrisisDetectionResult, CRISIS_HELP_INFO } from '../utils/KeywordDetector';
import { SharedForestService } from '../service/SharedForestService';
import { EchoColors, EchoRadius, EchoSpacing } from '../utils/EchoTheme';

@Entry
@Component
struct SharedWrite {
  @State inputContent: string = '';
  @State inputNickname: string = '';
  @State aiResponse: string = '';
  @State showAIResponse: boolean = false;
  @State isSubmitting: boolean = false;
  @State isOnline: boolean = true;

  // 危机检测相关状态
  @State showCrisisDialog: boolean = false;
  @State crisisLevel: string = 'none';
  @State showMildWarning: boolean = false;
  @StorageProp('currentAccountKey') currentAccountKey: string = '';
  @StorageProp('userNickname') userNickname: string = '';

  aboutToAppear(): void {
    this.checkConnection();
  }

  private async checkConnection(): Promise<void> {
    this.isOnline = await SharedForestService.checkConnection();
  }

  private generateNickname(): string {
    const prefixes: string[] = ['南核的', '图书馆的', '操场边的', '食堂里的', '眉湖边的', '樱花道的', '钟楼下的', '柳园的'];
    const suffixes: string[] = ['猫', '云', '风', '星星', '蒲公英', '叶子', '萤火虫', '小鸟', '蝴蝶'];
    const pIndex: number = Math.floor(Math.random() * prefixes.length);
    const sIndex: number = Math.floor(Math.random() * suffixes.length);
    return prefixes[pIndex] + suffixes[sIndex];
  }

  // 检测并处理提交
  private handleSubmit(): void {
    if (this.inputContent.trim().length === 0 || this.isSubmitting) {
      return;
    }

    const result: CrisisDetectionResult = KeywordDetector.detect(this.inputContent);

    if (result.isCrisis) {
      this.crisisLevel = result.level;

      if (result.level === 'severe') {
        // 严重：显示关怀弹窗，不允许发布
        this.showCrisisDialog = true;
      } else if (result.level === 'mild') {
        // 轻度：显示关怀弹窗，但允许选择继续发布
        this.showMildWarning = true;
      }
    } else {
      // 无危机关键词，直接发布
      this.submitLeaf();
    }
  }

  private async submitLeaf(): Promise<void> {
    if (this.inputContent.trim().length === 0 || this.isSubmitting) {
      return;
    }

    this.isSubmitting = true;

    const nickname: string = this.inputNickname.trim().length > 0
      ? this.inputNickname.trim()
      : this.generateNickname();

    try {
      const response = await SharedForestService.submitLeaf(this.inputContent.trim(), nickname);

      if (response.responseCode === 200) {
        const aiRes: string = AIResponseGenerator.generate(this.inputContent);
        this.aiResponse = aiRes;
        this.showAIResponse = true;
        this.inputContent = '';
        this.inputNickname = '';

        promptAction.showToast({ message: '已分享到共享森林' });
      } else {
        promptAction.showToast({ message: '发送失败，请重试' });
      }
    } catch (e) {
      console.error('SharedWrite', 'Submit failed');
      promptAction.showToast({ message: '网络错误，请检查校园网连接' });
    } finally {
      this.isSubmitting = false;
    }
  }

  build() {
    Stack() {
      Column() {
        this.TopBar()

        Scroll() {
          Column({ space: 16 }) {
            if (this.showAIResponse) {
              this.AIResponseCard()
            }

            Column({ space: 6 }) {
              Text('分享一段心情')
                .fontSize(26)
                .fontWeight(FontWeight.Bold)
                .fontColor(EchoColors.TEXT_PRIMARY)

              Text('它会以昵称或匿名的方式出现在共享森林')
                .fontSize(13)
                .fontColor(EchoColors.TEXT_SECONDARY)

              Text(this.isOnline ? '网络已连接' : '网络未连接，请检查后再发布')
                .fontSize(11)
                .fontColor(this.isOnline ? EchoColors.MINT_TEXT : EchoColors.PINK_TEXT)
                .margin({ top: 4 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Column({ space: 8 }) {
              Text('显示名称')
                .fontSize(13)
                .fontWeight(500)
                .fontColor(EchoColors.TEXT_SECONDARY)

              TextInput({ placeholder: '留空将自动生成匿名昵称', text: this.inputNickname })
                .fontSize(15)
                .maxLength(12)
                .height(48)
                .backgroundColor(EchoColors.SURFACE)
                .fontColor(EchoColors.TEXT_PRIMARY)
                .placeholderColor(EchoColors.TEXT_TERTIARY)
                .border({ width: 1, color: EchoColors.BORDER })
                .borderRadius(EchoRadius.SMALL)
                .onChange((value: string) => {
                  this.inputNickname = value;
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Column({ space: 8 }) {
              Text('想说的话')
                .fontSize(13)
                .fontWeight(500)
                .fontColor(EchoColors.TEXT_SECONDARY)

              Column() {
                TextArea({ placeholder: '今天有什么想分享的吗？', text: this.inputContent })
                  .fontSize(15)
                  .fontColor(EchoColors.TEXT_PRIMARY)
                  .placeholderColor(EchoColors.TEXT_TERTIARY)
                  .backgroundColor(Color.Transparent)
                  .height(180)
                  .maxLength(500)
                  .onChange((value: string) => {
                    this.inputContent = value;
                  })

                Row() {
                  Blank()
                  Text(this.inputContent.length.toString() + '/500')
                    .fontSize(11)
                    .fontColor(EchoColors.TEXT_TERTIARY)
                }
                .width('100%')
                .padding({ right: 12, bottom: 8 })
              }
              .width('100%')
              .backgroundColor(EchoColors.SURFACE)
              .border({ width: 1, color: EchoColors.BORDER })
              .borderRadius(EchoRadius.LARGE)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Column({ space: 7 }) {
              Text('发布说明')
                .fontSize(13)
                .fontWeight(600)
                .fontColor(EchoColors.MINT_TEXT)
              Text('不会显示账号信息；内容将在 7 天后自动消失；当前仅限校内网络访问。')
                .fontSize(12)
                .fontColor(EchoColors.TEXT_SECONDARY)
                .lineHeight(20)
            }
            .width('100%')
            .padding(16)
            .backgroundColor(EchoColors.MINT_SOFT)
            .borderRadius(EchoRadius.MEDIUM)
            .alignItems(HorizontalAlign.Start)

            Column({ space: 8 }) {
              Text('需要支持时')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(EchoColors.TEXT_PRIMARY)
              Text('如果你正在经历困难，记得你不是一个人')
                .fontSize(13)
                .fontColor(EchoColors.TEXT_SECONDARY)
              Text(CRISIS_HELP_INFO.name + '  ' + CRISIS_HELP_INFO.hotline)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(EchoColors.PRIMARY_DARK)
            }
            .width('100%')
            .padding(16)
            .backgroundColor(EchoColors.PRIMARY_SOFT)
            .borderRadius(EchoRadius.MEDIUM)
            .alignItems(HorizontalAlign.Start)

            Button(this.isSubmitting ? '正在发布…' : '发布到共享森林')
              .width('100%')
              .height(52)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .backgroundColor(this.inputContent.trim().length > 0 && this.isOnline
                ? EchoColors.PRIMARY : EchoColors.TEXT_TERTIARY)
              .borderRadius(EchoRadius.MEDIUM)
              .enabled(this.inputContent.trim().length > 0 && this.isOnline && !this.isSubmitting)
              .onClick(() => {
                this.handleSubmit();
              })
          }
          .width('100%')
          .padding({ left: EchoSpacing.PAGE, right: EchoSpacing.PAGE, top: 18, bottom: 36 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(EchoColors.PAGE)

      if (this.showCrisisDialog) {
        this.SevereCrisisDialog()
      }

      if (this.showMildWarning) {
        this.MildWarningDialog()
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  // ==================== 严重危机弹窗 ====================
  @Builder
  SevereCrisisDialog() {
    // 遮罩层
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0,0,0,0.6)')

    // 弹窗内容
    Column({ space: 18 }) {

      Text('我们很担心你')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1B5E20')

      Text('检测到你可能正在经历非常困难的时刻。\n你的感受很重要，我们希望能帮助你。')
        .fontSize(14)
        .fontColor('#555555')
        .textAlign(TextAlign.Center)
        .lineHeight(24)

      // 援助信息卡片
      Column({ space: 10 }) {
        Text(CRISIS_HELP_INFO.message)
          .fontSize(14)
          .fontColor('#333333')
          .textAlign(TextAlign.Center)
          .lineHeight(22)

        Column({ space: 4 }) {
          Text(CRISIS_HELP_INFO.name)
            .fontSize(14)
            .fontColor('#4CAF50')
            .fontWeight(FontWeight.Medium)

          Text(CRISIS_HELP_INFO.hotline)
            .fontSize(22)
            .fontColor('#1B5E20')
            .fontWeight(FontWeight.Bold)

          Text(CRISIS_HELP_INFO.available + '在线')
            .fontSize(12)
            .fontColor('#888888')
        }
      }
      .width('100%')
      .padding(18)
      .backgroundColor('#E8F5E9')
      .borderRadius(14)

      // 额外资源
      Column({ space: 8 }) {
        Text('其他求助方式')
          .fontSize(13)
          .fontColor('#666666')

        Row({ space: 16 }) {
          Column({ space: 4 }) {
            Text('全国心理援助')
              .fontSize(11)
              .fontColor('#666666')
            Text('400-161-9995')
              .fontSize(12)
              .fontColor('#333333')
              .fontWeight(FontWeight.Medium)
          }
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#FAFAFA')
      .borderRadius(12)

      // 按钮
      Column({ space: 10 }) {
        Button('我想和专业人员聊聊')
          .width('100%')
          .height(48)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .backgroundColor('#4CAF50')
          .borderRadius(24)
          .onClick(() => {
            // 这里可以集成拨打电话功能
            promptAction.showToast({ message: '请拨打: ' + CRISIS_HELP_INFO.hotline });
          })

        Button('我现在感觉好一些了')
          .width('100%')
          .height(44)
          .fontSize(14)
          .backgroundColor('#E8F5E9')
          .fontColor('#4CAF50')
          .borderRadius(22)
          .onClick(() => {
            this.showCrisisDialog = false;
            this.inputContent = '';
          })
      }
      .width('100%')

      Text('为了保护你，这条内容暂时无法发布')
        .fontSize(11)
        .fontColor('#999999')
    }
    .width('90%')
    .padding(26)
    .backgroundColor(Color.White)
    .borderRadius(24)
    .position({ x: '5%', y: '10%' })
  }

  // ==================== 轻度关怀弹窗 ====================
  @Builder
  MildWarningDialog() {
    // 遮罩层
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0,0,0,0.5)')
      .onClick(() => {
        this.showMildWarning = false;
      })

    // 弹窗内容
    Column({ space: 16 }) {

      Text('我们注意到了')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1B5E20')

      Text('看起来你可能正在经历一些压力或困扰。\n无论发生什么，记得有人关心你。')
        .fontSize(14)
        .fontColor('#555555')
        .textAlign(TextAlign.Center)
        .lineHeight(22)

      // 援助信息
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text('需要倾诉？')
            .fontSize(12)
            .fontColor('#666666')
        }

        Column({ space: 2 }) {
          Text(CRISIS_HELP_INFO.name)
            .fontSize(13)
            .fontColor('#4CAF50')
          Text(CRISIS_HELP_INFO.hotline)
            .fontSize(15)
            .fontColor('#1B5E20')
            .fontWeight(FontWeight.Medium)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#E8F5E9')
      .borderRadius(12)
      .justifyContent(FlexAlign.Center)

      // 按钮
      Row({ space: 12 }) {
        Button('继续发布')
          .layoutWeight(1)
          .height(46)
          .fontSize(14)
          .backgroundColor('#E8F5E9')
          .fontColor('#4CAF50')
          .borderRadius(23)
          .onClick(() => {
            this.showMildWarning = false;
            this.submitLeaf();
          })

        Button('重新编辑')
          .layoutWeight(1)
          .height(46)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .backgroundColor('#4CAF50')
          .borderRadius(23)
          .onClick(() => {
            this.showMildWarning = false;
          })
      }
      .width('100%')

      Text('你可以随时寻求帮助')
        .fontSize(12)
        .fontColor('#888888')
    }
    .width('88%')
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius(22)
    .position({ x: '6%', y: '22%' })
  }

  @Builder
  TopBar() {
    Row() {
      Text('‹')
        .fontSize(28)
        .fontWeight(600)
        .fontColor(EchoColors.TEXT_PRIMARY)
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .backgroundColor(EchoColors.SURFACE)
        .border({ width: 1, color: EchoColors.BORDER })
        .borderRadius(EchoRadius.PILL)
        .onClick(() => {
          router.back();
        })

      Blank()

      Text('共享森林')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(EchoColors.TEXT_PRIMARY)

      Blank()

      Column()
        .width(40)
        .height(40)
    }
    .width('100%')
    .padding({ left: EchoSpacing.PAGE, right: EchoSpacing.PAGE, top: 16, bottom: 8 })
  }

  @Builder
  AIResponseCard() {
    Column({ space: 8 }) {
      Row() {
        Text('给你的回应')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(EchoColors.MINT_TEXT)
        Blank()
        Text('关闭')
          .fontSize(11)
          .fontColor(EchoColors.TEXT_TERTIARY)
      }
      .width('100%')

      Text(this.aiResponse)
        .fontSize(14)
        .fontColor(EchoColors.TEXT_SECONDARY)
        .lineHeight(23)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(EchoColors.MINT_SOFT)
    .borderRadius(EchoRadius.LARGE)
    .onClick(() => {
      this.showAIResponse = false;
    })
  }
}

