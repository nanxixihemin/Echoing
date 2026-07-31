import { ColorConstants } from '../utils/ColorConstants';
import { ZzuNetwork } from '../utils/ZzuNetwork';
import { AppConfig } from '../common/AppConfig';
import http from '@ohos.net.http';
import { AuthenticatedHttpClient } from '../service/AuthenticatedHttpClient';

interface TarotCard {
  id: number;
  name: string;
  meaning: string;
  reversedMeaning: string;
  description: string;
  imageUrl: string;
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

@Component
export struct TarotWidget {
  onResult: (result: string) => void = (): void => {};
  onClose: () => void = (): void => {};

  @State isZzuMode: boolean = false;
  @State isNetworkChecked: boolean = false;
  @State selectedMode: number = 0;
  @State keyword: string = "";
  
  @State readingResults: ReadingResult[] = [];
  @State showResults: boolean = false;
  
  @State isAILoading: boolean = false;
  @State aiInterpretation: string = '';
  @State actionPrompt: string = '';

  private tarotCards: TarotCard[] = [
    {
      id: 1, name: "愚者", meaning: "新开始、冒险精神", reversedMeaning: "鲁莽、缺乏计划",
      description: "代表新的旅程、无限可能和天真无邪的精神。", imageUrl: "0"
    },
    {
      id: 2, name: "魔术师", meaning: "创造力、技能、意志力", reversedMeaning: "操纵、欺骗、能力不足",
      description: "象征个人能力的展现，以及将想法转化为现实的能力。", imageUrl: "1"
    },
    {
      id: 3, name: "女祭司", meaning: "直觉、潜意识、神秘", reversedMeaning: "缺乏直觉、秘密泄露",
      description: "代表内在知识、直觉和隐藏的智慧。", imageUrl: "2"
    },
    {
      id: 4, name: "皇后", meaning: "丰饶、母性、繁荣", reversedMeaning: "依赖、空虚、缺乏安全感",
      description: "象征创造力、关怀和物质上的富足。", imageUrl: "3"
    },
    {
      id: 5, name: "皇帝", meaning: "权威、结构、控制", reversedMeaning: "专制、缺乏纪律",
      description: "代表领导力、稳定性和组织能力。", imageUrl: "4"
    },
    {
      id: 6, name: "教皇", meaning: "传统、教育、道德", reversedMeaning: "非传统、激进思想",
      description: "象征传统价值观、教育和精神指导。", imageUrl: "5"
    },
    {
      id: 7, name: "恋人", meaning: "爱情、关系、和谐", reversedMeaning: "冲突、不和谐",
      description: "代表爱情、关系和重要的人生选择。", imageUrl: "6"
    },
    {
      id: 8, name: "战车", meaning: "胜利、意志力、决心", reversedMeaning: "失控、缺乏方向",
      description: "象征克服障碍、取得胜利和坚定的决心。", imageUrl: "7"
    },
    {
      id: 9, name: "力量", meaning: "勇气、毅力、同情", reversedMeaning: "软弱、无力",
      description: "代表内在力量、勇气和坚韧不拔的精神。", imageUrl: "8"
    },
    {
      id: 10, name: "隐士", meaning: "反思、独处、内省", reversedMeaning: "孤立、固执",
      description: "象征智慧、内省和精神探索。", imageUrl: "9"
    },
    {
      id: 11, name: "命运之轮", meaning: "变化、周期、命运", reversedMeaning: "坏运气、停滞",
      description: "代表生活中的变化和不可预测的命运转折。", imageUrl: "10"
    },
    {
      id: 12, name: "正义", meaning: "公平、诚实、法律", reversedMeaning: "不公、失衡",
      description: "象征公正、真理和因果报应。", imageUrl: "11"
    },
    {
      id: 13, name: "倒吊人", meaning: "牺牲、等待、新视角", reversedMeaning: "不情愿、延迟",
      description: "代表为了更大的目标而做出的牺牲和新的视角。", imageUrl: "12"
    },
    {
      id: 14, name: "死神", meaning: "结束、转变、重生", reversedMeaning: "抗拒改变、停滞",
      description: "象征结束和新的开始，重要的生命转折点。", imageUrl: "13"
    },
    {
      id: 15, name: "节制", meaning: "平衡、耐心、调和", reversedMeaning: "极端、不平衡",
      description: "代表和谐、平衡和适度的重要性。", imageUrl: "14"
    },
    {
      id: 16, name: "恶魔", meaning: "束缚、物质主义、恐惧", reversedMeaning: "解放、释放",
      description: "象征物质诱惑、束缚和恐惧。", imageUrl: "15"
    },
    {
      id: 17, name: "塔", meaning: "突然变化、启示、破坏", reversedMeaning: "逃避、避免",
      description: "代表突然的改变、觉醒和破坏性的启示。", imageUrl: "16"
    },
    {
      id: 18, name: "星星", meaning: "希望、灵感、指导", reversedMeaning: "绝望、悲观",
      description: "象征希望、灵感和精神上的指引。", imageUrl: "17"
    },
    {
      id: 19, name: "月亮", meaning: "幻象、恐惧、潜意识", reversedMeaning: "真相揭露、澄清",
      description: "代表幻象、恐惧和潜意识的领域。", imageUrl: "18"
    },
    {
      id: 20, name: "太阳", meaning: "成功、快乐、活力", reversedMeaning: "暂时挫折、缺乏热情",
      description: "象征成功、快乐和积极的能量。", imageUrl: "19"
    },
    {
      id: 21, name: "审判", meaning: "重生、内省、精神觉醒", reversedMeaning: "自我怀疑、拒绝",
      description: "代表精神觉醒、重生和重要的决定。", imageUrl: "20"
    },
    {
      id: 22, name: "世界", meaning: "完成、成就、结束", reversedMeaning: "不完整、延迟",
      description: "象征完成、成就和生命的圆满。", imageUrl: "21"
    }
  ];

