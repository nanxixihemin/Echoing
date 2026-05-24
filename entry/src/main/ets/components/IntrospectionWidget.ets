import { ColorConstants } from '../utils/ColorConstants';

@Component
export struct IntrospectionWidget {
  onResult: (result: string) => void = (result: string): void => {};
  onClose: () => void = (): void => {};

  @State currentStep: number = 0;
  @State answers: string[] = ['', '', '', ''];
  @State currentInput: string = '';
  @State inputHint: string = '';

  private questions: string[] = [
    '沉下心来，剥开繁杂。此刻，究竟是什么在牵扯你的思绪？',
    '抛开外界甚至他人的眼光，这件事对你个人而言，真正的意义是什么？',
    '如果你什么都不做任由其发展，最坏的结果是什么？它真的有那么可怕、不可承受吗？',
    '不谈宏大的计划。如果只要打破当下的僵局，今天你能走出的【最小第一步】是什么？'
  ];

  aboutToAppear(): void {
    console.info('[Echoing] IntrospectionWidget aboutToAppear called');
  }

  nextStep() {
    const answer = this.currentInput.trim();
    console.info(`[Echoing] Introspection nextStep tapped, step=${this.currentStep}, answerLength=${answer.length}`);
    if (answer === '') {
      this.inputHint = '先写下一点此刻浮现的答案，再继续。';
      return;
    }
    this.answers[this.currentStep] = this.currentInput;
    this.currentInput = '';
    this.inputHint = '';
    
    if (this.currentStep < this.questions.length - 1) {
      animateTo({ duration: 400, curve: Curve.EaseOut }, (): void => {
        this.currentStep++;
      });
    } else {
      // 结束，将最小第一步化作待办
      this.onResult(this.answers[3]); 
    }
  }

  build() {
    Stack() {
      // 沉浸背景
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(ColorConstants.BACKGROUND_DARK)
        .opacity(0.98)
        .onClick((): void => { this.onClose(); })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column() {
        // 头部
        Text('问 鼎 初 心')
          .fontSize(24)
          .fontColor(ColorConstants.TEXT_PRIMARY)
          .fontWeight(FontWeight.Bold)
          .letterSpacing(6)
          .margin({ top: 60, bottom: 40 })

        // 问答流 (对话轴)
        List({ space: 24 }) {
           ForEach(this.questions.slice(0, this.currentStep + 1), (q: string, idx: number) => {
              ListItem() {
                 Column() {
                     // 系统提问
                     Text(`Q${idx + 1}: ` + q)
                        .fontSize(14)
                        .lineHeight(20)
                        .fontColor(ColorConstants.TEXT_SECONDARY)
                        .margin({ bottom: 12 })
                        .transition({ type: TransitionType.Insert, opacity: 1, translate: { y: 20 } })

                     // 用户回答
                     if (idx < this.currentStep) {
                        Text(this.answers[idx])
                          .fontSize(15)
                          .lineHeight(22)
                          .fontColor(ColorConstants.MINT_CYAN)
                          .padding(16)
                          .backgroundColor(ColorConstants.SURFACE_GLASS)
                          .borderRadius(16)
                          .margin({ bottom: 8 })
                          .transition({ type: TransitionType.Insert, opacity: 1 })
                     }
                 }
                 .alignItems(HorizontalAlign.Start)
                 .width('100%')
                 .padding({ left: 24, right: 24 })
              }
           })
        }
        .width('100%')
        .layoutWeight(1)

        // 底部输入交互区
        if (this.currentStep < this.questions.length) {
            Column() {
              TextArea({ placeholder: '在此写下浮现的答案...', text: this.currentInput })
                 .height(100)
                 .backgroundColor(ColorConstants.SURFACE_CARD)
                 .fontColor(ColorConstants.TEXT_PRIMARY)
                 .placeholderColor(ColorConstants.TEXT_SECONDARY)
                 .borderRadius(16)
                 .padding(16)
                 .onChange((v: string): void => {
                   this.currentInput = v;
                   if (v.trim().length > 0) {
                     this.inputHint = '';
                   }
                 })
                 .margin({ bottom: 20 })
              
              Button(this.currentStep === this.questions.length - 1 ? '点燃：转化行动微光' : '深呼吸，继续向内探索')
                 .width('100%')
                 .height(48)
                 .backgroundColor(this.currentStep === this.questions.length - 1 ? ColorConstants.MINT_CYAN : ColorConstants.TEXT_PRIMARY)
                 .fontColor(ColorConstants.BACKGROUND_DARK)
                 .fontWeight(FontWeight.Bold)
                 .borderRadius(24)
                 .onClick((): void => { this.nextStep(); })

              if (this.inputHint.length > 0) {
                Text(this.inputHint)
                  .fontSize(12)
                  .fontColor(ColorConstants.MINT_CYAN)
                  .margin({ top: 12 })
                  .width('100%')
              }
            }
            .width('100%')
            .padding({ left: 24, right: 24, bottom: 40 })
        }
      }
      .width('100%')
      .height('100%')

      // 沉浸式返回按键
      Row() {
        Row() {
          Text('‹').fontSize(18).fontColor(ColorConstants.TEXT_PRIMARY).margin({ right: 4 })
          Text('返回').fontSize(14).fontColor(ColorConstants.TEXT_PRIMARY)
        }
        .padding({ left: 12, right: 16, top: 6, bottom: 6 })
        .backgroundColor(ColorConstants.SURFACE_CARD)
        .borderRadius(16)
        .border({ width: 1, color: ColorConstants.BORDER_COLOR })
        .onClick((): void => { this.onClose(); })
      }
      .position({ x: 16, y: 36 })
      .zIndex(99)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
