import router from '@ohos.router';

@Entry
@Component
struct Index {
  @State currentMode: string = 'private';
  @State currentDate: string = '';
  @State greeting: string = '';
  @State warmQuote: string = '';
  @State isDarkTime: boolean = false;
  @State quoteOpacity: number = 1;

  private warmQuotes: string[] = [
    '每一个今天，都是余生中最年轻的一天。',
    '你比想象中更勇敢，比看起来更坚强。',
    '允许自己慢慢来，成长不是一蹴而就的事。',
    '今天的你，已经很努力了。',
    '不必完美，只要真实。',
    '温柔对待自己，世界才会温柔对你。',
    '再小的努力，乘以365都很明显。',
    '深呼吸，一切都会好起来的。',
    '困难是暂时的，你的光芒是永恒的。',
    '你的存在本身就是一种力量。'
  ];

  // 定义5种动态相匹配的主题色：[背景色, 文字深色, 边栏亮色, 次要文字色]
  private themes: string[][] = [
    ['#FFF1F2', '#D81B60', '#F06292', '#F8BBD0'], // 粉色
    ['#F0F8FF', '#1E88E5', '#64B5F6', '#BBDEFB'], // 蓝色
    ['#F1F8E9', '#43A047', '#81C784', '#C8E6C9'], // 绿色
    ['#FFFDE7', '#FBC02D', '#FFF176', '#FFF59D'], // 黄色
    ['#F3E5F5', '#8E24AA', '#BA68C8', '#E1BEE7']  // 紫色
  ];

  private getCurrentTheme(): string[] {
    // 根据字符串长度取余数，确保每次相同的句子颜色一致，不同的句子颜色变化
    const index = this.warmQuote.length % this.themes.length;
    return this.themes[index];
  }

  aboutToAppear(): void {
    this.updateDateTime();
    this.updateGreeting();
    this.randomQuote();
  }

  private updateDateTime(): void {
    const now: Date = new Date();
    const month: number = now.getMonth() + 1;
    const day: number = now.getDate();
    const hours: number = now.getHours();
    const weekdays: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    const weekday: string = weekdays[now.getDay()];

    this.currentDate = `${month}月${day}日 ${weekday}`;
    this.isDarkTime = hours < 6 || hours >= 18;
  }

  private updateGreeting(): void {
    const hour: number = new Date().getHours();
    if (hour < 6) {
      this.greeting = '夜深了';
    } else if (hour < 12) {
      this.greeting = '早上好';
    } else if (hour < 14) {
      this.greeting = '中午好';
    } else if (hour < 18) {
      this.greeting = '下午好';
    } else if (hour < 22) {
      this.greeting = '晚上好';
    } else {
      this.greeting = '夜深了';
    }
  }

  private randomQuote(): void {
    const index: number = Math.floor(Math.random() * this.warmQuotes.length);
    this.warmQuote = this.warmQuotes[index];
  }

  private navigateTo(page: string): void {
    router.pushUrl({ url: `pages/${page}` });
  }

  // ---- 动态主题色 ----
  private getPageBg(): ResourceColor {
    return this.isDarkTime ? '#0F1419' : '#FAFAFA';
  }

  private getCardBg(): ResourceColor {
    return this.isDarkTime ? '#1C2530' : '#FFFFFF';
  }

  private getTextPrimary(): string {
    return this.isDarkTime ? '#E8ECF0' : '#1A1A2E';
  }

  private getTextSecondary(): string {
    return this.isDarkTime ? '#7A8A9E' : '#8C8C9A';
  }

  private getTextTertiary(): string {
    return this.isDarkTime ? '#4A5568' : '#BEBEC8';
  }

  private getAccentPrivate(): string {
    return this.isDarkTime ? '#7EC8C0' : '#5AAFA7';
  }

  private getAccentShared(): string {
    return this.isDarkTime ? '#8CC58F' : '#6AAF6D';
  }

  private getAccent(): string {
    return this.currentMode === 'private' ? this.getAccentPrivate() : this.getAccentShared();
  }

  private getDividerColor(): string {
    return this.isDarkTime ? '#2A3544' : '#F0F0F2';
  }

