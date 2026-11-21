/**
 * 导出到系统日历的 DialogV2 弹窗。
 *
 * 使用 CustomContentDialogV2 让系统负责对话框容器和底部按钮布局。
 * 系统自带按钮点击后会关闭弹窗，因此本组件只负责选择提醒方式；
 * 真正导出由设置页在关闭后显示加载 Dialog 完成。
 */
import { AdvancedDialogV2Button, ColorMetrics, CustomContentDialogV2 } from '@kit.ArkUI';
import { AppStore } from '../../app/AppStore';
import { Colors, FontSize, Spacing } from '../../common/design/Tokens';
import { CalendarExport } from '../../data/CalendarExport';

@ComponentV2
export struct CalendarExportDialog {
  @Local store: AppStore = AppStore.connect();
  @Param tableName: string = '';
  @Event onClose: () => void = () => {
  };
  /** 用户确认导出；参数为提醒分钟数，0 表示不提醒。 */
  @Event onExport: (reminderMinutes: number) => void = (_minutes: number) => {
  };

  @Local reminderEnabled: boolean = false;
  @Local reminderIndex: number = 1;

  private reminderChoices(): string[] {
    return CalendarExport.reminderChoices().map((minutes: number) => `提前 ${minutes} 分钟`);
  }

  private reminderMinutes(): number {
    const choices: number[] = CalendarExport.reminderChoices();
    const index: number = Math.max(0, Math.min(this.reminderIndex, choices.length - 1));
    return choices[index];
  }

  @Builder
  private dialogContent(): void {
    Column({ space: Spacing.Md }) {
      Text(this.tableName === '' ? '当前课表' : `当前课表：${this.tableName}`)
        .fontSize(FontSize.BodySm)
        .fontColor(Colors.TextSecondary)
        .width('100%')
      Text('以课表同名独立账户储存，导出前请确认当前周正确')
        .fontSize(FontSize.Caption)
        .fontColor(Colors.TextTertiary)
        .lineHeight(18)
        .width('100%')

      Row({ space: Spacing.Md }) {
        Column({ space: 2 }) {
          Text('课程提醒')
            .fontSize(FontSize.Body)
            .fontColor(Colors.TextPrimary)
          Text(this.reminderEnabled ? '将在课程开始前提醒' : '不发送提醒')
            .fontSize(FontSize.Caption)
            .fontColor(Colors.TextTertiary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.reminderEnabled })
          .selectedColor(this.store.accentDisplay)
          .onChange((isOn: boolean) => {
            this.reminderEnabled = isOn;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.reminderEnabled) {
        TextPicker({
          range: this.reminderChoices(),
          selected: this.reminderIndex
        })
          .width('100%')
          .height(150)
          .selectedTextStyle({
            color: this.store.accentDisplay,
            font: { size: '18fp', weight: FontWeight.Medium }
          })
          .onChange((_value: string | string[], index: number | number[]) => {
            this.reminderIndex = Array.isArray(index) ? index[0] : index as number;
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    CustomContentDialogV2({
      primaryTitle: '导出到系统日历',
      contentBuilder: () => {
        this.dialogContent()
      },
      buttons: [
        new AdvancedDialogV2Button({
          content: '取消',
          fontColor: ColorMetrics.resourceColor(Colors.TextSecondary),
          action: () => {
            this.onClose();
          }
        }),
        new AdvancedDialogV2Button({
          content: '开始导出',
          fontColor: ColorMetrics.resourceColor(this.store.accentDisplay),
          action: () => {
            this.onExport(this.reminderEnabled ? this.reminderMinutes() : 0);
          }
        })
      ]
    })
  }
}
