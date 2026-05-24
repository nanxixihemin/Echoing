import { ColorConstants } from '../utils/ColorConstants';
import { DatabaseService } from '../utils/DatabaseService';
import { EchoTask } from '../models/EchoTask';
import { Seed } from '../models/Seed';
import { TreeHoleWidget } from '../components/TreeHoleWidget';
import { EchoDrawer } from '../components/EchoDrawer';
import { SpinnerWidget } from '../components/SpinnerWidget';
import { SoulSelectionWidget } from '../components/SoulSelectionWidget';
import { TarotWidget } from '../components/TarotWidget';
import { IntrospectionWidget } from '../components/IntrospectionWidget';
import common from '@ohos.app.ability.common';
import router from '@ohos.router';

@Entry
@Component
struct Index {
  @State pendingTasks: EchoTask[] = [];
  @State showDrawer: boolean = false;
  @State activeTool: string = 'none'; // 'none', 'spinner', 'tarot', etc.
  // 登录状态监听(只读绑定，由 LoginPage 更新)
  @StorageProp('isLoggedIn') isLoggedIn: boolean = false;
  @StorageProp('userNickname') userNickname: string = '';
  private dbService: DatabaseService | null = null;

  async aboutToAppear() {
    this.dbService = new DatabaseService(getContext(this) as common.UIAbilityContext);
    await this.dbService.init();
    await this.loadTasks();
  }

  async loadTasks() {
    if (this.dbService) {
      this.pendingTasks = await this.dbService.getPendingTasks();
    }
  }

  async handleNewSeed(content: string) {
    let seed: Seed = {
      content: content,
      source: 'TREE_HOLE',
      state: 1,
      created_at: new Date().getTime()
    };
    if (!this.dbService) return;
    let seedId = await this.dbService.insertSeed(seed);

    let task: EchoTask = {
      seed_id: seedId,
      action: '树洞回声: ' + content,
      is_completed: false,
      created_at: new Date().getTime()
    };
    await this.dbService.insertTask(task);

    await this.loadTasks();
    this.showDrawer = true;
  }

  async handleSpinnerResult(result: string) {
    this.activeTool = 'none';

    // 把转盘结果存为一个种子，并自动创建一条回声任务
    let seed: Seed = {
      content: '转盘抽取结果',
      source: 'SPINNER',
      state: 1,
      created_at: new Date().getTime()
    };
    if (!this.dbService) return;
    let seedId = await this.dbService.insertSeed(seed);

    let task: EchoTask = {
      seed_id: seedId,
      action: result, // 例如 "去散步"
      is_completed: false,
      created_at: new Date().getTime()
    };
    await this.dbService.insertTask(task);

    await this.loadTasks();
    this.showDrawer = true;
  }

  async handleSoulResult(result: string) {
    this.activeTool = 'none';
    let seed: Seed = {
      content: '灵魂选择结果',
      source: 'CHOICE',
      state: 1,
      created_at: new Date().getTime()
    };
    if (!this.dbService) return;
    let seedId = await this.dbService.insertSeed(seed);

    let task: EchoTask = {
      seed_id: seedId,
      action: '灵魂选择: ' + result,
      is_completed: false,
      created_at: new Date().getTime()
    };
    await this.dbService.insertTask(task);

    await this.loadTasks();
    this.showDrawer = true;
  }

  async handleTarotResult(result: string) {
    this.activeTool = 'none';
    let seed: Seed = {
      content: '塔罗占卜结果',
      source: 'TAROT',
      state: 1,
      created_at: new Date().getTime()
    };
    if (!this.dbService) return;
    let seedId = await this.dbService.insertSeed(seed);

    let task: EchoTask = {
      seed_id: seedId,
      action: '塔罗指引: ' + result,
      is_completed: false,
      created_at: new Date().getTime()
    };
    await this.dbService.insertTask(task);

    await this.loadTasks();
    this.showDrawer = true;
  }

  async handleIntroResult(result: string) {
    this.activeTool = 'none';
    let seed: Seed = {
      content: '内省探索结果',
      source: 'INTROSPECTION',
      state: 1,
      created_at: new Date().getTime()
    };
    if (!this.dbService) return;
    let seedId = await this.dbService.insertSeed(seed);

    let task: EchoTask = {
      seed_id: seedId,
      action: '内省感悟: ' + result,
      is_completed: false,
      created_at: new Date().getTime()
    };
    await this.dbService.insertTask(task);

    await this.loadTasks();
    this.showDrawer = true;
  }

