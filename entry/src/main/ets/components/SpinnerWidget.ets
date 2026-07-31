import { EchoColors, EchoRadius } from '../utils/EchoTheme';

@Component
export struct SpinnerWidget {
  onResult: (result: string) => void = (result: string): void => {};
  onClose: () => void = (): void => {};

  @State rotationAngle: number = 0;
  @State resultText: string = '';
  @State isSpinning: boolean = false;

  private options: string[] = [
    '好好吃一顿饭',
    '出去走一小圈',
    '安静读半小时书',
    '换个地方透透气',
    '玩一会儿再继续',
    '允许自己休息一下'
  ];

  spin() {
    if (this.isSpinning) return;
    this.isSpinning = true;
    this.resultText = '';
    const turns = Math.floor(Math.random() * 8) + 8;
    const randomExtraAngle = Math.floor(Math.random() * 360);
    const targetAngle = this.rotationAngle + (360 * turns) + randomExtraAngle;

    animateTo({
      duration: 3500,
      curve: Curve.FastOutSlowIn,
      onFinish: (): void => {
        this.isSpinning = false;
        const hitIndex = Math.floor(Math.random() * this.options.length);
        this.resultText = this.options[hitIndex];
      }
    }, (): void => {
      this.rotationAngle = targetAngle;
    });
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(EchoColors.PAGE)
        .onClick((): void => {
          if (!this.isSpinning) this.onClose();
        })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column({ space: 24 }) {
        Column({ space: 6 }) {
          Text('帮我做个小决定')
            .fontSize(24)
            .fontColor(EchoColors.TEXT_PRIMARY)
            .fontWeight(FontWeight.Bold)
          Text('转动一下，把犹豫暂时交给随机')
            .fontSize(13)
            .fontColor(EchoColors.TEXT_SECONDARY)
        }
        .alignItems(HorizontalAlign.Center)

        Stack() {
          Circle({ width: 260, height: 260 })
            .fill(EchoColors.SURFACE)
            .stroke(EchoColors.BORDER)
            .strokeWidth(2)

          Path()
            .commands('M 130 0 L 130 260 M 0 130 L 260 130')
            .stroke(EchoColors.BORDER)
            .strokeWidth(1)

          Path()
            .commands('M 38 38 L 222 222 M 222 38 L 38 222')
            .stroke(EchoColors.BORDER)
            .strokeWidth(1)

          Circle({ width: 240, height: 240 })
            .fill('transparent')
            .strokeDashArray([10, 20])
            .stroke(EchoColors.PRIMARY)
            .strokeWidth(4)
            .rotate({ angle: this.rotationAngle })

          Circle({ width: 82, height: 82 })
            .fill(EchoColors.PRIMARY)
            .onClick((): void => {
              this.spin();
            })

          Text(this.isSpinning ? '转动中' : '开始')
            .fontSize(14)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
            .onClick((): void => {
              this.spin();
            })
        }

        Column({ space: 12 }) {
          if (this.resultText !== '') {
            Text('不妨试试')
              .fontSize(13)
              .fontColor(EchoColors.TEXT_SECONDARY)
              .transition({ type: TransitionType.Insert, opacity: 1 })

            Text(this.resultText)
              .fontSize(25)
              .fontColor(EchoColors.TEXT_PRIMARY)
              .fontWeight(FontWeight.Bold)
              .transition({ type: TransitionType.Insert, opacity: 1 })

            Button('记下来')
              .height(44)
              .padding({ left: 24, right: 24 })
              .backgroundColor(EchoColors.PRIMARY)
              .fontColor(Color.White)
              .borderRadius(EchoRadius.PILL)
              .onClick((): void => {
                this.onResult(this.resultText);
              })
          }
        }
        .height(130)
      }
      .width('100%')
      .height('100%')
      .padding({ top: 110, left: 24, right: 24 })
      .alignItems(HorizontalAlign.Center)

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
        if (!this.isSpinning) this.onClose();
      })
      .position({ x: 16, y: 36 })
      .zIndex(99)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
