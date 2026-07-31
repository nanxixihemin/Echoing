import router from '@ohos.router';
import http from '@ohos.net.http';
import promptAction from '@ohos.promptAction';
import { ChatHistoryManager, ChatSession, ChatMsg } from '../service/ChatHistoryManager';
import common from '@ohos.app.ability.common';
import { AppConfig } from '../common/AppConfig';
import { AuthenticatedHttpClient } from '../service/AuthenticatedHttpClient';
import { EchoColors, EchoRadius, EchoSpacing } from '../utils/EchoTheme';

interface RouterParams {
  interpretation?: string;
  theme?: string;
  sessionId?: string;
}

// ====== SiliconFlow API ======
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

interface ChatMessage {
  id: number;
  role: 'user' | 'assistant';
  content: string;
}

@Entry
@Component
struct AIDialogPage {
  @State messages: ChatMessage[] = [];
  @State userInput: string = '';
  @State isLoading: boolean = false;
  @State titleScale: number = 1;
  @State dotCount: number = 0;
  private nextId: number = 1;
  private dotTimer: number = -1;
  private systemPrompt: string = '';
  // 会话持久化
  private sessionId: string = '';
  private sessionTheme: string = '';
  private memoryContext: string = '';

  aboutToAppear() {
    const params = router.getParams() as RouterParams;
    const interpretation = params.interpretation ?? '';
    const theme = params.theme ?? '你当前最关心的人生议题';
    const existingSessionId = params.sessionId ?? '';

    this.sessionTheme = theme;

    // 初始化 ChatHistoryManager
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const mgr = ChatHistoryManager.getInstance();
      mgr.initialize(context).then(() => {
        // 获取 AI 记忆上下文
        mgr.getMemoryContext((ctx: string) => {
          this.memoryContext = ctx;
          this.buildSystemPrompt(interpretation, theme);
        });

        // 如果有 sessionId，说明是从历史页跳入
        if (existingSessionId.length > 0) {
          this.sessionId = existingSessionId;
          mgr.getSession(existingSessionId).then((session: ChatSession | null) => {
            if (session !== null) {
              this.sessionTheme = session.theme;
              this.systemPrompt = session.systemPrompt;
              let restored: ChatMessage[] = [];
              for (let i = 0; i < session.messages.length; i++) {
                let m = session.messages[i];
                let cm: ChatMessage = {
                  id: m.id,
                  role: m.role === 'user' ? 'user' : 'assistant',
                  content: m.content
                };
                restored.push(cm);
                if (m.id >= this.nextId) {
                  this.nextId = m.id + 1;
                }
              }
              this.messages = restored;
            }
          });
        } else {
          // 新会话
          this.sessionId = ChatHistoryManager.generateId();
          if (interpretation.length > 0) {
            this.messages = [{
              id: this.nextId++,
              role: 'assistant',
              content: interpretation
            }];
          }
        }
      });
    } catch (e) {
      // fallback: 不使用历史
      this.sessionId = `s_${Date.now()}`;
      this.buildSystemPrompt(interpretation, theme);
      if (interpretation.length > 0) {
        this.messages = [{
          id: this.nextId++,
          role: 'assistant',
          content: interpretation
        }];
      }
    }

