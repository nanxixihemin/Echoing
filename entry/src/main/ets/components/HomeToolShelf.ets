import { EchoColors, EchoRadius, EchoSpacing } from '../utils/EchoTheme';

@Component
export struct HomeToolShelf {
  onTarotClick: () => void = (): void => {};
  onSpinnerClick: () => void = (): void => {};
  onChoiceClick: () => void = (): void => {};
  onReflectClick: () => void = (): void => {};
  onAiClick: () => void = (): void => {};

  build() {
    Column({ space: EchoSpacing.MEDIUM }) {
      Text('放松一下')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(EchoColors.TEXT_PRIMARY)
        .width('100%')

      Scroll() {
        Row({ space: EchoSpacing.SMALL }) {
          this.ToolCard('塔罗', '获得一点指引', EchoColors.PRIMARY_SOFT, this.onTarotClick)
          this.ToolCard('转盘', '替你做个决定', EchoColors.WARM_SOFT, this.onSpinnerClick)
          this.ToolCard('趣味选择', '听听第一直觉', EchoColors.PINK_SOFT, this.onChoiceClick)
          this.ToolCard('自我探索', '慢慢靠近内心', EchoColors.MINT_SOFT, this.onReflectClick)
          this.ToolCard('对话陪伴', '有人听你慢慢说', EchoColors.SURFACE, this.onAiClick)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ToolCard(title: string, description: string, background: string, onClickAction: () => void) {
    Column({ space: 8 }) {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(EchoColors.TEXT_PRIMARY)
      Text(description)
        .fontSize(12)
        .fontColor(EchoColors.TEXT_SECONDARY)
        .maxLines(1)
    }
    .width(130)
    .height(82)
    .padding(14)
    .backgroundColor(background)
    .borderRadius(EchoRadius.MEDIUM)
    .border({ width: 1, color: EchoColors.BORDER })
    .alignItems(HorizontalAlign.Start)
    .onClick(onClickAction)
  }
}
