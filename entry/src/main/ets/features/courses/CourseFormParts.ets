/**
 * 课程表单内部通用组件（只被 features/courses 使用）。
 *
 * 刻意不放进 `common/ui`：这些组件带着课程表单的语义（必填星号、周次 chip、
 * 色池色块），不是跨功能通用件。视觉全部走 design/Tokens 令牌。
 */
import { Colors, FontSize, Radius, Spacing } from '../../common/design/Tokens';
import { AppStore } from '../../app/AppStore';
import { SettingsItemGroup } from '../../common/ui/SettingsListItems';

/** 表单分区卡片：标题 + 说明 + 内容。 */
@ComponentV2
export struct FormSection {
  @Param title: string = '';
  @BuilderParam content: () => void;

  build() {
    Column({ space: Spacing.Sm }) {
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(FontSize.BodySm)
          .fontColor(Colors.TextTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: Spacing.Md, right: Spacing.Md })

      SettingsItemGroup() {
        this.content()
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}

/** 文本框：单行输入 / 多行备注共用，V2 下用 `@Param text + @Event onTextChange` 双向同步给父组件。 */
@ComponentV2
export struct CourseTextField {
  @Param label: string = '';
  @Param placeholder: string = '';
  @Param multiline: boolean = false;
  @Param required: boolean = false;
  @Param error: string = '';
  /** 输入框左侧实时颜色预览圆（自定义色值用）。 */
  @Param leadingColor: string = '';
  @Param showLeadingColor: boolean = false;
  @Param text: string = '';
  @Event onTextChange: (value: string) => void = () => {
  };

  build() {
    Column({ space: 2 }) {
      if (this.multiline) {
        Row({ space: Spacing.Md }) {
          Row({ space: 2 }) {
            Text(this.label)
              .fontSize(FontSize.Body)
              .fontColor(Colors.TextSecondary)
              .maxLines(1)
            if (this.required) {
              Text('*')
                .fontSize(FontSize.Caption)
                .fontColor(Colors.Error)
            }
          }
          .constraintSize({ minWidth: 72 })
          .alignItems(VerticalAlign.Center)

          TextArea({ text: this.text, placeholder: this.placeholder })
            .layoutWeight(1)
            .height(96)
            .fontSize(FontSize.Body)
            .fontColor(Colors.TextPrimary)
            .placeholderColor(Colors.TextTertiary)
            .backgroundColor(Colors.SurfaceHigh)
            .borderRadius(Radius.Sm)
            .padding(Spacing.Sm)
            .onChange((value: string) => {
              this.onTextChange(value);
            })
        }
        .width('100%')
        .padding({ left: Spacing.Md, right: Spacing.Md, top: Spacing.Sm, bottom: Spacing.Sm })
        .alignItems(VerticalAlign.Top)
      } else {
        Row({ space: Spacing.Md }) {
          Row({ space: 2 }) {
            Text(this.label)
              .fontSize(FontSize.Body)
              .fontColor(Colors.TextSecondary)
              .maxLines(1)
            if (this.required) {
              Text('*')
                .fontSize(FontSize.Caption)
                .fontColor(Colors.Error)
            }
          }
          .constraintSize({ minWidth: 72 })
          .alignItems(VerticalAlign.Center)

          Row({ space: Spacing.Sm }) {
            if (this.showLeadingColor) {
              Column()
                .width(20)
                .height(20)
                .borderRadius(Radius.Round)
                .backgroundColor(this.leadingColor === '' ? Colors.SurfaceHigh : this.leadingColor)
                .border({ width: 1, color: Colors.Outline })
            }
            TextInput({ text: this.text, placeholder: this.placeholder })
              .layoutWeight(1)
              .height(40)
              .fontSize(FontSize.Body)
              .fontColor(Colors.TextPrimary)
              .placeholderColor(Colors.TextTertiary)
              .textAlign(TextAlign.Start)
              .style(TextInputStyle.Default)
              .backgroundColor(Colors.SurfaceHigh)
              .borderRadius(Radius.Sm)
              .padding({ left: Spacing.Md, right: Spacing.Md })
              .onChange((value: string) => {
                this.onTextChange(value);
              })
          }
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .constraintSize({ minHeight: 56 })
        .padding({ left: Spacing.Md, right: Spacing.Md })
        .alignItems(VerticalAlign.Center)
      }

      if (this.error !== '') {
        Text(this.error)
          .fontSize(FontSize.Caption)
          .fontColor(Colors.Error)
          .padding({ left: Spacing.Md, right: Spacing.Md })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}

/** 单选 chip：星期、节次、周次类型等短选项。 */
@ComponentV2
export struct SelectChip {
  /** V2 全局 Store（主题色）。 */
  @Local store: AppStore = AppStore.connect();
  @Param label: string = '';
  @Param selected: boolean = false;
  @Event onSelect: () => void = () => {
  };

  build() {
    Text(this.label)
      .fontSize(FontSize.BodySm)
      .fontColor(this.selected ? this.store.accentOn : Colors.TextSecondary)
      .backgroundColor(this.selected ? this.store.accentDisplay : Colors.SurfaceHigh)
      .borderRadius(Radius.Sm)
      .padding({
        left: Spacing.Md,
        right: Spacing.Md,
        top: Spacing.Xs + 2,
        bottom: Spacing.Xs + 2
      })
      .margin({ right: Spacing.Sm, bottom: Spacing.Sm })
      .onClick(() => {
        this.onSelect();
      })
  }
}
