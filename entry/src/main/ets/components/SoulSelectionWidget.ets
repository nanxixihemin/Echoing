import { ColorConstants } from '../utils/ColorConstants';

interface Reason {
  id: string;
  text: string;
  weight: number; 
}

@Component
export struct SoulSelectionWidget {
  onResult: (result: string) => void = (result: string): void => {};
  onClose: () => void = (): void => {};

  @State choiceA: string = '';
  @State choiceB: string = '';
  @State reasonsA: Reason[] = [];
  @State reasonsB: Reason[] = [];

  @State showAddReason: boolean = false;
  @State addingTo: string = 'A';
  @State currentReasonText: string = '';
  @State currentWeight: number = 3;

  @State scoreA: number = 0;
  @State scoreB: number = 0;
  @State balanceAngle: number = 0;

  private refreshBalance() {
    this.scoreA = this.reasonsA.reduce((sum, r) => sum + r.weight, 0);
    this.scoreB = this.reasonsB.reduce((sum, r) => sum + r.weight, 0);
    let diff = this.scoreB - this.scoreA; 
    let angle = diff * 4; 
    if (angle > 20) angle = 20;
    if (angle < -20) angle = -20;
    this.balanceAngle = angle;
  }

  addReason() {
    if (this.currentReasonText.trim() === '') return;
    const r: Reason = {
      id: new Date().getTime().toString(),
      text: this.currentReasonText,
      weight: this.currentWeight
    };
    if (this.addingTo === 'A') {
      this.reasonsA.push(r);
    } else {
      this.reasonsB.push(r);
    }
    
    this.refreshBalance();
    
    this.showAddReason = false;
    this.currentReasonText = '';
    this.currentWeight = 3;
  }

  build() {
    Stack() {
      // 模糊遮罩层
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(ColorConstants.BACKGROUND_DARK)
        .opacity(0.95)
        .onClick((): void => { this.onClose(); })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column() {
        Text('灵魂天平 - 权衡 A 与 B')
          .fontSize(20)
          .fontColor(ColorConstants.TEXT_PRIMARY)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 60, bottom: 20 })

        // 选项输入区
        Row({ space: 16 }) {
          TextInput({ placeholder: '输入选项 A...', text: this.choiceA })
            .width('40%')
            .onChange((v: string): void => { this.choiceA = v; })
            .backgroundColor(ColorConstants.SURFACE_CARD)
            .fontColor(ColorConstants.MINT_CYAN)
          Text('VS').fontColor(ColorConstants.TEXT_SECONDARY)
          TextInput({ placeholder: '输入选项 B...', text: this.choiceB })
            .width('40%')
            .onChange((v: string): void => { this.choiceB = v; })
            .backgroundColor(ColorConstants.SURFACE_CARD)
            .fontColor(ColorConstants.MINT_CYAN)
        }
        .margin({ bottom: 40 })

        // 天平视觉核心区
        Column() {
          Row() {
            Text('权重: ' + this.scoreA.toString()).fontColor(ColorConstants.TEXT_SECONDARY).fontSize(12)
            Blank()
            Text('权重: ' + this.scoreB.toString()).fontColor(ColorConstants.TEXT_SECONDARY).fontSize(12)
          }
          .width('60%')
          .padding({ left: 10, right: 10, bottom: 8 })

          Row()
            .width('60%')
            .height(8)
            .backgroundColor(ColorConstants.BORDER_COLOR)
            .borderRadius(4)
            .rotate({ z: 1, angle: this.balanceAngle, centerX: '50%', centerY: '50%' })
            .animation({ duration: 600, curve: Curve.FastOutSlowIn })
          
          Stack() {
            Circle({ width: 14, height: 14 })
              .fill(ColorConstants.MINT_CYAN)
              .margin({ top: -3 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ bottom: 40 })

        // 理由列表区
        Row({ space: 16 }) {
          // A side
          Column() {
            Button('+ 加重磅 (A)')
              .height(30)
              .backgroundColor(ColorConstants.SURFACE_CARD)
              .fontColor(ColorConstants.TEXT_PRIMARY)
              .onClick((): void => { this.addingTo = 'A'; this.showAddReason = true; })
            ForEach(this.reasonsA, (r: Reason) => {
              Text(`${r.text} (+${r.weight})`)
                .fontSize(10).fontColor(ColorConstants.MINT_CYAN).margin({ top: 8 })
            }, (r: Reason) => r.id)
          }.width('40%').alignItems(HorizontalAlign.Center)

          // B side
          Column() {
            Button('+ 加重磅 (B)')
              .height(30)
              .backgroundColor(ColorConstants.SURFACE_CARD)
              .fontColor(ColorConstants.TEXT_PRIMARY)
              .onClick((): void => { this.addingTo = 'B'; this.showAddReason = true; })
            ForEach(this.reasonsB, (r: Reason) => {
              Text(`${r.text} (+${r.weight})`)
                .fontSize(10).fontColor(ColorConstants.MINT_CYAN).margin({ top: 8 })
            }, (r: Reason) => r.id)
          }.width('40%').alignItems(HorizontalAlign.Center)
        }.width('100%').justifyContent(FlexAlign.Center).layoutWeight(1)

        if (this.scoreA > 0 || this.scoreB > 0) {
           Button(`就选它了: ${this.scoreA >= this.scoreB ? this.choiceA : this.choiceB}`)
             .height(44)
             .width('60%')
             .backgroundColor(ColorConstants.MINT_CYAN)
             .fontColor(ColorConstants.BACKGROUND_DARK)
             .fontWeight(FontWeight.Bold)
             .borderRadius(22)
             .shadow({ radius: 10, color: 'rgba(0, 240, 255, 0.2)' })
             .margin({ bottom: 60 })
             .onClick((): void => {
               this.onResult(this.scoreA >= this.scoreB ? this.choiceA : this.choiceB);
             })
        }
      }
      .width('100%')
      .height('100%')

      // Modal
      if (this.showAddReason) {
         Stack() {
           Column()
             .width('100%')
             .height('100%')
             .backgroundColor('#000000')
             .opacity(0.8)
             .onClick((): void => { this.showAddReason = false; })
             
           Column() {
             Text(`为什么选项 ${this.addingTo === 'A' ? this.choiceA || 'A' : this.choiceB || 'B'} 值得选？`)
               .fontColor(ColorConstants.TEXT_PRIMARY).margin({ bottom: 16 }).fontSize(14)
             TextInput({ placeholder: '例如：离家更近...', text: this.currentReasonText })
               .onChange((v: string): void => { this.currentReasonText = v; })
               .backgroundColor(ColorConstants.BACKGROUND_DARK)
               .fontColor(ColorConstants.TEXT_PRIMARY)
             
             Row() {
               Text(`在意程度: ${this.currentWeight}`).fontColor(ColorConstants.TEXT_SECONDARY).fontSize(14)
               Slider({ value: this.currentWeight, min: 1, max: 10, step: 1 })
                 .onChange((v: number): void => { this.currentWeight = v; })
                 .width('60%')
             }.margin({ top: 16, bottom: 20 })

             Button('放入天平')
               .backgroundColor(ColorConstants.MINT_CYAN)
               .fontColor(ColorConstants.BACKGROUND_DARK)
               .onClick((): void => { this.addReason(); })
           }
           .width('80%')
           .padding(20)
           .backgroundColor(ColorConstants.SURFACE_CARD)
           .borderRadius(16)
         }
      }

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
