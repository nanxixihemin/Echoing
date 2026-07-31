import { EchoColors, EchoRadius, EchoSpacing } from '../utils/EchoTheme';

@Component
export struct HomePrimaryActions {
  onWriteClick: () => void = (): void => {};
  onPrivateTreeClick: () => void = (): void => {};
  onSharedForestClick: () => void = (): void => {};

  build() {
    Column({ space: EchoSpacing.MEDIUM }) {
      Column({ space: 14 }) {
        Text('今日回声')
          .fontSize(13)
          .fontColor(EchoColors.PRIMARY)
        Text('不用急着成为更好的人，先允许自己被看见。')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(EchoColors.TEXT_PRIMARY)
          .lineHeight(30)
        Button('写下此刻')
          .height(44)
          .padding({ left: 20, right: 20 })
          .backgroundColor(EchoColors.PRIMARY)
          .fontColor(Color.White)
          .fontSize(15)
          .borderRadius(EchoRadius.PILL)
          .alignSelf(ItemAlign.Start)
          .onClick(this.onWriteClick)
      }
      .width('100%')
      .padding(20)
      .backgroundColor(EchoColors.SURFACE)
      .borderRadius(EchoRadius.LARGE)
      .border({ width: 1, color: EchoColors.BORDER })
      .alignItems(HorizontalAlign.Start)

      Row({ space: EchoSpacing.MEDIUM }) {
        this.EntryCard('私密树洞', '只属于你的情绪空间', EchoColors.PRIMARY_SOFT,
          EchoColors.PRIMARY_DARK, this.onPrivateTreeClick)
        this.EntryCard('共享森林', '匿名倾诉，也接住他人', EchoColors.MINT_SOFT,
          EchoColors.MINT_TEXT, this.onSharedForestClick)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  EntryCard(title: string, description: string, background: string, textColor: string,
    onClickAction: () => void) {
    Column() {
      Text(title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(textColor)
      Blank()
      Text(description)
        .fontSize(13)
        .fontColor(textColor)
        .opacity(0.82)
        .lineHeight(19)
        .maxLines(2)
    }
    .layoutWeight(1)
    .height(126)
    .padding(18)
    .backgroundColor(background)
    .borderRadius(EchoRadius.LARGE)
    .alignItems(HorizontalAlign.Start)
    .onClick(onClickAction)
  }
}
