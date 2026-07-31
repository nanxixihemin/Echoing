// MainAbility/pages/SharedForest.ets

import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { SharedForestService } from '../service/SharedForestService';
import { EchoColors, EchoRadius, EchoSpacing } from '../utils/EchoTheme';

interface LeafPosition {
  x: number;
  y: number;
  angle: number;
  scale: number;
}

interface SharedLeafData {
  id: string;
  content: string;
  nickname: string;
  timestamp: number;
  greenLevel: number;
  aiResponse: string;
  position: LeafPosition;
}

@Entry
@Component
struct SharedForest {
  @State leaves: SharedLeafData[] = [];
  @State selectedLeaf: SharedLeafData | null = null;
  @State showDetail: boolean = false;
  @State isLoading: boolean = true;
  @State isOnline: boolean = true;
  @State treeScale: number = 1;

  aboutToAppear(): void {
    this.loadLeaves();
  }

  private generateLeafPosition(index: number): LeafPosition {
    const layer: number = Math.floor(index / 8);
    const posInLayer: number = index % 8;
    const baseAngle: number = (posInLayer / 8) * Math.PI * 2;
    const angle: number = baseAngle + layer * 0.4;
    const radius: number = 0.12 + layer * 0.06 + Math.random() * 0.08;

    return {
      x: 0.5 + Math.cos(angle) * radius,
      y: 0.12 + layer * 0.08 + Math.random() * 0.08,
      angle: -40 + Math.random() * 80,
      scale: 0.5 + Math.random() * 0.5
    };
  }

  /**
   * 解析后端返回的时间字符串
   * 格式: "2025-12-21 02:20:56"
   */
  private parseDateTime(dateStr: string): number {
    try {
      // 方式1: 替换空格为T
      const isoStr: string = dateStr.replace(' ', 'T');
      const date: Date = new Date(isoStr);

      if (!isNaN(date.getTime())) {
        return date.getTime();
      }
    } catch (e) {
      // 忽略
    }

    // 方式2: 手动解析 "2025-12-21 02:20:56"
    try {
      const parts: string[] = dateStr.split(' ');
      if (parts.length === 2) {
        const dateParts: string[] = parts[0].split('-');
        const timeParts: string[] = parts[1].split(':');

        if (dateParts.length === 3 && timeParts.length === 3) {
          const year: number = parseInt(dateParts[0]);
          const month: number = parseInt(dateParts[1]) - 1; // 月份从0开始
          const day: number = parseInt(dateParts[2]);
          const hour: number = parseInt(timeParts[0]);
          const minute: number = parseInt(timeParts[1]);
          const second: number = parseInt(timeParts[2]);

          const timestamp: number = new Date(year, month, day, hour, minute, second).getTime();
          return timestamp;
        }
      }
    } catch (e) {
      // 忽略
    }

    return Date.now();
  }

  private formatTime(timestamp: number): string {
    const now: number = Date.now();
    const diff: number = now - timestamp;

    if (diff < 0) {
      return '刚刚';
    }
    if (diff < 60000) {
      return '刚刚';
    }
    if (diff < 3600000) {
      return `${Math.floor(diff / 60000)}分钟前`;
    }
    if (diff < 86400000) {
      return `${Math.floor(diff / 3600000)}小时前`;
    }
    if (diff < 604800000) {
      return `${Math.floor(diff / 86400000)}天前`;
    }

    const date: Date = new Date(timestamp);
    const month: number = date.getMonth() + 1;
    const day: number = date.getDate();
    return `${month}月${day}日`;
  }

