import { EchoColors, EchoRadius } from '../utils/EchoTheme';

@Component
export struct IntrospectionWidget {
  onResult: (result: string) => void = (result: string): void => {};
  onClose: () => void = (): void => {};

  @State currentStep: number = 0;
  @State answers: string[] = ['', '', '', ''];
  @State currentInput: string = '';
  @State inputHint: string = '';

  private questions: string[] = [
    '此刻，是什么一直牵动着你的思绪？',
    '如果暂时放下别人的眼光，这件事对你真正意味着什么？',
    '如果什么都不做，最担心的结果是什么？它真的无法承受吗？',
    '不需要完整计划，今天能走出的最小一步是什么？'
  ];

  nextStep() {
    const answer = this.currentInput.trim();
    if (answer === '') {
      this.inputHint = '先写下一点此刻浮现的答案。';
      return;
    }
    this.answers[this.currentStep] = answer;
    this.currentInput = '';
    this.inputHint = '';

    if (this.currentStep < this.questions.length - 1) {
      animateTo({ duration: 300, curve: Curve.EaseOut }, (): void => {
        this.currentStep++;
      });
    } else {
      this.onResult(this.answers[3]);
    }
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(EchoColors.PAGE)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column({ space: 20 }) {
        Column({ space: 6 }) {
          Text('向内看一会儿')
            .fontSize(24)
            .fontColor(EchoColors.TEXT_PRIMARY)
            .fontWeight(FontWeight.Bold)
          Text(`第 ${this.currentStep + 1} 步，共 ${this.questions.length} 步`)
            .fontSize(13)
            .fontColor(EchoColors.TEXT_SECONDARY)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Row({ space: 6 }) {
          ForEach(this.questions, (_question: string, index: number) => {
            Row()
              .height(4)
              .layoutWeight(1)
              .backgroundColor(index <= this.currentStep ? EchoColors.PRIMARY : EchoColors.BORDER)
              .borderRadius(2)
          }, (_question: string, index: number) => index.toString())
        }
        .width('100%')

        List({ space: 12 }) {
          ForEach(this.questions.slice(0, this.currentStep + 1), (question: string, index: number) => {
            ListItem() {
              Column({ space: 10 }) {
                Text(question)
                  .fontSize(15)
                  .lineHeight(23)
                  .fontColor(EchoColors.TEXT_PRIMARY)

                if (index < this.currentStep) {
                  Text(this.answers[index])
                    .fontSize(14)
                    .lineHeight(21)
                    .fontColor(EchoColors.TEXT_SECONDARY)
                    .padding(14)
                    .width('100%')
                    .backgroundColor(EchoColors.SURFACE)
                    .borderRadius(EchoRadius.MEDIUM)
                    .border({ width: 1, color: EchoColors.BORDER })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
            }
          }, (_question: string, index: number) => index.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        Column({ space: 12 }) {
          TextArea({ placeholder: '写下此刻浮现的答案', text: this.currentInput })
            .height(110)
            .backgroundColor(EchoColors.SURFACE)
            .fontColor(EchoColors.TEXT_PRIMARY)
            .placeholderColor(EchoColors.TEXT_TERTIARY)
            .borderRadius(EchoRadius.MEDIUM)
            .border({ width: 1, color: EchoColors.BORDER })
            .padding(16)
            .onChange((value: string): void => {
              this.currentInput = value;
              if (value.trim().length > 0) {
                this.inputHint = '';
              }
            })

          if (this.inputHint.length > 0) {
            Text(this.inputHint)
              .fontSize(12)
              .fontColor(EchoColors.PRIMARY)
              .width('100%')
          }

          Button(this.currentStep === this.questions.length - 1 ? '记下这一步' : '继续')
            .width('100%')
            .height(48)
            .backgroundColor(EchoColors.PRIMARY)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
            .borderRadius(EchoRadius.PILL)
            .onClick((): void => {
              this.nextStep();
            })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .padding({ top: 92, left: 24, right: 24, bottom: 28 })

      Row({ space: 5 }) {
        Text('‹')
          .fontSize(18)
          .fontColor(EchoColors.TEXT_PRIMARY)
        Text('返回')
          .fontSize(14)
          .fontColor(EchoColors.TEXT_PRIMARY)
      }
      .padding({ left: 12, right: 16, top: 7, bottom: 7 })
      .backgroundColor(EchoColors.SURFACE)
      .borderRadius(EchoRadius.PILL)
      .border({ width: 1, color: EchoColors.BORDER })
      .onClick((): void => {
        this.onClose();
      })
      .position({ x: 16, y: 36 })
      .zIndex(99)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