  private readingModes: ReadingMode[] = [
    { name: "单张指引", positions: ["今日启示"], count: 1 },
    { name: "三张圣三角", positions: ["过去", "现在", "未来"], count: 3 },
    { name: "凯尔特十字", positions: ["现状", "阻碍", "目标", "根源", "过去", "未来", "自我", "环境", "希望", "结果"], count: 10 }
  ];

  async aboutToAppear() {
    let result = await ZzuNetwork.verifyCampusNetwork();
    this.isZzuMode = result.isZzu;
    this.isNetworkChecked = true;
  }

  drawCards() {
    this.readingResults = [];
    this.aiInterpretation = '';
    this.actionPrompt = '';
    
    // 复制牌组并洗牌
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
    
    // 按所选模式抽取
    const count = this.readingModes[this.selectedMode].count;
    for (let i = 0; i < count; i++) {
      const card = shuffled[i];
      // 随机决定正逆位 (40% 逆位)
      const isReversed = Math.random() < 0.4;
      this.readingResults.push({
        card: card,
        isReversed: isReversed,
        position: this.readingModes[this.selectedMode].positions[i]
      });
    }
    this.showResults = true;
  }

  getAIInterpretation() {
    if (this.readingResults.length === 0) return;
    this.isAILoading = true;
    const theme = this.keyword.trim() || "当前的内心困惑";
    const modeName = this.readingModes[this.selectedMode].name;

    let prompt = `【角色设定】你是一位温暖的资深塔罗占卜师，结合用户具体关切给出深刻且 actionable 的独立行动建议。
【用户关注】「${theme}」
【占卜牌阵】${modeName}\n`;
    this.readingResults.forEach((res, index) => {
      const pos = this.readingModes[this.selectedMode].positions[index] || `位置${index+1}`;
      const orientation = res.isReversed ? "逆位" : "正位";
      const meaning = res.isReversed ? res.card.reversedMeaning : res.card.meaning;
      prompt += `- ${pos}：${res.card.name}（${orientation}）, 象征: ${meaning}\n`;
    });
    prompt += `【要求】
1. 分析必须紧扣“${theme}”。
2. 避免泛泛而谈或套话。
3. 最后一段**必须**用 "【塔罗建议行动】：<具体可执行的一句话单次行动>" 的格式结尾，用于引导用户将其作为待办任务。不要包含任何Markdown加粗符号。`;

    const endpoint = AppConfig.AI_CHAT_COMPLETIONS_PROXY_URL;

    if (endpoint.length === 0) {
      this.isAILoading = false;
      this.aiInterpretation = 'AI 解读暂未配置代理地址。请先启动 backend/server.py，并在 AppConfig 中填写电脑局域网代理地址。';
      return;
    }

    let reqBody: SiliconFlowReqBody = {
      model: AppConfig.AI_MODEL,
      messages: [ { role: "user", content: prompt } ],
      temperature: 0.7,
      max_tokens: 550
    };

    AuthenticatedHttpClient.request(endpoint, {
      method: http.RequestMethod.POST,
      extraData: JSON.stringify(reqBody),
      connectTimeout: 15000,
      readTimeout: 60000
    }).then((data: http.HttpResponse) => {
      this.isAILoading = false;
      if (data.responseCode !== 200) {
        this.aiInterpretation = `AI 解读请求失败（${data.responseCode}），请稍后重试。`;
        return;
      }
      try {
        const aiResponse = JSON.parse(data.result as string) as SiliconFlowResponse;
        if (aiResponse.choices && aiResponse.choices.length > 0) {
          let content = aiResponse.choices[0].message.content.trim();
          this.aiInterpretation = content;
          let match = content.match(/【塔罗建议行动】：(.*)/);
          if (match && match[1]) {
            this.actionPrompt = match[1].trim();
          } else {
             this.actionPrompt = "跟随心声前行，顺其自然";
          }
        }
      } catch (e) {
        this.aiInterpretation = "塔罗波长失准，解读解析失败。";
      }
    }).catch(() => {
      this.isAILoading = false;
      this.aiInterpretation = 'AI 解读请求失败，请检查登录状态和网络连接。';
    });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 模糊暗夜遮罩层，增加模糊滤镜
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(13, 17, 23, 0.85)') // 更深的柔和遮罩
        .backdropBlur(30)
        .onClick((): void => { this.onClose(); })

      Column() {
        // 顶部操作栏
        Row() {
          Row() {
            Text('‹').fontSize(20).fontColor('#D8C4E6').margin({ right: 6 })
            Text('返回').fontSize(14).fontColor('#D8C4E6')
          }
          .padding({ left: 16, right: 20, top: 6, bottom: 6 })
          .backgroundColor('rgba(255, 255, 255, 0.08)')
          .borderRadius(20)
          .onClick((): void => { this.onClose(); })
        }
        .width('100%')
        .padding({ top: 32, left: 24, bottom: 12 })

        // 柔和浮动容器
        Column() {
          Scroll() {
            Column() {
              // 标题区
              Column() {
                Row() {
                  Text('嵩 月 塔 罗')
                    .fontSize(32)
                    .fontColor('#E0B0FF') // 梦幻淡紫
                    .letterSpacing(8)
                    .fontWeight(FontWeight.Bolder)
                  
                  if (this.isNetworkChecked) {
                    Circle({ width: 6, height: 6 })
                      .fill(this.isZzuMode ? '#9D65C9' : '#FFA500')
                      .margin({ left: 6, top: 6 })
                      .shadow({ radius: 4, color: this.isZzuMode ? 'rgba(157, 101, 201, 0.8)' : 'rgba(255, 165, 0, 0.8)' })
                  }
                }
                .alignItems(VerticalAlign.Top)
                .margin({ top: 20, bottom: 6 })
                
                Text('宇宙的星体正在聆听你的潜意识')
                  .fontSize(12)
                  .fontColor('rgba(224, 176, 255, 0.7)')
                  .margin({ bottom: 30 })

                // 分割线
                Row().width('40%').height(1)
                  .linearGradient({
                     direction: GradientDirection.Right,
                     colors: [['rgba(224, 176, 255, 0)', 0.0], ['#E0B0FF', 0.5], ['rgba(224, 176, 255, 0)', 1.0]]
                  })
                  .margin({ bottom: 30 })
              }.alignItems(HorizontalAlign.Center)

              // 主题输入 (更加柔和梦幻)
              TextInput({ placeholder: "默默在心里念出你的问题，或在此输入..." })
                .width('90%').height(48)
                .backgroundColor('rgba(0, 0, 0, 0.3)')
                .border({ width: 1, color: 'rgba(224, 176, 255, 0.3)', radius: 24 })
                .fontColor(ColorConstants.TEXT_PRIMARY)
                .placeholderColor('rgba(255,255,255,0.4)')
                .padding({ left: 24, right: 24 })
                .onChange((v) => { this.keyword = v; })
                .margin({ bottom: 24 })

              // 模式切换
              Row({ space: 14 }) {
                ForEach([0, 1, 2], (idx: number) => {
                  Text(this.readingModes[idx].name)
                    .height(36).padding({ left: 16, right: 16 })
                    .borderRadius(18).textAlign(TextAlign.Center)
                    .backgroundColor(this.selectedMode === idx ? '#9D65C9' : 'rgba(255,255,255,0.06)')
                    .fontColor(this.selectedMode === idx ? '#FFFFFF' : 'rgba(255,255,255,0.6)')
                    .fontWeight(this.selectedMode === idx ? FontWeight.Bold : FontWeight.Normal)
                    .onClick(() => {
                      this.selectedMode = idx;
                      this.showResults = false;
                      this.readingResults = [];
                    })
                    .animation({ duration: 300, curve: Curve.EaseInOut })
                })
              }.margin({ bottom: 32 })

              // 洗牌按钮
              Button(this.showResults ? "命运重置 / 重新洗牌" : "翻开命运的帷幕")
                .width('80%').height(52)
                .borderRadius(26)
                .linearGradient({
                  direction: GradientDirection.Right,
                  colors: [['#9D65C9', 0.0], ['#C48CE0', 1.0]]
                })
                .fontColor('#FFFFFF')
                .fontSize(16).fontWeight(FontWeight.Bold)
                .shadow({ radius: 16, color: 'rgba(157, 101, 201, 0.4)', offsetY: 4 })
                .onClick(() => { this.drawCards(); })
                .margin({ bottom: 40 })

              // 抽牌结果区
              if (this.showResults && this.readingResults.length > 0) {
                // 卡牌展示
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
                  ForEach(this.readingResults, (res: ReadingResult) => {
                     FlipCardItem({ result: res })
                       .margin({ left: 10, right: 10, bottom: 24 })
                  })
                }
                .margin({ bottom: 30 })

                // AI 解读模块
                Button(this.isAILoading ? '召唤灵感 解析降临中...' : '召唤潜意识解析')
                   .height(44).padding({ left: 28, right: 28 }).borderRadius(22)
                   .backgroundColor('rgba(157,101,201,0.1)')
                   .border({ width: 1.5, color: '#C48CE0' })
                   .fontColor('#E0B0FF').fontSize(14).fontWeight(FontWeight.Medium)
                   .onClick(() => { if (!this.isAILoading) this.getAIInterpretation(); })
                   .margin({ bottom: 24 })

                if (this.aiInterpretation) {
                   Column() {
                     Text('塔罗密语')
                       .fontSize(12).fontColor('#9D65C9').margin({ bottom: 10 }).alignSelf(ItemAlign.Start)
                     Text(this.aiInterpretation)
                       .fontSize(14).lineHeight(24).fontColor('rgba(255,255,255,0.9)')
                   }
                   .width('90%').padding(20)
                   .backgroundColor('rgba(255,255,255,0.04)')
                   .borderRadius(20).border({ width: 1, color: 'rgba(255,255,255,0.1)' })
                   .backdropBlur(10)
                   .margin({ bottom: 24 })
                   .transition({ type: TransitionType.Insert, opacity: 1, translate: { y: 20 } })
                   .animation({ duration: 500, curve: Curve.FastOutSlowIn })
                   
                   if (this.actionPrompt) {
                     Text(`🔮 下一步指引`).fontSize(13).fontColor('#C48CE0').margin({ bottom: 12 })
                     Button(this.actionPrompt)
                        .height(50).width('90%').padding({ left: 20, right: 20 })
                        .linearGradient({
                           direction: GradientDirection.Right,
                           colors: [['#4DA1A9', 0.0], ['#6BCB77', 1.0]]
                        })
                        .fontColor('#FFFFFF').fontWeight(FontWeight.Bold).fontSize(14)
                        .borderRadius(25).shadow({ radius: 12, color: 'rgba(107, 203, 119, 0.3)' })
                        .onClick(() => { this.onResult(this.actionPrompt); })
                        .margin({ bottom: 40 })
                   }
                }
              }

              Blank().height(100)
            }
            .width('100%')
            .padding({ top: 10 })
            .alignItems(HorizontalAlign.Center)
          }
          .scrollable(ScrollDirection.Vertical)
          .scrollBar(BarState.Off)
          .width('100%')
          .layoutWeight(1)
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('rgba(0,0,0,0.2)')
        .borderRadius({ topLeft: 32, topRight: 32 })
        .border({ width: { top: 1, left: 1, right: 1 }, color: 'rgba(255,255,255,0.05)' })
        .shadow({ radius: 30, color: 'rgba(0,0,0,0.5)' })
      }
      .width('100%')
      .height('100%')
    }
  }
}

