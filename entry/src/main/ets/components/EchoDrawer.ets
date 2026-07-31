import { EchoColors, EchoRadius, EchoSpacing } from '../utils/EchoTheme';
import { EchoTask } from '../models/EchoTask';

@Component
export struct EchoDrawer {
  @Link tasks: EchoTask[];
  onCompleteTask: (task: EchoTask) => void = (task: EchoTask): void => {};

  build() {
    Column() {
      Row()
        .width(40)
        .height(4)
        .backgroundColor(EchoColors.BORDER)
        .borderRadius(2)
        .margin({ top: 12, bottom: 20 })

      Column({ space: 5 }) {
        Text('待回应的事')
          .fontColor(EchoColors.TEXT_PRIMARY)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
        Text(this.tasks.length > 0 ? '慢慢来，一件件回应就好' : '此刻没有需要处理的事情')
          .fontColor(EchoColors.TEXT_SECONDARY)
          .fontSize(13)
      }
      .width('88%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 16 })

      if (this.tasks.length === 0) {
        Column({ space: EchoSpacing.SMALL }) {
          Text('安静地感受现在')
            .fontSize(15)
            .fontColor(EchoColors.TEXT_PRIMARY)
          Text('新的回声会在需要时出现')
            .fontSize(13)
            .fontColor(EchoColors.TEXT_SECONDARY)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: EchoSpacing.SMALL }) {
          ForEach(this.tasks, (task: EchoTask) => {
            ListItem() {
              Row() {
                Checkbox()
                  .select(task.is_completed)
                  .selectedColor(EchoColors.PRIMARY)
                  .onChange((value: boolean): void => {
                    if (value) {
                      this.onCompleteTask(task);
                    }
                  })

                Column({ space: 4 }) {
                  if (task.seed_id) {
                    Text(`来自记录 #${task.seed_id}`)
                      .fontSize(11)
                      .fontColor(EchoColors.TEXT_TERTIARY)
                  }
                  Text(task.action)
                    .fontColor(EchoColors.TEXT_PRIMARY)
                    .fontSize(14)
                    .lineHeight(21)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: 12 })
              }
              .width('100%')
              .padding(16)
              .backgroundColor(EchoColors.PAGE)
              .borderRadius(EchoRadius.MEDIUM)
              .border({ width: 1, color: EchoColors.BORDER })
            }
          }, (task: EchoTask, index: number) => task.id ? task.id.toString() : index.toString())
        }
        .width('88%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EchoColors.SURFACE)
    .borderRadius({ topLeft: EchoRadius.LARGE, topRight: EchoRadius.LARGE })
    .alignItems(HorizontalAlign.Center)
  }
}