  build() {
    Stack() {
      // 背景图片 - 根据当前模式切换
      Image(this.currentMode === 'private' ? $r('app.media.private_garden_bg') : $rawfile('garden_bg.jpg'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 半透明遮罩层 - 动态调节背景亮度以保证文字和卡片的可读性，并衬托出深浅主题的氛围感
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.isDarkTime ? 'rgba(15, 23, 36, 0.78)' : 'rgba(255, 255, 255, 0.25)')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column() {
        // 顶部时间区域
        this.HeaderSection()

        // 模式切换
        this.ModeSwitchSection()

        // 功能入口
        this.ActionSection()

        // 暖心语
        this.QuoteSection()

        Blank()

        // 底部提示
        this.FooterSection()
      }
      .width('100%')
      .height('100%')
      .padding({ left: 24, right: 24 })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  HeaderSection() {
    Column({ space: 4 }) {
      // 顶部导航栏：精致返回按钮
      Row() {
        Row() {
          Text('‹')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getTextPrimary())
            .margin({ top: -3 })
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(this.isDarkTime ? 'rgba(255, 255, 255, 0.08)' : 'rgba(0, 0, 0, 0.05)')
        .border({ width: 1, color: this.isDarkTime ? 'rgba(255, 255, 255, 0.15)' : 'rgba(0, 0, 0, 0.08)' })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          router.back()
        })
        
        Blank()
      }
      .width('100%')
      .margin({ top: 0, bottom: 8 })

      Text(this.greeting)
        .fontSize(32)
        .fontWeight(700)
        .fontColor(this.getTextPrimary())
        .letterSpacing(1)

      Text(this.currentDate)
        .fontSize(14)
        .fontColor(this.getTextSecondary())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    // 增加顶部 padding 到 60 甚至 72，避开全面屏沉浸式状态栏 (expandSafeArea)
    .padding({ top: 48, bottom: 16 })
  }

  @Builder
  ModeSwitchSection() {
    Row({ space: 0 }) {
      // 私密花园
      Column({ space: 4 }) {
        Text('私密花园')
          .fontSize(15)
          .fontWeight(this.currentMode === 'private' ? 600 : 400)
          .fontColor(this.currentMode === 'private' ? this.getAccentPrivate() : this.getTextTertiary())

        Text('本地保存')
          .fontSize(11)
          .fontColor(this.currentMode === 'private' ? this.getAccentPrivate() : this.getTextTertiary())
          .opacity(this.currentMode === 'private' ? 0.7 : 0.5)
      }
      .layoutWeight(1)
      .padding({ top: 16, bottom: 14 })
      .alignItems(HorizontalAlign.Center)
      .border({
        width: { bottom: 2 },
        color: this.currentMode === 'private' ? this.getAccentPrivate() : 'transparent'
      })
      .onClick(() => {
        this.currentMode = 'private';
      })
      .animation({ duration: 250, curve: Curve.EaseOut })

      // 分割线
      Column()
        .width(1)
        .height(20)
        .backgroundColor(this.getDividerColor())

      // 共享森林
      Column({ space: 4 }) {
        Text('共享森林')
          .fontSize(15)
          .fontWeight(this.currentMode === 'shared' ? 600 : 400)
          .fontColor(this.currentMode === 'shared' ? this.getAccentShared() : this.getTextTertiary())

        Text('匿名分享')
          .fontSize(11)
          .fontColor(this.currentMode === 'shared' ? this.getAccentShared() : this.getTextTertiary())
          .opacity(this.currentMode === 'shared' ? 0.7 : 0.5)
      }
      .layoutWeight(1)
      .padding({ top: 16, bottom: 14 })
      .alignItems(HorizontalAlign.Center)
      .border({
        width: { bottom: 2 },
        color: this.currentMode === 'shared' ? this.getAccentShared() : 'transparent'
      })
      .onClick(() => {
        this.currentMode = 'shared';
      })
      .animation({ duration: 250, curve: Curve.EaseOut })
    }
    .width('100%')
    .backgroundColor(this.getCardBg())
    .borderRadius(14)
    .padding({ left: 8, right: 8 })
    .border({ width: 1, color: this.isDarkTime ? 'rgba(255, 255, 255, 0.08)' : 'rgba(0, 0, 0, 0.04)' })
    .shadow({
      radius: 12,
      color: this.isDarkTime ? 'rgba(0,0,0,0.3)' : 'rgba(0,0,0,0.04)',
      offsetY: 2
    })
  }

  @Builder
  ActionSection() {
    Column({ space: 12 }) {
      // 写心事入口
      Row() {
        Column({ space: 4 }) {
          Text(this.currentMode === 'private' ? '写下心事' : '挂一片叶子')
            .fontSize(17)
            .fontWeight(600)
            .fontColor(this.getTextPrimary())

          Text(this.currentMode === 'private' ? '种在你的私密花园里' : '让叶子随风飘向森林')
            .fontSize(13)
            .fontColor(this.getTextSecondary())
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column() {
          Text('→')
            .fontSize(16)
            .fontColor(this.getAccent())
            .opacity(0.8)
        }
        .width(36)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .borderRadius(18)
        .backgroundColor(this.getAccent() + '1A') // 使用带透明度的主色作为底色
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 22, bottom: 22 })
      .backgroundColor(this.getCardBg())
      .borderRadius(16)
      .border({ width: 1, color: this.isDarkTime ? 'rgba(255, 255, 255, 0.08)' : 'rgba(0, 0, 0, 0.04)' })
      .shadow({
        radius: 12,
        color: this.isDarkTime ? 'rgba(0,0,0,0.3)' : 'rgba(0,0,0,0.04)',
        offsetY: 2
      })
      .onClick(() => {
        if (this.currentMode === 'private') {
          this.navigateTo('PrivateWrite');
        } else {
          this.navigateTo('SharedWrite');
        }
      })

      // 查看入口
      Row() {
        Column({ space: 4 }) {
          Text(this.currentMode === 'private' ? '我的花园' : '漫步森林')
            .fontSize(17)
            .fontWeight(600)
            .fontColor(this.getTextPrimary())

          Text(this.currentMode === 'private' ? '回顾花开的时刻' : '看看其他叶子的故事')
            .fontSize(13)
            .fontColor(this.getTextSecondary())
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column() {
          Text('→')
            .fontSize(16)
            .fontColor(this.getAccent())
            .opacity(0.8)
        }
        .width(36)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .borderRadius(18)
        .backgroundColor(this.getAccent() + '1A') // 使用带透明度的主色作为底色
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 22, bottom: 22 })
      .backgroundColor(this.getCardBg())
      .borderRadius(16)
      .border({ width: 1, color: this.isDarkTime ? 'rgba(255, 255, 255, 0.08)' : 'rgba(0, 0, 0, 0.04)' })
      .shadow({
        radius: 12,
        color: this.isDarkTime ? 'rgba(0,0,0,0.3)' : 'rgba(0,0,0,0.04)',
        offsetY: 2
      })
      .onClick(() => {
        if (this.currentMode === 'private') {
          this.navigateTo('PrivateTree');
        } else {
          this.navigateTo('SharedForest');
        }
      })
    }
    .width('100%')
    .margin({ top: 24 })
  }

  @Builder
  QuoteSection() {
    Column({ space: 12 }) {
      Row() {
        Column()
          .width(3)
          .height(14)
          .borderRadius(2)
          .backgroundColor(this.getCurrentTheme()[2])
        
        Text('今日暖心语')
          .fontSize(12)
          .fontWeight(500)
          .fontColor('#E8A050')
          .letterSpacing(2)
          .margin({ left: 8 })
          
        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 引号装饰
      Text('＂')
        .fontSize(28)
        .fontColor(this.getCurrentTheme()[2])
        .fontWeight(FontWeight.Bold)
        .opacity(0.3)
        .margin({ top: 4, bottom: -12 })

      Text(`${this.warmQuote}`)
        .fontSize(16)
        .fontColor(this.getCurrentTheme()[1])
        .fontWeight(FontWeight.Medium)
        .lineHeight(28)
        .opacity(this.quoteOpacity)
        .textAlign(TextAlign.Start)
        .width('100%')
        .margin({ bottom: 12 })

      Row() {
        Blank()

        Row({ space: 4 }) {
          Text('↻')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#000000')
            .opacity(0.8)
          Text('换一条')
            .fontSize(12)
            .fontWeight(500)
            .fontColor('#000000')
            .opacity(0.8)
        }
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(this.getCurrentTheme()[2] + '33') // 卡片颜色加深作为背景
        .borderRadius(16)
        .onClick(() => {
          this.quoteOpacity = 0;
          setTimeout(() => {
            this.randomQuote();
            this.quoteOpacity = 1;
          }, 300);
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .margin({ top: 24 }) // 增加间隔，将其更靠下一点，留出呼吸感
    .backgroundColor(this.getCurrentTheme()[0])
    .borderRadius(20)
    .shadow({
      radius: 20,
      color: this.getCurrentTheme()[1] + '1A', // 阴影颜色与主题色呼应，降低透明度
      offsetY: 8
    })
    .animation({ duration: 400, curve: Curve.Smooth })
  }

  @Builder
  FooterSection() {
    Column({ space: 6 }) {
      Row({ space: 16 }) {
        Text('匿名安全')
          .fontSize(11)
          .fontColor(this.getTextTertiary())

        Text('·')
          .fontSize(11)
          .fontColor(this.getTextTertiary())

        Text('校内专属')
          .fontSize(11)
          .fontColor(this.getTextTertiary())

        Text('·')
          .fontSize(11)
          .fontColor(this.getTextTertiary())

        Text('温暖陪伴')
          .fontSize(11)
          .fontColor(this.getTextTertiary())
      }
      .justifyContent(FlexAlign.Center)

      Text('如需专业帮助  心理中心 0371-67783291')
        .fontSize(10)
        .fontColor(this.getTextTertiary())
    }
    .width('100%')
    .padding({ bottom: 24 })
  }
}

