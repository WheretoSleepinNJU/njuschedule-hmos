/**
 * 全局反馈工具：Toast 与二次确认弹窗的统一样式（替代各页面复制的 9 份 toast / 5 份确认框）。
 *
 * 用法：
 *   Feedback.toast(this.getUIContext(), '已保存');
 *   Feedback.confirmDanger(this.getUIContext(), '删除课程', `确定删除「${name}」吗？`, '删除', () => this.deleteCourse());
 */
import { UIContext } from '@kit.ArkUI';
import { Colors } from '../design/Tokens';
import { DIALOG_MATERIAL, REGULAR_MATERIAL } from './SystemMaterial';

export class Feedback {
  /** 系统 Toast（默认 1.5s）。 */
  static toast(ctx: UIContext, message: string, duration: number = 1500): void {
    try {
      ctx.getPromptAction().showToast({
        message: message,
        duration: duration,
        systemMaterial: REGULAR_MATERIAL
      });
    } catch (err) {
      console.warn(`[Feedback] toast failed: ${JSON.stringify(err)}`);
    }
  }

  /** 危险操作二次确认（确认按钮为错误色）。 */
  static confirmDanger(ctx: UIContext, title: string, message: string,
    confirmText: string, onConfirm: () => void): void {
    Feedback.showConfirm(ctx, title, message, confirmText, onConfirm, Colors.Error);
  }

  /** 普通二次确认（确认按钮默认色，例如时间冲突「仍要保存」）。 */
  static confirm(ctx: UIContext, title: string, message: string,
    confirmText: string, onConfirm: () => void): void {
    Feedback.showConfirm(ctx, title, message, confirmText, onConfirm);
  }

  /** 两类确认框共用同一套取消/确认布局和系统材质。 */
  private static showConfirm(ctx: UIContext, title: string, message: string,
    confirmText: string, onConfirm: () => void, confirmColor?: ResourceColor): void {
    try {
      ctx.showAlertDialog({
        title: title,
        message: message,
        autoCancel: true,
        systemMaterial: DIALOG_MATERIAL,
        primaryButton: {
          value: '取消',
          fontColor: Colors.TextSecondary,
          action: () => {
          }
        },
        secondaryButton: {
          value: confirmText,
          fontColor: confirmColor,
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