@Component
struct FlipCardItem {
  @Prop result: ReadingResult;
  @State rotateAngle: number = 0;
  @State isFlipped: boolean = false;

  build() {
    Column() {
      // 阵型位置标签
      Text(this.result.position)
        .fontSize(12)
        .fontColor('#E0B0FF')
        .margin({ bottom: 6 })
        .fontWeight(FontWeight.Medium)

      Stack() {
        if (this.rotateAngle < 90) {
           Image($r('app.media.answer_book_bg'))
              .width(96).height(144)
              .objectFit(ImageFit.Cover)
              .borderRadius(12)
              .border({ width: 1.5, color: 'rgba(255,255,255,0.2)' })
              .shadow({ radius: 8, color: 'rgba(157, 101, 201, 0.4)' })
        } else {
           Stack() {
              Image($r('app.media.' + this.result.card.imageUrl))
                 .width('100%').height('100%')
                 .objectFit(ImageFit.Cover)
                 .borderRadius(12)
                 .rotate({ z: 1, angle: this.result.isReversed ? 180 : 0 })
           }
           .width(96).height(144)
           .backgroundColor('rgba(0,0,0,0.5)')
           .border({ width: 1.5, color: '#C48CE0' })
           .borderRadius(12)
           .rotate({ y: 1, angle: 180 })
        }
      }
      .rotate({ y: 1, angle: this.rotateAngle })
      .animation({ duration: 800, curve: Curve.FastOutSlowIn })
      .onClick(() => {
        if (!this.isFlipped) {
           this.isFlipped = true;
           this.rotateAngle = 180;
        }
      })

      // 地位名称标识
      if (this.isFlipped) {
         Text(`${this.result.card.name} ${this.result.isReversed ? '(逆)' : '(正)'}`)
            .fontSize(12)
            .fontColor(ColorConstants.TEXT_PRIMARY)
            .margin({ top: 8 })
            .width(96)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .transition({ type: TransitionType.Insert, opacity: 1 })
      } else {
         Text('点击翻转')
            .fontSize(11)
            .fontColor(ColorConstants.TEXT_SECONDARY)
            .margin({ top: 8 })
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width(106)
  }
}
