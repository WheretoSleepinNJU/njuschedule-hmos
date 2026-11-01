/**
 * 全局反馈工具：Toast 与二次确认弹窗的统一样式（替代各页面复制的 9 份 toast / 5 份确认框）。
 *
 * 用法：
 *   Feedback.toast(this.getUIContext(), '已保存');
 *   Feedback.confirmDanger(this.getUIContext(), '删除课程', `确定删除「${name}」吗？`, '删除', () => this.deleteCourse());
 */
import { UIContext } from '@kit.ArkUI';
import { Colors } from '../design/Tokens';

export class Feedback {
  /** 系统 Toast（默认 1.5s）。 */
  static toast(ctx: UIContext, message: string, duration: number = 1500): void {
    try {
      ctx.getPromptAction().showToast({ message: message, duration: duration });
    } catch (err) {
      console.warn(`[Feedback] toast failed: ${JSON.stringify(err)}`);
    }
  }

  /** 危险操作二次确认（确认按钮为错误色）。 */
  static confirmDanger(ctx: UIContext, title: string, message: string,
    confirmText: string, onConfirm: () => void): void {
    try {
      ctx.showAlertDialog({
        title: title,
        message: message,
        autoCancel: true,
        primaryButton: {
          value: '取消',
          fontColor: Colors.TextSecondary,
          action: () => {
          }
        },
        secondaryButton: {
          value: confirmText,
          fontColor: Colors.Error,
          action: (): void => {
            onConfirm();
          }
        }
      });
    } catch (err) {
      console.warn(`[Feedback] confirmDanger failed: ${JSON.stringify(err)}`);
    }
  }

  /** 普通二次确认（确认按钮默认色，例如时间冲突「仍要保存」）。 */
  static confirm(ctx: UIContext, title: string, message: string,
    confirmText: string, onConfirm: () => void): void {
    try {
      ctx.showAlertDialog({
        title: title,
        message: message,
        autoCancel: true,
        primaryButton: {
          value: '取消',
          fontColor: Colors.TextSecondary,
          action: () => {
          }
        },
        secondaryButton: {
          value: confirmText,
          action: (): void => {
            onConfirm();
          }
        }
      });
    } catch (err) {
      console.warn(`[Feedback] confirm failed: ${JSON.stringify(err)}`);
    }
  }
}