  async handleComplete(task: EchoTask) {
    if (!this.dbService || task.id === undefined) {
      return;
    }
    const isUpdated = await this.dbService.markTaskCompleted(task.id, new Date().getTime());
    if (isUpdated) {
      await this.loadTasks();
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {

      if (this.activeTool === 'none') {
        Column() {
          Blank().height(140)

          Row({ space: 16 }) {
            this.MagicButton('\u5185\u7701', '#FF6B6B', (): void => {
              console.info('[Echoing] Clicked Introspection button, setting activeTool to intro');
              this.activeTool = 'intro';
            })
            this.MagicButton('\u7075\u9b42', '#FFD93D', (): void => {
              this.activeTool = 'soul';
            })
            this.MagicButton('\u8da3\u9009', '#B89CD4', (): void => {
              router.pushUrl({ url: 'pages/FunChoiceView' });
            })
            this.MagicButton('\u5854\u7f57', '#6BCB77', (): void => {
              router.pushUrl({ url: 'pages/TarotView' });
            })
            this.MagicButton('\u8f6c\u76d8', '#4D96FF', (): void => {
              this.activeTool = 'spinner';
            })
          }
          Blank().height(50)

          Column() {
            Row() {
              Column() {
                Text('\u6b63\u5ff5\u6811')
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(ColorConstants.TEXT_PRIMARY)
                  .margin({ bottom: 4 })
                Text('\u6bcf\u65e5\u6b63\u5ff5\u7ec3\u4e60\uff0c\u6ecb\u517b\u5185\u5fc3')
                  .fontSize(12)
                  .fontColor(ColorConstants.MINT_CYAN)
              }.alignItems(HorizontalAlign.Start)

              Blank()

              Text('->')
                .fontSize(20)
                .fontColor(ColorConstants.MINT_CYAN)
            }
            .width('100%')
            .padding(24)
            .backgroundColor(ColorConstants.SURFACE_GLASS)
            .borderRadius(20)
            .border({ width: 1, color: 'rgba(0, 240, 255, 0.2)' })
            .onClick((): void => {
              router.pushUrl({ url: 'pages/ZzuMindfulTree' })
            })
          }
          .width('90%')
          Blank()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(ColorConstants.BACKGROUND_DARK)
        .alignItems(HorizontalAlign.Center)
        .onClick((): void => {
          if (this.showDrawer) this.showDrawer = false;
        })

        Row() {
          Row({ space: 10 }) {
            Image($r('app.media.echoing_icon'))
              .width(40)
              .height(40)
              .borderRadius(20)
              .border({ width: 2, color: ColorConstants.MINT_CYAN })
              .shadow({ radius: 10, color: 'rgba(0, 240, 255, 0.2)' })

            Column() {
              Text('Echoing')
                .fontColor(ColorConstants.TEXT_PRIMARY)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .letterSpacing(2)
              Text(this.isLoggedIn && this.userNickname.length > 0 ? this.userNickname + ' \u00B7 \u8046\u542c\u5185\u5fc3\u7684\u56de\u54cd' : '\u8046\u542c\u5185\u5fc3\u7684\u56de\u54cd')
                .fontColor(ColorConstants.TEXT_SECONDARY)
                .fontSize(11)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
          }
          .padding({ left: 8, right: 12, top: 6, bottom: 6 })
          .borderRadius(22)
          .backgroundColor('rgba(22, 27, 34, 0.42)')
          .border({ width: 1, color: ColorConstants.MINT_CYAN_DIM })
          .onClick(() => {
            router.pushUrl({ url: 'pages/LoginPage' });
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 40 })
        .position({ x: 0, y: 0 })
        .zIndex(10)
      }
      // 底部抽屉
      Column() {
        if (!this.showDrawer) {
          Row()
            .width('30%')
            .height(6)
            .backgroundColor(ColorConstants.MINT_CYAN_DIM)
            .borderRadius(3)
            .margin({ bottom: 20 })
            .onClick((): void => {
              this.showDrawer = true;
            })
        } else {
          EchoDrawer({
            tasks: $pendingTasks,
            onCompleteTask: (task: EchoTask): void => { this.handleComplete(task); }
          })
          .height('60%')
          .transition({ type: TransitionType.Insert, translate: { y: 200 } })
          .transition({ type: TransitionType.Delete, translate: { y: 500 } })
        }
      }
      .width('100%')
      .animation({ duration: 400, curve: Curve.FastOutSlowIn })

      // 功能组件覆盖层
      if (this.activeTool === 'spinner') {
        SpinnerWidget({
          onResult: (result: string): void => { this.handleSpinnerResult(result); },
          onClose: (): void => { this.activeTool = 'none'; }
        })
        .transition({ type: TransitionType.Insert, opacity: 1 })
        .transition({ type: TransitionType.Delete, opacity: 0 })
      }

      if (this.activeTool === 'soul') {
        SoulSelectionWidget({
          onResult: (result: string): void => { this.handleSoulResult(result); },
          onClose: (): void => { this.activeTool = 'none'; }
        })
        .transition({ type: TransitionType.Insert, opacity: 1 })
        .transition({ type: TransitionType.Delete, opacity: 0 })
      }

      if (this.activeTool === 'tarot') {
        TarotWidget({
          onResult: (result: string): void => { this.handleTarotResult(result); },
          onClose: (): void => { this.activeTool = 'none'; }
        })
        .transition({ type: TransitionType.Insert, opacity: 1 })
        .transition({ type: TransitionType.Delete, opacity: 0 })
      }

      if (this.activeTool === 'intro') {
        IntrospectionWidget({
          onResult: (result: string): void => { this.handleIntroResult(result); },
          onClose: (): void => { this.activeTool = 'none'; }
        })
        .transition({ type: TransitionType.Insert, opacity: 1 })
        .transition({ type: TransitionType.Delete, opacity: 0 })
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor(ColorConstants.BACKGROUND_DARK)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder MagicButton(title: string, color: string, onClickAction: () => void) {
    Column() {
      Circle({ width: 48, height: 48 })
        .fill(ColorConstants.SURFACE_CARD)
        .stroke(color)
        .strokeWidth(2)
      Text(title)
        .fontSize(12)
        .fontColor(ColorConstants.TEXT_PRIMARY)
        .margin({ top: 8 })
    }
    .onClick(onClickAction)
  }
}
