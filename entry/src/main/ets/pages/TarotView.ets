import { promptAction } from '@kit.ArkUI';
import router from '@ohos.router';
import http from '@ohos.net.http';
import { AppConfig } from '../common/AppConfig';
import { AuthenticatedHttpClient } from '../service/AuthenticatedHttpClient';
import { EchoColors, EchoRadius, EchoSpacing } from '../utils/EchoTheme';

// === 类型定义 ===
interface TarotCard {
  id: number;
  name: string;
  meaning: string;
  reversedMeaning: string;
  description: string;
  imageUrl: string;
}
interface ShowDialogOptions {
  title: string;
  message: string | Resource;
  confirmLabel?: string;
  cancelLabel?: string;
  onConfirm?: () => void;
  onCancel?: () => void;
}

interface ReadingResult {
  card: TarotCard;
  isReversed: boolean;
  position: string;
}

interface ReadingMode {
  name: string;
  positions: string[];
  count: number;
}

// SiliconFlow / OpenAI API 请求与响应接口定义
interface SiliconFlowMessage {
  role: string;
  content: string;
}
interface SiliconFlowReqBody {
  model: string;
  messages: SiliconFlowMessage[];
  temperature: number;
  max_tokens: number;
}
interface SiliconFlowChoiceMessage {
  content: string;
}
interface SiliconFlowChoice {
  message: SiliconFlowChoiceMessage;
}
interface SiliconFlowResponse {
  choices: SiliconFlowChoice[];
}

@Entry
@Component
struct TarotReadingApp {
  @State selectedMode: number = 0;
  @State readingResults: ReadingResult[] = [];
  @State showResults: boolean = false;
  @State currentCard: ReadingResult | undefined = undefined;
  @State keyword: string = "";
  @State isAILoading: boolean = false;


