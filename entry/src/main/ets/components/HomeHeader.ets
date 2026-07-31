import { EchoColors, EchoRadius } from '../utils/EchoTheme';

@Component
export struct HomeHeader {
  @Prop nickname: string = '';
  @Prop isLoggedIn: boolean = false;
  onProfileClick: () => void = (): void => {};

  build() {
    Row() {
      Column({ space: 6 }) {
        Text(this.isLoggedIn && this.nickname.length > 0 ? `晚上好，${this.nickname}` : '晚上好')
          .fontSize(14)
          .fontColor(EchoColors.TEXT_SECONDARY)
        Text('听见此刻的自己')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(EchoColors.TEXT_PRIMARY)
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Image($r('app.media.echoing_icon'))
        .width(44)
        .height(44)
        .borderRadius(EchoRadius.PILL)
        .border({ width: 1, color: EchoColors.BORDER })
        .onClick(this.onProfileClick)
    }
    .width('100%')
  }
}
