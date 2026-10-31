/**
 * 跨功能复用的列表行组件。
 *
 * 设置页、教务导入、课程列表和课程编辑共用同一套卡片/行样式。
 */
import { Colors, FontSize, Radius, Spacing } from '../design/Tokens';
import { AppStore } from '../../app/AppStore';

/** 设置分组卡片：官方设置应用样式，圆角 24、内边距 4。 */
@ComponentV2
export struct SettingsItemGroup {
  /** 可选分类标题，显示在卡片上方。 */
  @Param title: string = '';
  @BuilderParam content: () => void;

  build() {
    Column({ space: Spacing.Sm }) {
      if (this.title !== '') {
        Text(this.title)
          .fontSize(FontSize.BodySm)
          .fontColor(Colors.TextTertiary)
          .width('100%')
          .padding({ left: Spacing.Md, right: Spacing.Md })
      }
      Column() {
        this.content()
      }
      .width('100%')
      .padding(4)
      .borderRadius(Radius.Xxl)
      .backgroundColor(Colors.Surface)
    }
    .width('100%')
  }
}

/** 组内分隔线：左边距 48，右边距 8。 */
@ComponentV2
export struct SettingsItemDivider {
  /** 左侧起始缩进；有图标的行用 48，无图标行传 12。 */
  @Param startMargin: number = 48;

  build() {
    Divider()
      .strokeWidth(1)
      .color(Colors.OutlineLight)
      .margin({ left: this.startMargin, right: 8 })
  }
}

/** 开关行：左侧标题/说明，右侧 Toggle。 */
@ComponentV2
export struct SettingsSwitchRow {
  /** V2 全局 Store（主题色 / 避让区）。 */
  @Local store: AppStore = AppStore.connect();
  /** 行首图标（HarmonyOS 系统图标库 sys.symbol.*）。 */
  @Param icon: Resource | undefined = undefined;
  @Param title: string = '';
  @Param subtitle: string = '';
  @Param isOn: boolean = false;
  @Event onToggle: (isOn: boolean) => void = () => {
  };

  build() {
    Row({ space: Spacing.Md }) {
      if (this.icon !== undefined) {
        SymbolGlyph(this.icon)
          .fontSize(24)
          .fontColor([Colors.TextSecondary])
      }
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(FontSize.Body)
          .fontColor(Colors.TextPrimary)
          .width('100%')
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(FontSize.BodySm)
            .fontColor(Colors.TextTertiary)
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(this.store.accentDisplay)
        .switchPointColor(Colors.Surface)
        .onChange((isOn: boolean) => {
          this.onToggle(isOn);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({ left: Spacing.Sm, right: Spacing.Sm })
    .borderRadius(Radius.Xl)
    .backgroundColor(Colors.Surface)
    .alignItems(VerticalAlign.Center)
  }
}

/** 设置行：跳转/信息/动作通用。图标 + 标题/说明 + 可选右侧值/箭头；danger 时标题/图标用错误色。 */
@ComponentV2
export struct SettingsRow {
  /** 行首图标（HarmonyOS 系统图标库 sys.symbol.*）。 */
  @Param icon: Resource | undefined = undefined;
  @Param title: string = '';
  @Param subtitle: string = '';
  @Param trailingText: string = '';
  /** 右侧箭头（跳转型页面用 true）。 */
  @Param showArrow: boolean = true;
  /** 外部网页链接：右侧显示“打开网页”符号；应用内跳转仍显示箭头。 */
  @Param externalLink: boolean = false;
  /** 危险操作（删除/清空）：标题与图标用错误色。 */
  @Param danger: boolean = false;
  @Event onTap: () => void = () => {
  };

  @Local isTouched: boolean = false;

  build() {
    Row({ space: Spacing.Md }) {
      if (this.icon !== undefined) {
        SymbolGlyph(this.icon)
          .fontSize(24)
          .fontColor([this.danger ? Colors.Error : Colors.TextSecondary])
      }
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(FontSize.Body)
          .fontColor(this.danger ? Colors.Error : Colors.TextPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(FontSize.BodySm)
            .fontColor(Colors.TextTertiary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.trailingText !== '') {
        Text(this.trailingText)
          .fontSize(FontSize.BodySm)
          .fontColor(Colors.TextTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 160 })
      }
      if (this.showArrow) {
        if (this.externalLink) {
          SymbolGlyph($r('sys.symbol.arrow_up_right'))
            .fontSize(18)
            .fontColor([Colors.TextTertiary])
        } else {
          Image($r('sys.media.ohos_ic_public_arrow_right'))
            .width(12)
            .height(24)
            .fillColor(Colors.TextTertiary)
        }
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({ left: Spacing.Sm, right: Spacing.Sm })
    .borderRadius(Radius.Xl)
    .backgroundColor(this.isTouched ? Colors.SurfaceHigh : Colors.Surface)
    .alignItems(VerticalAlign.Center)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.isTouched = true;
      } else if (event.type === TouchType.Up) {
        this.isTouched = false;
      }
    })
    .onClick(() => {
      this.isTouched = false;
      this.onTap();
    })
  }
}
