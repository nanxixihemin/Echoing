import { ColorConstants } from '../utils/ColorConstants';

@Component
export struct SpinnerWidget {
  onResult: (result: string) => void = (result: string): void => {};
  onClose: () => void = (): void => {};

  @State rotationAngle: number = 0;
  @State resultText: string = '';
  @State isSpinning: boolean = false;
  
  // 预设选项（极简化决策）
  private options: string[] = ['奖励一顿大餐', '立刻去跑两圈', '坐下看半小时书', '去散步换个心情', '打盘游戏再说', '什么都不做'];

  spin() {
    if (this.isSpinning) return;
    this.isSpinning = true;
    this.resultText = '';

    // 转动 8 - 15 圈，外加一个随机角度
    const turns = Math.floor(Math.random() * 8) + 8;
    const randomExtraAngle = Math.floor(Math.random() * 360);
    const targetAngle = this.rotationAngle + (360 * turns) + randomExtraAngle;

    animateTo({
      duration: 3500,
      curve: Curve.FastOutSlowIn,
      onFinish: (): void => {
        this.isSpinning = false;
        // 计算中奖索引。这是一个简化逻辑：随机抽一个，与动画解耦。
        // 在严肃应用里需要严格计算角度，但这里的“命运”就由下面的随机数决定
        const hitIndex = Math.floor(Math.random() * this.options.length);
        this.resultText = this.options[hitIndex];
      }
    }, (): void => {
      this.rotationAngle = targetAngle;
    });
  }

  build() {
    Stack() {
      // 模糊遮罩层
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(ColorConstants.BACKGROUND_DARK)
        .opacity(0.95)
        .onClick((): void => {
          if (!this.isSpinning) this.onClose();
        })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 核心 UI
      Column() {
        Text('指尖命运轮盘')
          .fontSize(24)
          .fontColor(ColorConstants.TEXT_PRIMARY)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 40 })

        // 轮盘本体
        Stack() {
          // 底座
          Circle({ width: 260, height: 260 })
            .fill(ColorConstants.SURFACE_CARD)
            .stroke(ColorConstants.BORDER_COLOR)
            .strokeWidth(2)

          // 假装有几个切片的视觉（简化版，用交叉线模拟）
          Path()
            .commands('M 130 0 L 130 260 M 0 130 L 260 130')
            .stroke(ColorConstants.BORDER_COLOR)
            .strokeWidth(1)

          Path()
            .commands('M 38 38 L 222 222 M 222 38 L 38 222')
            .stroke(ColorConstants.BORDER_COLOR)
            .strokeWidth(1)

          // 核心指针/或者转动的图案
          Circle({ width: 240, height: 240 })
            .fill('transparent')
            .strokeDashArray([10, 20])
            .stroke(ColorConstants.MINT_CYAN)
            .strokeWidth(4)
            .rotate({ angle: this.rotationAngle })

          // 中央启动按钮
          Circle({ width: 80, height: 80 })
            .fill(ColorConstants.BACKGROUND_DARK)
            .stroke(ColorConstants.MINT_CYAN)
            .strokeWidth(this.isSpinning ? 0 : 3)
            .onClick((): void => {
              this.spin();
            })

          Text(this.isSpinning ? '...' : 'SPIN')
            .fontColor(ColorConstants.MINT_CYAN)
            .fontWeight(FontWeight.Bold)
            .onClick((): void => {
              this.spin();
            })
        }

        // 结果展示区
        Column() {
          if (this.resultText !== '') {
            Text('宇宙的建议是：')
              .fontSize(14)
              .fontColor(ColorConstants.TEXT_SECONDARY)
              .margin({ top: 40, bottom: 8 })
              .transition({ type: TransitionType.Insert, opacity: 1 })

            Text(this.resultText)
              .fontSize(28)
              .fontColor(ColorConstants.MINT_CYAN)
              .fontWeight(FontWeight.Bolder)
              .margin({ bottom: 24 })
              .transition({ type: TransitionType.Insert, opacity: 1 })

            Button('接受并转化为待办')
              .height(44)
              .width('60%')
              .backgroundColor(ColorConstants.MINT_CYAN)
              .fontColor(ColorConstants.BACKGROUND_DARK)
              .fontWeight(FontWeight.Bold)
              .borderRadius(22)
              .shadow({ radius: 10, color: 'rgba(0, 240, 255, 0.2)' })
              .onClick((): void => {
                this.onResult(this.resultText);
              })
          }
        }
        .height(150)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)

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
        .onClick((): void => {
          if (!this.isSpinning) this.onClose();
        })
      }
      .position({ x: 16, y: 36 })
      .zIndex(99)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