    setInterval(() => {
      this.titleScale = this.titleScale === 1 ? 1.04 : 1;
    }, 1800);
  }

  aboutToDisappear() {
    if (this.dotTimer !== -1) {
      clearInterval(this.dotTimer);
    }
    // 页面销毁时保存会话
    this.saveCurrentSession();
  }

  private buildSystemPrompt(interpretation: string, theme: string): void {
    let prompt = `你是一位资深塔罗占卜师，擅长以"嵩月塔罗占卜师"的身份为用户提供温暖且深刻的解读。本次占卜主题为：${theme}。请围绕此主题展开。`;
    if (interpretation.length > 0) {
      prompt += `\n以下是你刚才给出的初始解读，请基于此继续对话：\n${interpretation}`;
    }
    if (this.memoryContext.length > 0) {
      prompt += `\n\n${this.memoryContext}`;
      prompt += `\n请结合以上历史记忆，在对话中自然地呼应用户过往的经历。`;
    }
    prompt += `\n注意：回复请保持自然、温暖、有深度，语气坚定而不模糊，不使用 Markdown 格式，不要在末尾标注字数。`;
    this.systemPrompt = prompt;
  }

  private async saveCurrentSession(): Promise<void> {
    if (this.messages.length === 0) return;
    try {
      const mgr = ChatHistoryManager.getInstance();
      const context = getContext(this) as common.UIAbilityContext;
      await mgr.initialize(context);
      // 将 ChatMessage[] 转为 ChatMsg[]
      let msgs: ChatMsg[] = [];
      for (let i = 0; i < this.messages.length; i++) {
        let m = this.messages[i];
        let cm: ChatMsg = {
          id: m.id,
          role: m.role,
          content: m.content
        };
        msgs.push(cm);
      }

      // 自动摘要：取最后一条 AI 回复的前 30 字
      let summary = '';
      for (let i = this.messages.length - 1; i >= 0; i--) {
        if (this.messages[i].role === 'assistant') {
          summary = this.messages[i].content.substring(0, 30);
          break;
        }
      }

      let session: ChatSession = {
        id: this.sessionId,
        theme: this.sessionTheme,
        summary: summary,
        systemPrompt: this.systemPrompt,
        createdAt: Date.now(),
        updatedAt: Date.now(),
        messages: msgs
      };
      await mgr.saveSession(session);
    } catch (e) {
      // ignore save errors
    }
  }

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

        Column({ space: 2 }) {
          Text('对话陪伴')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(EchoColors.TEXT_PRIMARY)
          Text(this.sessionTheme)
            .fontSize(10)
            .fontColor(EchoColors.TEXT_TERTIARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)

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
            this.saveCurrentSession();
            router.pushUrl({
              url: 'pages/ChatHistoryPage'
            });
          })
      }
      .width('100%')
      .padding({ left: EchoSpacing.PAGE, right: EchoSpacing.PAGE, top: 16, bottom: 10 })
      .alignItems(VerticalAlign.Center)

      List({ space: 12 }) {
        if (this.messages.length === 0 && !this.isLoading) {
          ListItem() {
            Column({ space: 8 }) {
              Text('从你此刻最在意的事情开始')
                .fontSize(17)
                .fontWeight(600)
                .fontColor(EchoColors.TEXT_PRIMARY)
              Text('不需要组织好语言，想到什么就说什么')
                .fontSize(13)
                .fontColor(EchoColors.TEXT_SECONDARY)
            }
            .width('100%')
            .padding({ top: 60, bottom: 30 })
          }
        }

        ForEach(
          this.messages,
          (item: ChatMessage) => {
            ListItem() {
              Column() {
                if (item.role === 'assistant') {
                  Text('Echoing')
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(EchoColors.TEXT_SECONDARY)
                    .margin({ bottom: 4 })
                    .alignSelf(ItemAlign.Start)
                }

                Row() {
                  if (item.role === 'user') {
                    Blank()
                  }

                  Text(item.content)
                    .fontSize(14)
                    .fontColor(item.role === 'user' ? '#FFFFFF' : EchoColors.TEXT_PRIMARY)
                    .lineHeight(22)
                    .wordBreak(WordBreak.BREAK_ALL)
                    .constraintSize({ maxWidth: '82%' })
                    .backgroundColor(item.role === 'user' ? EchoColors.PRIMARY : EchoColors.SURFACE)
                    .border(item.role === 'assistant' ? { width: 1, color: EchoColors.BORDER } : { width: 0 })
                    .borderRadius(EchoRadius.MEDIUM)
                    .padding({ left: 14, right: 14, top: 11, bottom: 11 })

                  if (item.role === 'assistant') {
                    Blank()
                  }
                }
                .width('100%')
              }
              .width('100%')
            }
            .key(item.id.toString())
          },
          (item: ChatMessage) => item.id.toString()
        )

        if (this.isLoading) {
          ListItem() {
            Column() {
              Text('正在整理回应')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(EchoColors.TEXT_SECONDARY)
                .margin({ bottom: 4 })
                .alignSelf(ItemAlign.Start)

              Text(this.getLoadingDots())
                .fontSize(18)
                .fontColor(EchoColors.MINT_TEXT)
                .fontWeight(FontWeight.Bold)
                .backgroundColor(EchoColors.MINT_SOFT)
                .borderRadius(EchoRadius.MEDIUM)
                .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                .alignSelf(ItemAlign.Start)
            }
            .width('100%')
          }
        }
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: EchoSpacing.PAGE, right: EchoSpacing.PAGE })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      Row({ space: 8 }) {
        TextInput({
          placeholder: '继续说说…',
          text: this.userInput
        })
          .onChange((value: string) => {
            this.userInput = value;
          })
          .layoutWeight(1)
          .height(46)
          .backgroundColor(EchoColors.SURFACE)
          .fontColor(EchoColors.TEXT_PRIMARY)
          .placeholderColor(EchoColors.TEXT_TERTIARY)
          .border({ width: 1, color: EchoColors.BORDER })
          .borderRadius(EchoRadius.PILL)
          .padding({ left: 14, right: 14 })

        Button('发送')
          .width(64)
          .height(46)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor(this.userInput.trim().length > 0 ? EchoColors.PRIMARY : EchoColors.TEXT_TERTIARY)
          .borderRadius(EchoRadius.PILL)
          .enabled(this.userInput.trim().length > 0 && !this.isLoading)
          .onClick(() => {
            this.sendMessage();
          })
      }
      .width('100%')
      .padding({ left: EchoSpacing.PAGE, right: EchoSpacing.PAGE, top: 8, bottom: 22 })
      .backgroundColor(EchoColors.PAGE)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EchoColors.PAGE)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private getLoadingDots(): string {
    let d = this.dotCount % 4;
    if (d === 0) return '·';
    if (d === 1) return '··';
    if (d === 2) return '···';
    return '····';
  }

  private sendMessage(): void {
    const trimmed = this.userInput.trim();
    if (!trimmed || this.isLoading) return;
    this.userInput = '';

    this.messages.push({
      id: this.nextId++,
      role: 'user',
      content: trimmed
    });
    this.isLoading = true;
    this.dotCount = 0;

    this.dotTimer = setInterval(() => {
      this.dotCount++;
    }, 500);

    let apiMessages: SiliconFlowMessage[] = [];

    if (this.systemPrompt.length > 0) {
      let sysMsg: SiliconFlowMessage = {
        role: 'system',
        content: this.systemPrompt
      };
      apiMessages.push(sysMsg);
    }

    for (let i = 0; i < this.messages.length; i++) {
      let msg = this.messages[i];
      let sfMsg: SiliconFlowMessage = {
        role: msg.role === 'user' ? 'user' : 'assistant',
        content: msg.content
      };
      apiMessages.push(sfMsg);
    }

    let reqBody: SiliconFlowReqBody = {
      model: AppConfig.AI_MODEL,
      messages: apiMessages,
      temperature: 0.7,
      max_tokens: 600
    };

    const endpoint = AppConfig.AI_CHAT_COMPLETIONS_PROXY_URL;

    AuthenticatedHttpClient.request(endpoint, {
      method: http.RequestMethod.POST,
      extraData: JSON.stringify(reqBody),
      connectTimeout: 15000,
      readTimeout: 30000
    }).then((data: http.HttpResponse) => {
        this.isLoading = false;
        if (this.dotTimer !== -1) {
          clearInterval(this.dotTimer);
          this.dotTimer = -1;
        }

        if (data.responseCode !== 200) {
          let errMsg = '网络请求失败，请重试。';
          if (data.responseCode === 403) errMsg = '该接口暂无访问权限。';
          if (data.responseCode === 429) errMsg = '请求过于频繁，请稍后再试。';
          this.messages.push({
            id: this.nextId++,
            role: 'assistant',
            content: errMsg
          });
          return;
        }

        try {
          const resp: SiliconFlowResponse = JSON.parse(data.result as string);

          if (!resp.choices || resp.choices.length === 0) {
            this.messages.push({
              id: this.nextId++,
              role: 'assistant',
              content: '未获取到有效解读数据，请稍后重试。'
            });
            return;
          }

          let aiText = resp.choices[0].message.content.trim();

          aiText = aiText.replace(/<think>[\s\S]*?<\/think>/g, '');
          aiText = aiText
            .replace(/\*\*(.*?)\*\*/g, '$1')
            .replace(/\*(.*?)\*/g, '$1')
            .replace(/`/g, '')
            .replace(/^#{1,6}\s+/gm, '')
            .replace(/^\s*-\s+/gm, '- ')
            .replace(/\n\s*\n/g, '\n\n')
            .trim();

          if (aiText.length === 0) {
            aiText = '暂未获得有效回复，请再试一次。';
          }

          this.messages.push({
            id: this.nextId++,
            role: 'assistant',
            content: aiText
          });
        } catch (e) {
          this.messages.push({
            id: this.nextId++,
            role: 'assistant',
            content: '数据解析失败，请重试。'
          });
        }
    }).catch(() => {
      this.isLoading = false;
      if (this.dotTimer !== -1) {
        clearInterval(this.dotTimer);
        this.dotTimer = -1;
      }
      this.messages.push({
        id: this.nextId++,
        role: 'assistant',
        content: '网络请求失败，请重试。'
      });
    });
  }
}