  private tarotCards: TarotCard[] = [
    {
      id: 1,
      name: "愚者",
      meaning: "新开始、冒险精神",
      reversedMeaning: "鲁莽、缺乏计划",
      description: "代表新的旅程、无限可能和天真无邪的精神。",
      imageUrl: "0"
    },
    {
      id: 2,
      name: "魔术师",
      meaning: "创造力、技能、意志力",
      reversedMeaning: "操纵、欺骗、能力不足",
      description: "象征个人能力的展现，以及将想法转化为现实的能力。",
      imageUrl: "1"
    },
    {
      id: 3,
      name: "女祭司",
      meaning: "直觉、潜意识、神秘",
      reversedMeaning: "缺乏直觉、秘密泄露",
      description: "代表内在知识、直觉和隐藏的智慧。",
      imageUrl: "2"
    },
    {
      id: 4,
      name: "皇后",
      meaning: "丰饶、母性、繁荣",
      reversedMeaning: "依赖、空虚、缺乏安全感",
      description: "象征创造力、关怀和物质上的富足。",
      imageUrl: "3"
    },
    {
      id: 5,
      name: "皇帝",
      meaning: "权威、结构、控制",
      reversedMeaning: "专制、缺乏纪律",
      description: "代表领导力、稳定性和组织能力。",
      imageUrl: "4"
    },
    {
      id: 6,
      name: "教皇",
      meaning: "传统、教育、道德",
      reversedMeaning: "非传统、激进思想",
      description: "象征传统价值观、教育和精神指导。",
      imageUrl: "5"
    },
    {
      id: 7,
      name: "恋人",
      meaning: "爱情、关系、和谐",
      reversedMeaning: "冲突、不和谐",
      description: "代表爱情、关系和重要的人生选择。",
      imageUrl: "6"
    },
    {
      id: 8,
      name: "战车",
      meaning: "胜利、意志力、决心",
      reversedMeaning: "失控、缺乏方向",
      description: "象征克服障碍、取得胜利和坚定的决心。",
      imageUrl: "7"
    },
    {
      id: 9,
      name: "力量",
      meaning: "勇气、毅力、同情",
      reversedMeaning: "软弱、无力",
      description: "代表内在力量、勇气和坚韧不拔的精神。",
      imageUrl: "8"
    },
    {
      id: 10,
      name: "隐士",
      meaning: "反思、独处、内省",
      reversedMeaning: "孤立、固执",
      description: "象征智慧、内省和精神探索。",
      imageUrl: "9"
    },
    {
      id: 11,
      name: "命运之轮",
      meaning: "变化、周期、命运",
      reversedMeaning: "坏运气、停滞",
      description: "代表生活中的变化和不可预测的命运转折。",
      imageUrl: "10"
    },
    {
      id: 12,
      name: "正义",
      meaning: "公平、诚实、法律",
      reversedMeaning: "不公、失衡",
      description: "象征公正、真理和因果报应。",
      imageUrl: "11"
    },
    {
      id: 13,
      name: "倒吊人",
      meaning: "牺牲、等待、新视角",
      reversedMeaning: "不情愿、延误",
      description: "代表为了更大的目标而做出的牺牲和新的视角。",
      imageUrl: "12"
    },
    {
      id: 14,
      name: "死神",
      meaning: "结束、转变、重生",
      reversedMeaning: "抗拒改变、停滞",
      description: "象征结束和新的开始，重要的生命转折点。",
      imageUrl: "13"
    },
    {
      id: 15,
      name: "节制",
      meaning: "平衡、耐心、调和",
      reversedMeaning: "极端、不平衡",
      description: "代表和谐、平衡和适度的重要性。",
      imageUrl: "14"
    },
    {
      id: 16,
      name: "恶魔",
      meaning: "束缚、物质主义、恐惧",
      reversedMeaning: "解放、释放",
      description: "象征物质诱惑、束缚和恐惧。",
      imageUrl: "15"
    },
    {
      id: 17,
      name: "塔",
      meaning: "突然变化、启示、破坏",
      reversedMeaning: "逃避、避免",
      description: "代表突然的改变、觉醒和破坏性的启示。",
      imageUrl: "16"
    },
    {
      id: 18,
      name: "星星",
      meaning: "希望、灵感、指引",
      reversedMeaning: "绝望、悲观",
      description: "象征希望、灵感和精神上的指引。",
      imageUrl: "17"
    },
    {
      id: 19,
      name: "月亮",
      meaning: "幻象、恐惧、潜意识",
      reversedMeaning: "真相揭露、澄清",
      description: "代表幻象、恐惧和潜意识的领域。",
      imageUrl: "18"
    },
    {
      id: 20,
      name: "太阳",
      meaning: "成功、快乐、活力",
      reversedMeaning: "暂时挫折、缺乏热情",
      description: "象征成功、快乐和积极的能量。",
      imageUrl: "19"
    },
    {
      id: 21,
      name: "审判",
      meaning: "重生、内省、精神觉醒",
      reversedMeaning: "自我怀疑、拒绝",
      description: "代表精神觉醒、重生和重要的决定。",
      imageUrl: "20"
    },
    {
      id: 22,
      name: "世界",
      meaning: "完成、成就、结合",
      reversedMeaning: "不完整、延迟",
      description: "象征完成、成就和生命的圆满。",
      imageUrl: "21"
    }
  ];
  private readingModes: ReadingMode[] = [
    { name: "单张抽牌", positions: ["今日指引"], count: 1 },
    { name: "三张展开", positions: ["过去", "现在", "未来"], count: 3 },
    {
      name: "凯尔特十字",
      positions: ["现状", "挑战", "目标", "成因", "过去", "未来", "本身", "环境", "希望", "结果"],
      count: 10
    }
  ];

