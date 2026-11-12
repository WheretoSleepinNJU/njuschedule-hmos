/**
 * 半模态统一配置。
 *
 * 内容型半模态按内容高度自适应，内部 Scroll 负责超长内容滚动；
 * 切换课表等工具型半模态使用 LARGE 高度。
 */
import { Colors } from '../design/Tokens';
import { BreakpointName } from '../design/Breakpoints';

/**
 * 半模态形态按官方断点选择：
 * - < 600vp（Xs/Sm）：BOTTOM；
 * - >= 600vp（Md/Lg/Xl）：CENTER。
 * 不沿用 >= 840vp 的默认 POPUP，避免跟手弹窗随锚点跑到不可见位置。
 */
function preferTypeFor(breakpoint: string): SheetType {
  return breakpoint === BreakpointName.Md || breakpoint === BreakpointName.Lg ||
    breakpoint === BreakpointName.Xl ? SheetType.CENTER : SheetType.BOTTOM;
}

/**
 * 内容型半模态：FIT_CONTENT + 可拖动关闭 + 统一遮罩/背景。
 *
 * 显隐状态由 bindSheet 的 $$ 双向绑定维护；不在 onDisappear 里重复置 false，
 * 否则关闭动画结束时的旧回调可能覆盖刚发起的新一次打开。
 */
export function contentSheetOptions(breakpoint: string): SheetOptions {
  return {
    height: SheetSize.FIT_CONTENT,
    dragBar: true,
    showClose: false,
    preferType: preferTypeFor(breakpoint),
    maskColor: Colors.Scrim,
    onWillDismiss: (action: DismissSheetAction) => {
      action.dismiss();
    },
    backgroundColor: Colors.Background
  };
}

/** 工具栏型半模态：固定 LARGE 高度。 */
export function pickerSheetOptions(breakpoint: string): SheetOptions {
  return {
    height: SheetSize.LARGE,
    dragBar: false,
    showClose: false,
    preferType: preferTypeFor(breakpoint),
    maskColor: Colors.Scrim,
    onWillDismiss: (action: DismissSheetAction) => {
      action.dismiss();
    },
    backgroundColor: Colors.Background
  };
}
