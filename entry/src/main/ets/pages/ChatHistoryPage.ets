import router from '@ohos.router';
import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';
import picker from '@ohos.file.picker';
import fileUri from '@ohos.file.fileuri';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import { ChatHistoryManager, ChatSession } from '../service/ChatHistoryManager';
import { EchoColors, EchoRadius, EchoSpacing } from '../utils/EchoTheme';

interface HistoryRouterParams {
  refreshKey?: string;
}

@Entry
@Component
struct ChatHistoryPage {
  @State sessions: ChatSession[] = [];
  @State isLoading: boolean = true;
  @State exportMsg: string = '';
  // 多选模式
  @State isSelectMode: boolean = false;
  @State selectedIds: string[] = [];

  aboutToAppear() {
    this.loadSessions();
  }

  private async loadSessions(): Promise<void> {
    this.isLoading = true;
    try {
      const mgr = ChatHistoryManager.getInstance();
      const context = getContext(this) as common.UIAbilityContext;
      await mgr.initialize(context);
      this.sessions = await mgr.getAllSessions();
    } catch (e) {
      // ignore
    }
    this.isLoading = false;
  }

  private formatTime(timestamp: number): string {
    const d = new Date(timestamp);
    const month = d.getMonth() + 1;
    const day = d.getDate();
    const hour = d.getHours();
    const min = d.getMinutes();
    const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    return `${month}/${day} ${pad(hour)}:${pad(min)}`;
  }

  private isSelected(id: string): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  private toggleSelect(id: string): void {
    if (this.isSelected(id)) {
      let newIds: string[] = [];
      for (let i = 0; i < this.selectedIds.length; i++) {
        if (this.selectedIds[i] !== id) {
          newIds.push(this.selectedIds[i]);
        }
      }
      this.selectedIds = newIds;
    } else {
      let newIds: string[] = [];
      for (let i = 0; i < this.selectedIds.length; i++) {
        newIds.push(this.selectedIds[i]);
      }
      newIds.push(id);
      this.selectedIds = newIds;
    }
  }

  private selectAll(): void {
    let ids: string[] = [];
    for (let i = 0; i < this.sessions.length; i++) {
      ids.push(this.sessions[i].id);
    }
    this.selectedIds = ids;
  }