  build() {
    Column() {
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

        Text('塔罗指引')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(EchoColors.TEXT_PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Text('历史')
          .fontSize(12)
          .fontColor(EchoColors.PRIMARY_DARK)
          .fontWeight(FontWeight.Medium)
          .width(48)
          .height(36)
          .textAlign(TextAlign.Center)
          .backgroundColor(EchoColors.PRIMARY_SOFT)
          .borderRadius(EchoRadius.PILL)
          .onClick(() => {
            router.pushUrl({
              url: 'pages/ChatHistoryPage'
            });
          })
      }
      .width('100%')
      .padding({ left: EchoSpacing.PAGE, right: EchoSpacing.PAGE, top: 16, bottom: 10 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 18 }) {
          Column({ space: 6 }) {
            Text('把注意力放在一个问题上')
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor(EchoColors.TEXT_PRIMARY)
            Text('它不是替你做决定，而是帮你看见此刻的方向')
              .fontSize(13)
              .fontColor(EchoColors.TEXT_SECONDARY)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          TextInput({ placeholder: '输入你关心的主题，例如学业、感情或选择' })
            .width('100%')
            .height(48)
            .backgroundColor(EchoColors.SURFACE)
            .border({ width: 1, color: EchoColors.BORDER })
            .borderRadius(EchoRadius.SMALL)
            .fontColor(EchoColors.TEXT_PRIMARY)
            .placeholderColor(EchoColors.TEXT_TERTIARY)
            .onChange((value: string) => {
              this.keyword = value;
            })
            .padding({ left: 16, right: 16 })

          Row({ space: 8 }) {
            ForEach([0, 1, 2], (index: number) => {
              Text(this.readingModes[index].name)
                .layoutWeight(1)
                .height(38)
                .borderRadius(EchoRadius.SMALL)
                .textAlign(TextAlign.Center)
                .backgroundColor(index === this.selectedMode ? EchoColors.PRIMARY_SOFT : EchoColors.SURFACE)
                .fontColor(index === this.selectedMode ? EchoColors.PRIMARY_DARK : EchoColors.TEXT_SECONDARY)
                .fontSize(12)
                .fontWeight(index === this.selectedMode ? FontWeight.Bold : FontWeight.Normal)
                .border({ width: 1, color: index === this.selectedMode ? EchoColors.PRIMARY : EchoColors.BORDER })
                .onClick(() => {
                  this.selectedMode = index;
                  this.resetReading();
                })
            })
          }
          .width('100%')

          Button(this.selectedMode === 0 ? '抽一张牌' : '开始' + this.readingModes[this.selectedMode].name)
            .width('100%')
            .height(50)
            .borderRadius(EchoRadius.MEDIUM)
            .backgroundColor(EchoColors.PRIMARY)
            .fontColor('#FFFFFF')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .onClick(() => {
              this.performReading();
            })

          if (this.showResults) {
            Column({ space: 12 }) {
              Row({ space: 10 }) {
                Button(this.isAILoading ? '正在解读…' : 'AI 深度解读')
                  .layoutWeight(1)
                  .height(40)
                  .borderRadius(EchoRadius.SMALL)
                  .backgroundColor(this.isAILoading ? EchoColors.SURFACE_MUTED : EchoColors.PRIMARY_SOFT)
                  .fontColor(this.isAILoading ? EchoColors.TEXT_TERTIARY : EchoColors.PRIMARY_DARK)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .onClick(() => {
                    if (!this.isAILoading) {
                      this.getAIInterpretation();
                    }
                  })

                Button('查看牌义')
                  .layoutWeight(1)
                  .height(40)
                  .borderRadius(EchoRadius.SMALL)
                  .backgroundColor(EchoColors.MINT_SOFT)
                  .fontColor(EchoColors.MINT_TEXT)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .onClick(() => {
                    if (this.selectedMode === 1) {
                      this.showThreeCardInterpretation();
                    } else if (this.selectedMode === 2) {
                      this.showFullCelticCross();
                    }
                  })
              }
              .width('100%')

              if (this.selectedMode === 0 && this.currentCard) {
                this.SingleCardView();
              } else if (this.selectedMode === 1) {
                this.ThreeCardView();
              } else {
                this.CelticCrossView();
              }
            }
            .width('100%')
          }
        }
        .width('100%')
        .padding({ left: EchoSpacing.PAGE, right: EchoSpacing.PAGE, top: 16, bottom: 36 })
        .alignItems(HorizontalAlign.Center)
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EchoColors.PAGE)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  SingleCardView() {
    Column() {
      Image($r('app.media.' + this.currentCard!.card.imageUrl))
        .width(200)
        .height(300)
        .objectFit(ImageFit.Cover)
        .borderRadius(12)
        .rotate({ angle: this.currentCard!.isReversed ? 180 : 0 })
        .border({ width: 1, color: EchoColors.BORDER })
        .margin({ bottom: 20 })

      Text(this.currentCard!.card.name)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(EchoColors.TEXT_PRIMARY)
        .margin({ bottom: 8 })

      Text(this.currentCard!.isReversed ? "逆位" : "正位")
        .fontSize(16)
        .fontColor(this.currentCard!.isReversed ? '#E94057' : EchoColors.TEXT_PRIMARY)
        .backgroundColor(this.currentCard!.isReversed ? '#FFE5E5' : '#E2F0CB')
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .borderRadius(12)
        .margin({ bottom: 16 })

      Text(this.currentCard!.isReversed ? this.currentCard!.card.reversedMeaning : this.currentCard!.card.meaning)
        .fontSize(15)
        .fontColor(EchoColors.TEXT_PRIMARY)
        .fontWeight(FontWeight.Medium)
        .width('90%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 12 })

      Text(this.currentCard!.card.description)
        .fontSize(13)
        .fontColor(EchoColors.TEXT_SECONDARY)
        .width('90%')
        .textAlign(TextAlign.Center)
        .lineHeight(18)
    }
    .width('100%')
    .padding({ top: 24, bottom: 24, left: 16, right: 16 })
    .borderRadius(20)
    .backgroundColor(EchoColors.SURFACE)
    .border({ width: 1, color: EchoColors.BORDER })
  }

  @Builder
  ThreeCardView() {
    Column() {
      Row() {
        ForEach(this.readingResults, (result: ReadingResult, index: number) => {
          Column() {
            Text(this.readingModes[1].positions[index])
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor('#C4A76D')
              .margin({ bottom: 8 })

            Image($r('app.media.' + result.card.imageUrl))
              .width(90)
              .height(135)
              .objectFit(ImageFit.Cover)
              .borderRadius(8)
              .rotate({ angle: result.isReversed ? 180 : 0 })
              .border({ width: 1, color: EchoColors.BORDER })
              .margin({ bottom: 8 })

            Text(result.card.name)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(EchoColors.TEXT_PRIMARY)
              .margin({ bottom: 4 })

            Text(result.isReversed ? "逆位" : "正位")
              .fontSize(11)
              .fontColor(result.isReversed ? '#E94057' : EchoColors.TEXT_PRIMARY)
              .backgroundColor(result.isReversed ? '#FFE5E5' : '#E2F0CB')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(8)
              .margin({ bottom: 6 })

            Text(result.isReversed ? result.card.reversedMeaning : result.card.meaning)
              .fontSize(11)
              .fontColor(EchoColors.TEXT_SECONDARY)
              .width(90)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .maxLines(2)
              .textAlign(TextAlign.Center)
              .lineHeight(14)
          }
          .width(106)
          .padding(8)
          .borderRadius(16)
          .backgroundColor(EchoColors.SURFACE)
          .border({ width: 1, color: EchoColors.BORDER })
          .margin({ left: 4, right: 4 })
        })
      }
      .margin({ top: 10 })
    }
    .width('100%')
  }

  @Builder
  CelticCrossView() {
    Column() {
      // 凯尔特十字直接复用了原有信息展示，但修改为亮色卡片
      List({ space: 10 }) {
        ForEach(
          this.readingResults,
          (result: ReadingResult, index: number) => {
            ListItem() {
              Row() {
                Column() {
                  Text(`${index + 1}`)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#C4A76D')
                  Text(`${this.readingModes[2].positions[index]}`)
                    .fontSize(11)
                    .fontColor(EchoColors.TEXT_SECONDARY)
                    .margin({ top: 2 })
                }
                .width(40)
                .alignItems(HorizontalAlign.Center)

                Image($r('app.media.' + result.card.imageUrl))
                  .width(60)
                  .height(90)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(6)
                  .rotate({ angle: result.isReversed ? 180 : 0 })
                  .border({ width: 1, color: '#E0C9A0' })
                  .margin({ left: 8 })

                Column() {
                  Row() {
                    Text(result.card.name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(EchoColors.TEXT_PRIMARY)
                    
                    Text(result.isReversed ? "逆位" : "正位")
                      .fontSize(10)
                      .fontColor(result.isReversed ? '#E94057' : EchoColors.TEXT_PRIMARY)
                      .backgroundColor(result.isReversed ? '#FFE5E5' : '#E2F0CB')
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(8)
                      .margin({ left: 8 })
                  }
                  .margin({ bottom: 4 })

                  Text(result.isReversed ? result.card.reversedMeaning : result.card.meaning)
                    .fontSize(12)
                    .fontColor(EchoColors.TEXT_SECONDARY)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .maxLines(2)
                    .lineHeight(16)
                }
                .margin({ left: 12, right: 8 })
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding(10)
              .backgroundColor(EchoColors.SURFACE)
              .border({ width: 1, color: EchoColors.BORDER })
              .borderRadius(EchoRadius.MEDIUM)
            }
          },
          (item: ReadingResult) => item.position
        )
      }
      .width('100%')
      .margin({ top: 5 })
    }
    .width('100%')
  }

  private performReading() {
    this.readingResults = [];
    // 洗牌：复制一份牌组并随机打乱，确保不会抽到重复的牌
    const shuffled: TarotCard[] = [];
    for (let k = 0; k < this.tarotCards.length; k++) {
      shuffled.push(this.tarotCards[k]);
    }
    for (let i = shuffled.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      const temp = shuffled[i];
      shuffled[i] = shuffled[j];
      shuffled[j] = temp;
    }
    // 从洗好的牌中依次抽
    const count = this.readingModes[this.selectedMode].count;
    for (let i = 0; i < count; i++) {
      const card = shuffled[i];
      const isReversed = Math.random() > 0.7;
      this.readingResults.push({
        card: card,
        isReversed: isReversed,
        position: this.readingModes[this.selectedMode].positions[i]
      });
    }
    this.showResults = true;

    if (this.selectedMode === 0 && this.readingResults.length > 0) {
      this.currentCard = this.readingResults[0];
    } else {
      this.currentCard = undefined;
    }
  }

  private resetReading() {
    this.showResults = false;
    this.readingResults = [];
    this.currentCard = undefined;
  }

  private async showFullCelticCross() {
    let description = "凯尔特十字完整解读\n\n";
    for (let i = 0; i < this.readingResults.length; i++) {
      const result = this.readingResults[i];
      description += `${this.readingModes[2].positions[i]}: ${result.card.name} (${result.isReversed ? "逆位" :
        "正位"})\n`;
      description += `含义: ${result.isReversed ? result.card.reversedMeaning : result.card.meaning}\n\n`;
    }
    try {
      await promptAction.showDialog({
        title: "凯尔特十字完整解读",
        message: description,
      });
    } catch (error) {
      console.error("对话框异常", error);
    }
  }

  private async showThreeCardInterpretation() {
    let description = "三张牌解读\n\n";
    description += `过去 (${this.readingResults[0].card.name}): ${this.readingResults[0].isReversed ?
      this.readingResults[0].card.reversedMeaning : this.readingResults[0].card.meaning}\n\n`;
    description += `现在 (${this.readingResults[1].card.name}): ${this.readingResults[1].isReversed ?
      this.readingResults[1].card.reversedMeaning : this.readingResults[1].card.meaning}\n\n`;
    description += `未来 (${this.readingResults[2].card.name}): ${this.readingResults[2].isReversed ?
      this.readingResults[2].card.reversedMeaning : this.readingResults[2].card.meaning}\n\n`;
    try {
      await promptAction.showDialog({
        title: "三张牌详细解读",
        message: description,
      });
    } catch (error) {
      console.error("对话框错误", error);
    }
  }

  private getAIInterpretation(): void {
    if (this.readingResults.length === 0) {
      promptAction.showDialog({
        title: "尚未抽牌",
        message: "请先抽取塔罗牌再请求 AI 解读。",

      });
      return;
    }

    if (this.isAILoading) {
      return;
    }
    this.isAILoading = true;


    const theme = this.keyword.trim() || "你当前最关心的人生议题";
    const modeName = this.readingModes[this.selectedMode].name;

    let prompt = `【角色设定】
你是一位资深塔罗占卜师，擅长结合用户具体关切给出深刻、温暖且 actionable 的指引。
【用户主题】
本次占卜聚焦于：「${theme}」

【占卜模式】
${modeName}

【抽牌结果】
`;

    this.readingResults.forEach((result, index) => {
      const pos = this.readingModes[this.selectedMode].positions[index] || `第${index + 1}位`;
      const orientation = result.isReversed ? "逆位" : "正位";
      const meaning = result.isReversed ? result.card.reversedMeaning : result.card.meaning;
      prompt += `- ${pos}：${result.card.name}（${orientation}）\n  含义：${meaning}\n`;
    });

    prompt += `\n【解读要求】
1. 所有分析必须紧密围绕「${theme}」展开，不可泛泛而谈。
2. 避免使用“可能”“也许”等模糊词汇，语气坚定而温柔。
3. 从整体能量、潜在挑战、具体行动建议三方面解读。
4. 最后用一句鼓励的话收尾，让用户感到被支持。
5.不使用任何Markdown 格式（如 **加粗**、斜体*等），不要在回复末尾标注字数
现在，请开始你的专业解读：`;

    
    const endpoint = AppConfig.AI_CHAT_COMPLETIONS_PROXY_URL;

    let reqBody: SiliconFlowReqBody = {
      model: AppConfig.AI_MODEL, 
      messages: [
        { role: "user", content: prompt }
      ],
      temperature: 0.7,
      max_tokens: 600
    };

    AuthenticatedHttpClient.request(endpoint, {
      method: http.RequestMethod.POST,
      extraData: JSON.stringify(reqBody),
      connectTimeout: 15000,
      readTimeout: 60000
    }).then((data: http.HttpResponse) => {
        this.isAILoading = false;

        if (data.responseCode !== 200) {
          let msg = "服务器返回异常。";
          if (data.responseCode === 400) msg = "请求格式错误，请稍后重试。";
          if (data.responseCode === 429) msg = "请求过于频繁，请稍后再试。";
          promptAction.showDialog({
            title: "服务异常",
            message: msg,

          });
          return;
        }

        try {
          const aiResponse = JSON.parse(data.result as string) as SiliconFlowResponse;
          
          if (!aiResponse.choices || aiResponse.choices.length === 0) {
            console.error("响应异常 (无choices):", data.result);
            promptAction.showDialog({
              title: "解读失败",
              message: "未获取到有效解读数据，请稍后重试。",
            });
            return;
          }

          let aiResult = aiResponse.choices[0].message.content.trim();

          // 清除 DeepSeek R1 思考链标签
          aiResult = aiResult.replace(/<think>[\s\S]*?<\/think>/g, '');

          const cleanText = aiResult.replace(/\*\*(.*?)\*\*/g, '$1');
          const cleanText2 = cleanText.replace(/`/g, '').trim();

          router.pushUrl({
            url: 'pages/AIDialogPage',
            params: {
              interpretation: cleanText2,
              theme: this.keyword.trim() || "你当前最关心的人生议题"
            }
          });
        } catch (parseError) {
          console.error('JSON 解析失败:', parseError);
          promptAction.showDialog({
            title: "解读失败",
            message: "数据解析失败，请重试。",

          });
        }
    }).catch(() => {
      this.isAILoading = false;
      promptAction.showDialog({
        title: "网络错误",
        message: "请检查网络连接或重新登录。"
      });
    });
  }
}
