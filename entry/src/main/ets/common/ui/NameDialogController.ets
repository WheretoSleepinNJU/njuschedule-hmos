/**
 * 命名弹窗控制器：统一管理 promptAction.openCustomDialog 的打开/关闭。
 *
 * 弹窗内容由调用页面提供，且必须是组件内 @Builder 的箭头包装（官方 FAQ，否则闪退）；
 * 这里只负责 dialogId 的保存与异常处理，避免各页面重复同一套开/关代码。
 */
import { UIContext } from '@kit.ArkUI';

export class NameDialogController {
  private dialogId: number = -1;

  /** 关闭当前弹窗；未打开时不处理。 */
  async close(ctx: UIContext): Promise<void> {
    if (this.dialogId < 0) {
      return;
    }
    const id: number = this.dialogId;
    this.dialogId = -1;
    try {
      ctx.getPromptAction().closeCustomDialog(id);
    } catch (err) {
      console.warn(`[NameDialog] close failed: ${JSON.stringify(err)}`);
    }
  }

  /** 先关掉旧弹窗，再用调用方提供的 builder 打开新弹窗。 */
  async open(ctx: UIContext, builder: () => void): Promise<void> {
    await this.close(ctx);
    try {
      this.dialogId = await ctx.getPromptAction().openCustomDialog({
        builder: builder,
        autoCancel: true,
        alignment: DialogAlignment.Center
      });
    } catch (err) {
      console.error(`[NameDialog] open failed: ${JSON.stringify(err)}`);
    }
  }
}