  private getSelectedSessions(): ChatSession[] {
    let result: ChatSession[] = [];
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.isSelected(this.sessions[i].id)) {
        result.push(this.sessions[i]);
      }
    }
    return result;
  }

  private formatExportText(list: ChatSession[]): string {
    if (list.length === 0) return '暂无记录可导出';

    let text = '【嵩月塔罗 · 占卜记录导出】\n';
    const now = new Date();
    const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    text += `导出时间：${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}\n`;
    text += `共${list.length} 条记录\n\n`;

    for (let i = 0; i < list.length; i++) {
      const s = list[i];
      const d = new Date(s.createdAt);
      const dateStr = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;

      text += `═ 第${i + 1} 条 ═\n`;
      text += `主题：${s.theme || '未设主题'}\n`;
      text += `摘要：${s.summary || '无摘要'}\n`;
      text += `时间：${dateStr}\n\n`;

      for (let j = 0; j < s.messages.length; j++) {
        const m = s.messages[j];
        const label = m.role === 'user' ? '你：' : 'AI：';
        text += `${label}${m.content}\n\n`;
      }
      text += '\n';
    }
    return text;
  }

  private showToast(msg: string): void {
    this.exportMsg = msg;
    setTimeout(() => {
      this.exportMsg = '';
    }, 2500);
  }

  build() {
    Column() {
      Row() {
        Text(this.isSelectMode ? '取消' : '‹')
          .fontSize(this.isSelectMode ? 13 : 28)
          .fontColor(this.isSelectMode ? EchoColors.PRIMARY_DARK : EchoColors.TEXT_PRIMARY)
          .fontWeight(FontWeight.Medium)
          .width(48)
          .height(40)
          .textAlign(TextAlign.Center)
          .backgroundColor(EchoColors.SURFACE)
          .border({ width: 1, color: EchoColors.BORDER })
          .borderRadius(EchoRadius.PILL)
          .onClick(() => {
            if (this.isSelectMode) {
              this.isSelectMode = false;
              this.selectedIds = [];
            } else {
              router.back();
            }
          })

        Text(this.isSelectMode ? `已选 ${this.selectedIds.length} 条` : '对话历史')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(EchoColors.TEXT_PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        if (!this.isSelectMode) {
          Text('管理')
            .fontSize(13)
            .fontColor(EchoColors.PRIMARY_DARK)
            .fontWeight(FontWeight.Medium)
            .width(48)
            .height(36)
            .textAlign(TextAlign.Center)
            .backgroundColor(EchoColors.PRIMARY_SOFT)
            .borderRadius(EchoRadius.PILL)
            .onClick(() => {
              this.isSelectMode = true;
              this.selectedIds = [];
            })
        } else {
          Text(this.selectedIds.length === this.sessions.length ? '取消全选' : '全选')
            .fontSize(12)
            .fontColor(EchoColors.PRIMARY_DARK)
            .fontWeight(FontWeight.Medium)
            .width(56)
            .height(36)
            .textAlign(TextAlign.Center)
            .backgroundColor(EchoColors.PRIMARY_SOFT)
            .borderRadius(EchoRadius.PILL)
            .onClick(() => {
              if (this.selectedIds.length === this.sessions.length) {
                this.selectedIds = [];
              } else {
                this.selectAll();
              }
            })
        }
      }
      .width('100%')
      .padding({ left: EchoSpacing.PAGE, right: EchoSpacing.PAGE, top: 16, bottom: 12 })
      .alignItems(VerticalAlign.Center)

      // 提示条
      if (this.exportMsg) {
        Text(this.exportMsg)
          .fontSize(13)
          .fontColor('#5A3A00')
          .backgroundColor('#E2F0CB')
          .border({ width: 1, color: '#B8D8A8', radius: 12 })
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .margin({ left: 16, right: 16, bottom: 4 })
      }

      // ========== 列表区 ==========
      if (this.isLoading) {
        Column() {
          Text("加载中…").fontSize(14).fontColor(EchoColors.TEXT_SECONDARY).margin({ top: 80 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
      } else if (this.sessions.length === 0) {
        Column() {
          Text("还没有对话记录").fontSize(16).fontColor(EchoColors.TEXT_SECONDARY).margin({ top: 80 })
          Text("开始一次对话后，会在这里继续回顾").fontSize(13).fontColor('#C4A76D').margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
      } else {
        List({ space: 12 }) {
          ForEach(
            this.sessions,
            (item: ChatSession) => {
              ListItem() {
                Row() {
                  // 选择模式：复选框
                  if (this.isSelectMode) {
                    Text(this.isSelected(item.id) ? "✓" : "○")
                      .fontSize(22)
                      .fontColor(this.isSelected(item.id) ? EchoColors.PRIMARY : '#C4A76D')
                      .margin({ right: 10 })
                      .onClick(() => {
                        this.toggleSelect(item.id);
                      })
                  }

                  Column({ space: 4 }) {
                    Text(item.summary || '未命名会话')
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(EchoColors.TEXT_PRIMARY)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .lineHeight(20)

                    Row({ space: 8 }) {
                      Text(this.formatTime(item.updatedAt || item.createdAt))
                        .fontSize(11)
                        .fontColor('#C4A76D')

                      Text(`${item.messages.length}条消息`)
                        .fontSize(11)
                        .fontColor(EchoColors.TEXT_SECONDARY)
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .backgroundColor(this.isSelectMode && this.isSelected(item.id)
                  ? EchoColors.PRIMARY_SOFT : EchoColors.SURFACE)
                .border({ width: 1, color: this.isSelectMode && this.isSelected(item.id)
                  ? EchoColors.PRIMARY : EchoColors.BORDER })
                .borderRadius(EchoRadius.MEDIUM)
                .padding({ left: 16, right: 16, top: 14, bottom: 14 })
                .onClick(() => {
                  if (this.isSelectMode) {
                    this.toggleSelect(item.id);
                  } else {
                    router.pushUrl({
                      url: 'pages/AIDialogPage',
                      params: { sessionId: item.id, theme: item.theme }
                    });
                  }
                })
              }
              .key(item.id)
              .swipeAction({
                end: this.DeleteBtn(item.id)
              })
            },
            (item: ChatSession) => item.id
          )
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }

      // ========== 底部操作栏（多选模式时显示） ==========
      if (this.isSelectMode && this.selectedIds.length > 0) {
        Row({ space: 12 }) {
          // 分享按钮（文件）
          Button("分享导出")
            .layoutWeight(1)
            .height(42)
            .borderRadius(21)
            .backgroundColor('#E2F0CB')
            .border({ width: 1.2, color: '#7B8794' })
            .fontColor(EchoColors.TEXT_PRIMARY)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .onClick(() => {
              this.doShareFile();
            })

          // 保存到本地文件
          Button("保存文件")
            .layoutWeight(1)
            .height(42)
            .borderRadius(21)
            .backgroundColor(EchoColors.SURFACE)
            .border({ width: 1.2, color: '#7B8794' })
            .fontColor(EchoColors.TEXT_PRIMARY)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .onClick(() => {
              this.doSaveFile();
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 10, bottom: 30 })
        .backgroundColor(EchoColors.PAGE)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EchoColors.PAGE)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  DeleteBtn(sessionId: string) {
    Button("删除")
      .width(72)
      .height('100%')
      .fontSize(14)
      .fontColor('#FFFFFF')
      .backgroundColor('#FF6B6B')
      .borderRadius(14)
      .onClick(async () => {
        const mgr = ChatHistoryManager.getInstance();
        await mgr.deleteSession(sessionId);
        await this.loadSessions();
      })
  }

  // 获取导出文本
  private getExportText(): string {
    const selected = this.getSelectedSessions();
    return this.formatExportText(selected);
  }

  // 分享 -- 通过系统分享面板
  private doShareFile(): void {
    try {
      const text = this.getExportText();

      const context = getContext(this) as common.UIAbilityContext;
      const now = new Date();
      const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
      const fileName = `tarot_${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}.txt`;
      const filePath = context.cacheDir + '/' + fileName;

      // 写入缓存文件
      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, text);
      fs.closeSync(file);

      // 获取 content URI
      const uri = fileUri.getUriFromPath(filePath);

      // 用ShareKit 调起系统分享
      const record: systemShare.SharedRecord = {
        utd: utd.UniformDataType.PLAIN_TEXT,
        uri: uri,
        title: '嵩月塔罗 · 占卜记录'
      };
      const data = new systemShare.SharedData(record);
      const controller = new systemShare.ShareController(data);
      const options: systemShare.ShareControllerOptions = {
        previewMode: systemShare.SharePreviewMode.DEFAULT
      };
      controller.show(context, options).then(() => {
        this.isSelectMode = false;
        this.selectedIds = [];
      }).catch((err: Error) => {
        this.isSelectMode = false;
        this.selectedIds = [];
        this.showToast('分享已取消');
      });
    } catch (err) {
      const error = err as Error;
      this.showToast('分享失败: ' + error.message);
    }
  }

  // 保存到文件，调用picker
  private doSaveFile(): void {
    try {
      const text = this.getExportText();
      const count = this.selectedIds.length;
      const now = new Date();
      const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
      const fileName = `tarot_${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}.txt`;

      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.newFileNames = [fileName];
      const documentPicker = new picker.DocumentViewPicker();
      documentPicker.save(documentSaveOptions).then((uris: string[]) => {
        if (uris && uris.length > 0) {
          const destFile = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
          fs.writeSync(destFile.fd, text);
          fs.closeSync(destFile);

          this.isSelectMode = false;
          this.selectedIds = [];
          this.showToast(`已保存${count} 条记录`);
        }
      }).catch((err: Error) => {
        this.showToast('保存取消');
      });
    } catch (err) {
      const error = err as Error;
      this.showToast('保存失败: ' + error.message);
    }
  }
}