  /**
   * 加载叶子数据
   */
  private async loadLeaves(): Promise<void> {
    this.isLoading = true;

    console.info('SharedForest', '========== 开始加载叶子 ==========');

    try {
      const response = await SharedForestService.fetchLeaves();

      console.info('SharedForest', `响应码: ${response.responseCode}`);

      if (response.responseCode === 200 && response.result) {
        const resultStr: string = response.result as string;
        console.info('SharedForest', `原始数据: ${resultStr}`);

        const data: Object = JSON.parse(resultStr);
        let leavesArray: Object[] = [];

        // 从返回数据中提取叶子数组
        if (typeof data === 'object' && data !== null) {
          const dataObj = data as Record<string, Object>;

          // 优先从 leaves 字段获取
          if (dataObj['leaves'] && Array.isArray(dataObj['leaves'])) {
            leavesArray = dataObj['leaves'] as Object[];
            console.info('SharedForest', `从 leaves 字段获取，数量: ${leavesArray.length}`);
          }
          // 其次从 data 字段获取
          else if (dataObj['data'] && Array.isArray(dataObj['data'])) {
            leavesArray = dataObj['data'] as Object[];
            console.info('SharedForest', `从 data 字段获取，数量: ${leavesArray.length}`);
          }
          // 直接是数组
          else if (Array.isArray(data)) {
            leavesArray = data as Object[];
            console.info('SharedForest', `直接是数组，数量: ${leavesArray.length}`);
          }
        }

        console.info('SharedForest', `解析到叶子数量: ${leavesArray.length}`);

        // 处理每片叶子
        const processedLeaves: SharedLeafData[] = [];
        for (let i = 0; i < leavesArray.length; i++) {
          const leaf = leavesArray[i] as Record<string, Object>;

          // 解析时间
          let timestamp: number = Date.now();
          if (leaf['created_at']) {
            const dateStr: string = leaf['created_at'] as string;
            timestamp = this.parseDateTime(dateStr);
            console.info('SharedForest', `叶子 ${i} 时间: ${dateStr} -> ${new Date(timestamp).toLocaleString()}`);
          } else if (leaf['timestamp']) {
            timestamp = leaf['timestamp'] as number;
          }

          // 获取绿度（从后端获取，基于点赞数）
          let greenLevel: number = 30;
          if (leaf['green_level'] !== undefined && leaf['green_level'] !== null) {
            greenLevel = leaf['green_level'] as number;
          } else if (leaf['greenLevel'] !== undefined && leaf['greenLevel'] !== null) {
            greenLevel = leaf['greenLevel'] as number;
          } else if (leaf['like_count'] !== undefined && leaf['like_count'] !== null) {
            // 根据点赞数计算绿度：基础30 + 每次点赞5，最高100
            const likeCount: number = leaf['like_count'] as number;
            greenLevel = Math.min(100, 30 + likeCount * 5);
          }

          // 获取昵称
          let nickname: string = '匿名小叶子';
          if (leaf['nickname'] && (leaf['nickname'] as string).length > 0) {
            nickname = leaf['nickname'] as string;
          } else if (leaf['nick_name'] && (leaf['nick_name'] as string).length > 0) {
            nickname = leaf['nick_name'] as string;
          }

          // 获取AI回复
          let aiResponse: string = '';
          if (leaf['aiResponse']) {
            aiResponse = leaf['aiResponse'] as string;
          } else if (leaf['ai_response']) {
            aiResponse = leaf['ai_response'] as string;
          }

          // 构建叶子数据
          const processed: SharedLeafData = {
            id: String(leaf['id'] || `leaf_${i}`),
            content: (leaf['content'] as string) || '',
            nickname: nickname,
            timestamp: timestamp,
            greenLevel: greenLevel,
            aiResponse: aiResponse,
            position: this.generateLeafPosition(i)
          };

          console.info('SharedForest', `叶子 ${i}: "${processed.content.substring(0, 15)}...", 昵称=${processed.nickname}, 绿度=${processed.greenLevel}`);
          processedLeaves.push(processed);
        }

        this.leaves = processedLeaves;
        this.isOnline = true;
        console.info('SharedForest', `✅ 加载完成，共 ${this.leaves.length} 片叶子`);

      } else {
        console.error('SharedForest', `❌ 响应异常: ${response.responseCode}`);
        this.isOnline = false;
      }
    } catch (e) {
      console.error('SharedForest', `❌ 请求失败: ${JSON.stringify(e)}`);
      this.isOnline = false;
      promptAction.showToast({ message: '网络连接失败，请检查校园网' });
    } finally {
      this.isLoading = false;
      console.info('SharedForest', '========== 加载结束 ==========');
    }
  }

  /**
   * 点赞叶子（送温暖）
   */
  private async likeLeaf(leafId: string): Promise<void> {

    console.info('SharedForest', `点赞叶子: ${leafId}`);

    try {
      const response = await SharedForestService.likeLeaf(leafId);

      console.info('SharedForest', `点赞响应: ${response.responseCode}`);

      if (response.responseCode === 200) {
        // 解析返回的新绿度
        let newGreenLevel: number = 0;
        if (response.result) {
          const resultStr: string = response.result as string;
          const resultObj = JSON.parse(resultStr) as Record<string, Object>;
          if (resultObj['green_level']) {
            newGreenLevel = resultObj['green_level'] as number;
          }
        }

        // 更新本地叶子数据
        const updatedLeaves: SharedLeafData[] = [];
        for (let i = 0; i < this.leaves.length; i++) {
          const leaf: SharedLeafData = this.leaves[i];
          if (leaf.id === leafId) {
            const updated: SharedLeafData = {
              id: leaf.id,
              content: leaf.content,
              nickname: leaf.nickname,
              timestamp: leaf.timestamp,
              greenLevel: newGreenLevel > 0 ? newGreenLevel : Math.min(100, leaf.greenLevel + 5),
              aiResponse: leaf.aiResponse,
              position: leaf.position
            };
            updatedLeaves.push(updated);
          } else {
            updatedLeaves.push(leaf);
          }
        }
        this.leaves = updatedLeaves;

        promptAction.showToast({ message: '已送上温暖' });
        console.info('SharedForest', '✅ 点赞成功');
      } else {
        promptAction.showToast({ message: '操作失败' });
      }
    } catch (e) {
      console.error('SharedForest', `❌ 点赞失败: ${JSON.stringify(e)}`);
      promptAction.showToast({ message: '网络错误' });
    }

    this.showDetail = false;
    this.selectedLeaf = null;
  }

