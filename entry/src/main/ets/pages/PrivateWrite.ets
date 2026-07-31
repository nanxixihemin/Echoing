// MainAbility/pages/PrivateWrite.ets
// 私密花园 - 写下心事，种一朵花

import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import dataPreferences from '@ohos.data.preferences';
import { AIResponseGenerator } from '../utils/AIResponseGenerator';
import { EchoColors, EchoRadius, EchoSpacing } from '../utils/EchoTheme';

interface LeafPosition {
  x: number;
  y: number;
  angle: number;
  scale: number;
}

interface PrivateLeafData {
  id: string;
  content: string;
  timestamp: number;
  tags: string[];
  isImportant: boolean;
  aiResponse: string;
  position: LeafPosition;
}

const STORE_NAME: string = 'private_garden_store';
const LEAVES_KEY: string = 'private_leaves';
const CUSTOM_TAGS_KEY: string = 'custom_tags';
const GUEST_ACCOUNT_KEY: string = 'guest';

const PRESET_TAGS: string[] = ['学业', '情感', '生活', '压力', '开心', '迷茫', '目标', '感恩'];

const TAG_COLORS: Record<string, string> = {
  '学业': '#6C9BD2', '情感': '#D4849A', '生活': '#7BB88A', '压力': '#D4A06A',
  '开心': '#D4C76A', '迷茫': '#A688C0', '目标': '#6ABCBC', '感恩': '#D48A6A'
};

@Entry
@Component
struct PrivateWrite {
  @State inputContent: string = '';
  @State selectedTags: string[] = [];
  @State customTags: string[] = [];
  @State allTags: string[] = PRESET_TAGS;
  @State newTagInput: string = '';
  @State showAddTag: boolean = false;
  @State aiResponse: string = '';
  @State showAIResponse: boolean = false;
  @State isSubmitting: boolean = false;
  @StorageProp('currentAccountKey') currentAccountKey: string = '';

  private store: dataPreferences.Preferences | null = null;

  aboutToAppear(): void {
    this.loadCustomTags();
  }

  private async getStore(): Promise<dataPreferences.Preferences> {
    if (this.store === null) {
      const ctx = getContext(this);
      this.store = await dataPreferences.getPreferences(ctx, STORE_NAME);
    }
    return this.store;
  }

  private getAccountKey(): string {
    return this.currentAccountKey.length > 0 ? this.currentAccountKey : GUEST_ACCOUNT_KEY;
  }

  private getScopedKey(baseKey: string): string {
    return `${baseKey}.${this.getAccountKey()}`;
  }

  private async getScopedValue(store: dataPreferences.Preferences, baseKey: string, defaultValue: string): Promise<string> {
    const scopedKey = this.getScopedKey(baseKey);
    const scopedData: dataPreferences.ValueType = await store.get(scopedKey, '');
    if (typeof scopedData === 'string' && scopedData.length > 0) {
      return scopedData;
    }

    const legacyData: dataPreferences.ValueType = await store.get(baseKey, '');
    if (typeof legacyData === 'string' && legacyData.length > 0) {
      await store.put(scopedKey, legacyData);
      await store.put(baseKey, '');
      await store.flush();
      return legacyData;
    }

    return defaultValue;
  }

  private getTagColor(tagName: string): string {
    const color: string | undefined = TAG_COLORS[tagName];
    if (color) return color;
    let hash: number = 0;
    for (let i = 0; i < tagName.length; i++) {
      hash = tagName.charCodeAt(i) + ((hash << 5) - hash);
    }
    return `hsl(${Math.abs(hash % 360)}, 45%, 60%)`;
  }

