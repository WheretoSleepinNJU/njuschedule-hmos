/**
 * 主题配色卡片：预设与自定义色共用的色板示意 + 选中态。
 *
 * 自定义卡不接收外部颜色，直接读 Store 里的自定义色，保证改色后卡片立即刷新。
 */
import { AppStore } from '../../app/AppStore';
import { Colors, FontSize, Radius, Spacing } from '../../common/design/Tokens';

@ComponentV2
export struct ThemeColorCard {
  @Local store: AppStore = AppStore.connect();
  /** 预设色；custom 为 true 时忽略。 */
  @Param hex: string = '';
  @Param index: number = 0;
  @Param name: string = '';
  @Param desc: string = '';
  @Param custom: boolean = false;
  @Event onTap: () => void = () => {
  };

  private isSelected(): boolean {
    return this.store.themeAccentIndex === this.index;
  }

  private previewHex(): string {
    if (!this.custom) {
      return this.hex;
    }
    return this.store.themeCustomColor !== '' ? this.store.themeCustomColor : this.store.accentDisplay;
  }

  /** 色板示意：用该配色的深浅变体拼出类似「聊天气泡」的示意。 */
  @Builder
  private preview() {
    Column({ space: 5 }) {
      Row({ space: 6 }) {
        Row()
          .width(28)
          .height(10)
          .borderRadius(5)
          .backgroundColor(Colors.Surface)
        Row()
          .width(28)
          .height(10)
          .borderRadius(5)
          .backgroundColor(this.previewHex())
          .opacity(0.25)
        Blank()
        Row()
          .width(34)
          .height(18)
          .borderRadius(9)
          .backgroundColor(this.previewHex())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 6 }) {
        Row()
          .width(56)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.previewHex())
        Blank()
        Row()
          .width(26)
          .height(26)
          .borderRadius(13)
          .backgroundColor(this.previewHex())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row()
        .width(44)
        .height(8)
        .borderRadius(4)
        .backgroundColor(this.previewHex())
        .opacity(0.25)
    }
    .width('100%')
    .height(76)
    .padding(10)
    .backgroundColor(Colors.SurfaceHigh)
    .borderRadius(Radius.Md)
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: Spacing.Sm }) {
        this.preview()
        Text(this.name)
          .fontSize(FontSize.Body)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.TextPrimary)
          .width('100%')
          .maxLines(1)
        Text(this.desc)
          .fontSize(FontSize.Caption)
          .fontColor(Colors.TextTertiary)
          .width('100%')
          .maxLines(1)
      }
      .width('100%')
      .padding(Spacing.Md)
      .backgroundColor(Colors.Surface)
      .borderRadius(Radius.Xl)
      .border({
        width: this.isSelected() ? 2 : 1,
        color: this.isSelected() ? this.store.accentDisplay : Colors.OutlineLight
      })
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        this.onTap();
      })
      .clickEffect({ level: ClickEffectLevel.LIGHT })

      if (this.isSelected()) {
        Row() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(14)
            .fontColor([Colors.TextOnPrimary])
        }
        .width(24)
        .height(24)
        .borderRadius(Radius.Round)
        .backgroundColor(this.store.accentDisplay)
        .justifyContent(FlexAlign.Center)
        .margin({ right: Spacing.Md, bottom: Spacing.Sm })
      }
    }
    .width('48%')
    .margin({ bottom: Spacing.Md })
  }
}