  // 根据绿度获取叶子颜色
  private getLeafColor(greenLevel: number): string {
    if (greenLevel >= 80) return '#1B5E20'; // 深绿
    if (greenLevel >= 60) return '#2E7D32';
    if (greenLevel >= 40) return '#4CAF50';
    return '#81C784'; // 浅绿
  }

  private getLeafSize(greenLevel: number): number {
    return 16 + greenLevel / 8;
  }

  build() {
    Stack() {
      Column() {
        this.TopBar()

        if (this.isLoading) {
          this.LoadingView()
        } else if (this.leaves.length === 0) {
          this.EmptyView()
        } else {
          this.ForestView()
        }

        Button('分享一段心情')
          .width('100%')
          .height(52)
          .fontSize(15)
          .fontWeight(600)
          .fontColor('#FFFFFF')
          .backgroundColor(EchoColors.PRIMARY)
          .borderRadius(EchoRadius.MEDIUM)
          .margin({ left: EchoSpacing.PAGE, right: EchoSpacing.PAGE, top: 8, bottom: 18 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/SharedWrite' });
          })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(EchoColors.PAGE)

      if (this.showDetail && this.selectedLeaf !== null) {
        this.DetailPanel()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  TopBar() {
    Row() {
      Text('‹')
        .fontSize(28)
        .fontWeight(600)
        .fontColor(EchoColors.TEXT_PRIMARY)
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .backgroundColor(EchoColors.SURFACE)
        .border({ width: 1, color: EchoColors.BORDER })
        .borderRadius(EchoRadius.PILL)
        .onClick(() => {
          router.back();
        })

      Column({ space: 2 }) {
        Text('共享森林')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(EchoColors.TEXT_PRIMARY)

        Text(this.isOnline ? `${this.leaves.length} 条公开心情` : '网络未连接')
          .fontSize(11)
          .fontColor(this.isOnline ? EchoColors.MINT_TEXT : EchoColors.PINK_TEXT)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      Text('刷新')
        .fontSize(12)
        .fontWeight(500)
        .fontColor(EchoColors.PRIMARY_DARK)
        .width(48)
        .height(36)
        .textAlign(TextAlign.Center)
        .backgroundColor(EchoColors.PRIMARY_SOFT)
        .borderRadius(EchoRadius.PILL)
        .onClick(() => {
          this.loadLeaves();
        })
    }
    .width('100%')
    .padding({ left: EchoSpacing.PAGE, right: EchoSpacing.PAGE, top: 16, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  LoadingView() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(EchoColors.PRIMARY)

      Text('正在载入大家的近况…')
        .fontSize(14)
        .fontColor(EchoColors.TEXT_SECONDARY)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  EmptyView() {
    Column({ space: 12 }) {
      Column()
        .width(58)
        .height(58)
        .backgroundColor(EchoColors.MINT_SOFT)
        .borderRadius(EchoRadius.LARGE)

      Text('这里暂时很安静')
        .fontSize(18)
        .fontWeight(600)
        .fontColor(EchoColors.TEXT_PRIMARY)
        .margin({ top: 8 })

      Text('分享第一段心情，也许会有人给你一份温暖')
        .fontSize(13)
        .fontColor(EchoColors.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 36, right: 36 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  ForestView() {
    Scroll() {
      Column({ space: 12 }) {
        Column({ space: 5 }) {
          Text('来自此刻的真实心情')
            .fontSize(22)
            .fontWeight(700)
            .fontColor(EchoColors.TEXT_PRIMARY)
          Text('轻点一条记录，可以阅读完整内容并送上一份温暖')
            .fontSize(12)
            .fontColor(EchoColors.TEXT_SECONDARY)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: 4 })

        ForEach(this.leaves, (leaf: SharedLeafData) => {
          this.LeafCard(leaf)
        }, (leaf: SharedLeafData) => leaf.id)
      }
      .width('100%')
      .padding({ left: EchoSpacing.PAGE, right: EchoSpacing.PAGE, top: 12, bottom: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  LeafCard(leaf: SharedLeafData) {
    Column({ space: 10 }) {
      Row() {
        Text(leaf.nickname)
          .fontSize(13)
          .fontColor(EchoColors.MINT_TEXT)
          .fontWeight(FontWeight.Medium)

        Blank()

        Text(this.formatTime(leaf.timestamp))
          .fontSize(11)
          .fontColor(EchoColors.TEXT_TERTIARY)
      }
      .width('100%')

      Text(leaf.content)
        .fontSize(15)
        .fontColor(EchoColors.TEXT_PRIMARY)
        .lineHeight(23)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 8 }) {
        Text('温暖值')
          .fontSize(11)
          .fontColor(EchoColors.TEXT_SECONDARY)

        Stack({ alignContent: Alignment.Start }) {
          Row()
            .width('100%')
            .height(6)
            .backgroundColor(EchoColors.SURFACE_MUTED)
            .borderRadius(3)

          Row()
            .width(`${leaf.greenLevel}%`)
            .height(6)
            .backgroundColor(this.getLeafColor(leaf.greenLevel))
            .borderRadius(3)
        }
        .layoutWeight(1)

        Text(`${leaf.greenLevel}%`)
          .fontSize(11)
          .fontColor(EchoColors.MINT_TEXT)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(EchoColors.SURFACE)
    .border({ width: 1, color: EchoColors.BORDER })
    .borderRadius(EchoRadius.LARGE)
    .onClick(() => {
      this.selectedLeaf = leaf;
      this.showDetail = true;
    })
  }

  @Builder
  DetailPanel() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(EchoColors.SCRIM)
        .onClick(() => {
          this.showDetail = false;
          this.selectedLeaf = null;
        })

      Column({ space: 16 }) {
        if (this.selectedLeaf !== null) {
          Row() {
            Text(this.selectedLeaf.nickname)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#4CAF50')

            Blank()

            Text(this.formatTime(this.selectedLeaf.timestamp))
              .fontSize(12)
              .fontColor('#888888')
          }
          .width('100%')

          Scroll() {
            Text(this.selectedLeaf.content)
              .fontSize(16)
              .fontColor('#333333')
              .lineHeight(28)
              .width('100%')
          }
          .width('100%')
          .constraintSize({ maxHeight: 150 })
          .scrollBar(BarState.Off)

          // 绿度显示
          Column({ space: 8 }) {
            Row() {
              Text('温暖值')
                .fontSize(13)
                .fontColor('#4CAF50')

              Blank()

              Text(`${this.selectedLeaf.greenLevel}%`)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.getLeafColor(this.selectedLeaf.greenLevel))
            }
            .width('100%')

            Stack({ alignContent: Alignment.Start }) {
              Row()
                .width('100%')
                .height(12)
                .backgroundColor('rgba(76,175,80,0.2)')
                .borderRadius(6)

              Row()
                .width(`${this.selectedLeaf.greenLevel}%`)
                .height(12)
                .backgroundColor(this.getLeafColor(this.selectedLeaf.greenLevel))
                .borderRadius(6)
            }
            .width('100%')

            Text('温暖值越高，叶子越绿越大')
              .fontSize(11)
              .fontColor('#888888')
          }
          .width('100%')
          .padding(14)
          .backgroundColor('rgba(76,175,80,0.08)')
          .borderRadius(14)

          // AI回复
          if (this.selectedLeaf.aiResponse && this.selectedLeaf.aiResponse.length > 0) {
            Column({ space: 6 }) {
              Text('给你的回应')
                .fontSize(12)
                .fontColor('#4CAF50')

              Text(this.selectedLeaf.aiResponse)
                .fontSize(14)
                .fontColor('#666666')
                .lineHeight(22)
            }
            .width('100%')
            .padding(14)
            .backgroundColor('rgba(76,175,80,0.05)')
            .borderRadius(14)
            .alignItems(HorizontalAlign.Start)
          }

          // 送温暖按钮
          Button('送上温暖')
            .width('100%')
            .height(52)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .backgroundColor('#4CAF50')
            .fontColor('#FFFFFF')
            .borderRadius(26)
            .onClick(() => {
              if (this.selectedLeaf !== null) {
                this.likeLeaf(this.selectedLeaf.id);
              }
            })
        }
      }
      .width('100%')
      .padding(24)
      .backgroundColor('#FFFFFF')
      .borderRadius({ topLeft: 28, topRight: 28 })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