  private generateId(): string {
    return `leaf_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
  }

  private generatePosition(): LeafPosition {
    return {
      x: 0.1 + Math.random() * 0.8,
      y: 0.1 + Math.random() * 0.6,
      angle: -30 + Math.random() * 60,
      scale: 0.7 + Math.random() * 0.4
    };
  }

  private async loadCustomTags(): Promise<void> {
    try {
      const store: dataPreferences.Preferences = await this.getStore();
      const data: string = await this.getScopedValue(store, CUSTOM_TAGS_KEY, '[]');
      this.customTags = JSON.parse(data) as string[];
      this.allTags = [...PRESET_TAGS, ...this.customTags];
    } catch (e) {
      console.error('PrivateWrite', 'Load tags failed');
    }
  }

  private async saveCustomTags(): Promise<void> {
    try {
      const store: dataPreferences.Preferences = await this.getStore();
      await store.put(this.getScopedKey(CUSTOM_TAGS_KEY), JSON.stringify(this.customTags));
      await store.flush();
    } catch (e) {
      console.error('PrivateWrite', 'Save tags failed');
    }
  }

  private addCustomTag(): void {
    const tag: string = this.newTagInput.trim();
    if (tag.length === 0) {
      promptAction.showToast({ message: '标签不能为空' });
      return;
    }
    if (tag.length > 6) {
      promptAction.showToast({ message: '标签最多6个字' });
      return;
    }
    if (this.allTags.includes(tag)) {
      promptAction.showToast({ message: '标签已存在' });
      return;
    }

    this.customTags = [...this.customTags, tag];
    this.allTags = [...PRESET_TAGS, ...this.customTags];
    this.saveCustomTags();
    this.newTagInput = '';
    this.showAddTag = false;
  }

  private toggleTag(tagName: string): void {
    const index: number = this.selectedTags.indexOf(tagName);
    if (index >= 0) {
      const newTags: string[] = [];
      for (let i = 0; i < this.selectedTags.length; i++) {
        if (this.selectedTags[i] !== tagName) {
          newTags.push(this.selectedTags[i]);
        }
      }
      this.selectedTags = newTags;
    } else if (this.selectedTags.length < 3) {
      this.selectedTags = [...this.selectedTags, tagName];
    } else {
      promptAction.showToast({ message: '最多选择3个标签' });
    }
  }

  private async submitLeaf(): Promise<void> {
    if (this.inputContent.trim().length === 0 || this.isSubmitting) {
      return;
    }

    this.isSubmitting = true;
    const aiRes: string = AIResponseGenerator.generate(this.inputContent);

    const newLeaf: PrivateLeafData = {
      id: this.generateId(),
      content: this.inputContent.trim(),
      timestamp: Date.now(),
      tags: [...this.selectedTags],
      isImportant: false,
      aiResponse: aiRes,
      position: this.generatePosition()
    };

    try {
      const store: dataPreferences.Preferences = await this.getStore();
      const data: string = await this.getScopedValue(store, LEAVES_KEY, '[]');
      let leaves: PrivateLeafData[] = [];
      leaves = JSON.parse(data) as PrivateLeafData[];
      leaves = [newLeaf, ...leaves];
      await store.put(this.getScopedKey(LEAVES_KEY), JSON.stringify(leaves));
      await store.flush();

      this.aiResponse = aiRes;
      this.showAIResponse = true;
      this.inputContent = '';
      this.selectedTags = [];

      promptAction.showToast({ message: '花朵已种下' });
    } catch (e) {
      promptAction.showToast({ message: '保存失败' });
    }

    this.isSubmitting = false;
  }

  build() {
    Column() {
      this.TopBar()

      Scroll() {
        Column({ space: 16 }) {
          if (this.showAIResponse) {
            this.AIResponseCard()
          }

          Column({ space: 6 }) {
            Text('写下此刻')
              .fontSize(26)
              .fontWeight(700)
              .fontColor(EchoColors.TEXT_PRIMARY)
            Text('这里的内容只属于你，不需要把话说得很完整')
              .fontSize(13)
              .fontColor(EchoColors.TEXT_SECONDARY)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column() {
            TextArea({ placeholder: '今天有什么想说的吗？', text: this.inputContent })
              .fontSize(15)
              .fontColor(EchoColors.TEXT_PRIMARY)
              .placeholderColor(EchoColors.TEXT_TERTIARY)
              .backgroundColor(Color.Transparent)
              .height(190)
              .maxLength(500)
              .onChange((value: string) => {
                this.inputContent = value;
              })

            Text(`${this.inputContent.length}/500`)
              .fontSize(11)
              .fontColor(EchoColors.TEXT_TERTIARY)
              .alignSelf(ItemAlign.End)
              .margin({ right: 14, bottom: 10 })
          }
          .width('100%')
          .backgroundColor(EchoColors.SURFACE)
          .borderRadius(EchoRadius.LARGE)
          .border({ width: 1, color: EchoColors.BORDER })

          Column({ space: 12 }) {
            Row() {
              Column({ space: 2 }) {
                Text('给这段心情加个标签')
                  .fontSize(14)
                  .fontWeight(600)
                  .fontColor(EchoColors.TEXT_PRIMARY)
                Text('可选，最多选择 3 个')
                  .fontSize(11)
                  .fontColor(EchoColors.TEXT_TERTIARY)
              }
              .alignItems(HorizontalAlign.Start)

              Blank()

              Text(this.showAddTag ? '收起' : '自定义')
                .fontSize(12)
                .fontWeight(500)
                .fontColor(EchoColors.PRIMARY_DARK)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .backgroundColor(EchoColors.PRIMARY_SOFT)
                .borderRadius(EchoRadius.PILL)
                .onClick(() => {
                  this.showAddTag = !this.showAddTag;
                })
            }
            .width('100%')

            if (this.showAddTag) {
              Row({ space: 10 }) {
                TextInput({ placeholder: '输入标签名', text: this.newTagInput })
                  .fontSize(14)
                  .maxLength(6)
                  .backgroundColor(EchoColors.PAGE)
                  .fontColor(EchoColors.TEXT_PRIMARY)
                  .placeholderColor(EchoColors.TEXT_TERTIARY)
                  .border({ width: 1, color: EchoColors.BORDER })
                  .borderRadius(EchoRadius.SMALL)
                  .height(42)
                  .layoutWeight(1)
                  .onChange((value: string) => {
                    this.newTagInput = value;
                  })

                Button('添加')
                  .fontSize(13)
                  .height(42)
                  .backgroundColor(EchoColors.PRIMARY)
                  .fontColor('#FFFFFF')
                  .borderRadius(EchoRadius.SMALL)
                  .onClick(() => {
                    this.addCustomTag();
                  })
              }
              .width('100%')
            }

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.allTags, (tagName: string) => {
                Text(tagName)
                  .fontSize(13)
                  .fontColor(this.selectedTags.includes(tagName) ? '#FFFFFF' : this.getTagColor(tagName))
                  .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                  .backgroundColor(this.selectedTags.includes(tagName)
                    ? this.getTagColor(tagName)
                    : this.getTagColor(tagName) + '18')
                  .borderRadius(EchoRadius.PILL)
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => {
                    this.toggleTag(tagName);
                  })
              }, (tagName: string) => tagName)
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor(EchoColors.SURFACE)
          .borderRadius(EchoRadius.LARGE)
          .border({ width: 1, color: EchoColors.BORDER })

          Button(this.isSubmitting ? '正在保存…' : '保存这段心情')
            .width('100%')
            .height(52)
            .fontSize(15)
            .fontWeight(600)
            .fontColor('#FFFFFF')
            .backgroundColor(this.inputContent.trim().length > 0 ? EchoColors.PRIMARY : EchoColors.TEXT_TERTIARY)
            .borderRadius(EchoRadius.MEDIUM)
            .enabled(this.inputContent.trim().length > 0 && !this.isSubmitting)
            .onClick(() => {
              if (this.inputContent.trim().length > 0 && !this.isSubmitting) {
                this.submitLeaf();
              }
            })
        }
        .width('100%')
        .padding({ left: EchoSpacing.PAGE, right: EchoSpacing.PAGE, top: 20, bottom: 36 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EchoColors.PAGE)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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
        .onClick(() => { router.back(); })

      Blank()

      Text('私密树洞')
        .fontSize(17)
        .fontWeight(600)
        .fontColor(EchoColors.TEXT_PRIMARY)

      Blank()

      Column()
        .width(40)
        .height(40)
    }
    .width('100%')
    .padding({ left: EchoSpacing.PAGE, right: EchoSpacing.PAGE, top: 16, bottom: 8 })
  }

  @Builder
  AIResponseCard() {
    Column({ space: 8 }) {
      Row() {
        Text('给你的回应')
          .fontSize(13)
          .fontWeight(600)
          .fontColor(EchoColors.MINT_TEXT)
        Blank()
        Text('关闭')
          .fontSize(11)
          .fontColor(EchoColors.TEXT_TERTIARY)
      }
      .width('100%')

      Text(this.aiResponse)
        .fontSize(14)
        .fontColor(EchoColors.TEXT_SECONDARY)
        .lineHeight(23)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(EchoColors.MINT_SOFT)
    .borderRadius(EchoRadius.LARGE)
    .onClick(() => {
      this.showAIResponse = false;
    })
  }
}
