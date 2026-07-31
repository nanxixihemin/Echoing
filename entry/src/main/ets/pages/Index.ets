import { DatabaseService } from '../utils/DatabaseService';
import { EchoColors, EchoRadius, EchoSpacing } from '../utils/EchoTheme';
import { EchoTask } from '../models/EchoTask';
import { Seed } from '../models/Seed';
import { EchoDrawer } from '../components/EchoDrawer';
import { SpinnerWidget } from '../components/SpinnerWidget';
import { IntrospectionWidget } from '../components/IntrospectionWidget';
import { HomeHeader } from '../components/HomeHeader';
import { HomePrimaryActions } from '../components/HomePrimaryActions';
import { HomeToolShelf } from '../components/HomeToolShelf';
import common from '@ohos.app.ability.common';
import router from '@ohos.router';

@Entry
@Component
struct Index {
  @State pendingTasks: EchoTask[] = [];
  @State showDrawer: boolean = false;
  @State activeTool: string = 'none';
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

  async handleSpinnerResult(result: string) {
    this.activeTool = 'none';
    await this.saveToolResult('今天的小决定', 'SPINNER', result);
  }

  async handleIntroResult(result: string) {
    this.activeTool = 'none';
    await this.saveToolResult('一次向内的观察', 'INTROSPECTION', '留意今天的感受：' + result);
  }

  async saveToolResult(content: string, source: 'SPINNER' | 'CHOICE' | 'INTROSPECTION', action: string) {
    if (!this.dbService) return;
    const seed: Seed = {
      content: content,
      source: source,
      state: 1,
      created_at: Date.now()
    };
    const seedId = await this.dbService.insertSeed(seed);
    const task: EchoTask = {
      seed_id: seedId,
      action: action,
      is_completed: false,
      created_at: Date.now()
    };
    await this.dbService.insertTask(task);
    await this.loadTasks();
    this.showDrawer = true;
  }

  async handleComplete(task: EchoTask) {
    if (!this.dbService || task.id === undefined) return;
    const isUpdated = await this.dbService.markTaskCompleted(task.id, Date.now());
    if (isUpdated) {
      await this.loadTasks();
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.activeTool === 'none') {
        Column() {
          Scroll() {
            Column({ space: EchoSpacing.SECTION }) {
              HomeHeader({
                nickname: this.userNickname,
                isLoggedIn: this.isLoggedIn,
                onProfileClick: (): void => {
                  router.pushUrl({ url: 'pages/LoginPage' });
                }
              })

              HomePrimaryActions({
                onWriteClick: (): void => {
                  router.pushUrl({ url: 'pages/PrivateWrite' });
                },
                onPrivateTreeClick: (): void => {
                  router.pushUrl({ url: 'pages/PrivateTree' });
                },
                onSharedForestClick: (): void => {
                  router.pushUrl({ url: 'pages/SharedForest' });
                }
              })

              HomeToolShelf({
                onTarotClick: (): void => {
                  router.pushUrl({ url: 'pages/TarotView' });
                },
                onSpinnerClick: (): void => {
                  this.activeTool = 'spinner';
                },
                onChoiceClick: (): void => {
                  router.pushUrl({ url: 'pages/FunChoiceView' });
                },
                onReflectClick: (): void => {
                  this.activeTool = 'intro';
                },
                onAiClick: (): void => {
                  router.pushUrl({ url: 'pages/AIDialogPage' });
                }
              })

              Row() {
                Column({ space: 5 }) {
                  Text('正念树')
                    .fontSize(17)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(EchoColors.TEXT_PRIMARY)
                  Text('每天留一点时间，照顾自己的内心')
                    .fontSize(13)
                    .fontColor(EchoColors.TEXT_SECONDARY)
                }
                .alignItems(HorizontalAlign.Start)

                Blank()

                Text('进入')
                  .fontSize(13)
                  .fontColor(EchoColors.PRIMARY)
              }
              .width('100%')
              .padding(18)
              .backgroundColor(EchoColors.SURFACE)
              .borderRadius(EchoRadius.LARGE)
              .border({ width: 1, color: EchoColors.BORDER })
              .onClick((): void => {
                router.pushUrl({ url: 'pages/ZzuMindfulTree' });
              })

              Blank().height(86)
            }
            .width('100%')
            .padding({
              left: EchoSpacing.PAGE,
              right: EchoSpacing.PAGE,
              top: 54
            })
          }
          .scrollBar(BarState.Off)
          .width('100%')
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(EchoColors.PAGE)
        .onClick((): void => {
          if (this.showDrawer) this.showDrawer = false;
        })

        if (!this.showDrawer) {
          Row() {
            Column({ space: 3 }) {
              Text(this.pendingTasks.length > 0 ? `${this.pendingTasks.length} 件事等你回应` : '此刻没有待办')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(EchoColors.TEXT_PRIMARY)
              Text(this.pendingTasks.length > 0 ? '轻触查看' : '安心感受现在')
                .fontSize(12)
                .fontColor(EchoColors.TEXT_SECONDARY)
            }
            .alignItems(HorizontalAlign.Start)

            Blank()

            Text('展开')
              .fontSize(13)
              .fontColor(EchoColors.PRIMARY)
          }
          .width('88%')
          .height(62)
          .padding({ left: 18, right: 18 })
          .margin({ bottom: 18 })
          .backgroundColor(EchoColors.SURFACE)
          .borderRadius(EchoRadius.LARGE)
          .border({ width: 1, color: EchoColors.BORDER })
          .onClick((): void => {
            this.showDrawer = true;
          })
        } else {
          Column() {
            EchoDrawer({
              tasks: $pendingTasks,
              onCompleteTask: (task: EchoTask): void => {
                this.handleComplete(task);
              }
            })
          }
          .width('100%')
          .height('62%')
          .padding({ top: 8 })
          .backgroundColor(EchoColors.SURFACE)
          .borderRadius({ topLeft: EchoRadius.LARGE, topRight: EchoRadius.LARGE })
          .transition({ type: TransitionType.Insert, translate: { y: 260 } })
          .transition({ type: TransitionType.Delete, translate: { y: 520 } })
        }
      }

      if (this.activeTool === 'spinner') {
        SpinnerWidget({
          onResult: (result: string): void => {
            this.handleSpinnerResult(result);
          },
          onClose: (): void => {
            this.activeTool = 'none';
          }
        })
      }

      if (this.activeTool === 'intro') {
        IntrospectionWidget({
          onResult: (result: string): void => {
            this.handleIntroResult(result);
          },
          onClose: (): void => {
            this.activeTool = 'none';
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EchoColors.PAGE)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
