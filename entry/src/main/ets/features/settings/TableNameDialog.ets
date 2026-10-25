/**
 * 课表命名弹窗（新建 / 重命名共用）。
 *
 * 状态管理 V2 下使用官方 DialogV2 的 `CustomContentDialogV2` 承载表单内容与操作按钮，
 * 弹窗容器、标题、内容区和按钮区交给系统组件，避免自行绘制对话框。
 * 打开 / 关闭由调用方（ManageTablesPage）通过 `promptAction.openCustomDialog` 控制。
 */
import { AdvancedDialogV2Button, ColorMetrics, CustomContentDialogV2 } from '@kit.ArkUI';
import { AppStore } from '../../app/AppStore';
import { Colors, FontSize, Radius, Spacing } from '../../common/design/Tokens';
import { Feedback } from '../../common/ui/Feedback';

@ComponentV2
export struct TableNameDialog {
  /** V2 全局 Store（主题色）。 */
  @Local store: AppStore = AppStore.connect();
  /** 弹窗标题，如「新建课表」。 */
  @Param title: string = '';
  /** 输入框初始值（重命名时为原名）。 */
  @Param initialName: string = '';
  /** 确认按钮文字。 */
  @Param confirmText: string = '确定';
  /** 确认回调（关闭由调用方负责）。 */
  @Event onSubmit: (name: string) => void = () => {
  };
  /** 取消/关闭回调。 */
  @Event onCancel: () => void = () => {
  };

  @Local name: string = '';

  aboutToAppear(): void {
    this.name = this.initialName;
  }

  private trimmedName(): string {
    return this.name.trim();
  }

  private submit(): void {
    const value: string = this.trimmedName();
    if (value === '') {
      Feedback.toast(this.getUIContext(), '请输入课表名称');
      return;
    }
    this.onSubmit(value);
  }

  @Builder
  private nameInput() {
    TextInput({ text: this.name, placeholder: '请输入课表名称' })
      .width('100%')
      .height(44)
      .maxLength(30)
      .fontSize(FontSize.Body)
      .fontColor(Colors.TextPrimary)
      .placeholderColor(Colors.TextTertiary)
      .backgroundColor(Colors.SurfaceHigh)
      .borderRadius(Radius.Md)
      .padding({ left: Spacing.Md, right: Spacing.Md })
      .onChange((value: string) => {
        this.name = value;
      })
      .onSubmit(() => {
        this.submit();
      })
  }

  build() {
    CustomContentDialogV2({
      primaryTitle: this.title,
      contentBuilder: () => {
        this.nameInput()
      },
      buttons: [
        new AdvancedDialogV2Button({
          content: '取消',
          fontColor: ColorMetrics.resourceColor(this.store.accentDisplay),
          action: () => {
            this.onCancel();
          }
        }),
        new AdvancedDialogV2Button({
          content: this.confirmText,
          background: ColorMetrics.resourceColor(this.store.accentDisplay),
          fontColor: ColorMetrics.resourceColor(this.store.accentOn),
          enabled: this.trimmedName() !== '',
          action: () => {
            this.submit();
          }
        })
      ]
    })
  }
}
