/**
 * 半模态统一配置。
 *
 * 半模态按内容高度自适应，内部 Scroll 负责超长内容滚动。
 */
import { Colors } from '../design/Tokens';
import { BreakpointName } from '../design/Breakpoints';
import { DIALOG_MATERIAL } from './SystemMaterial';

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
 * 半模态内部二级页返回协调器。
 * 系统返回会先触发 bindSheet 的 onWillDismiss，而不是内部 NavDestination.onBackPressed；
 * 内容层把自己的二级页状态登记到这里，半模态层据此决定“返回上一级”还是关闭面板。
 * 参考：HarmonyOS FAQ faqs-arkui-1491、代码工坊 MineSettingView（sheet 内嵌 Navigation）。
 */
export class SheetBackCoordinator {
  canGoBack: boolean = false;
  goBack: () => void = () => {
  };
}

/**
 * 内容型半模态：FIT_CONTENT + 可拖动关闭 + 统一遮罩/系统材质。
 *
 * 显隐状态由 bindSheet 的 $$ 双向绑定维护；不在 onDisappear 里重复置 false，
 * 否则关闭动画结束时的旧回调可能覆盖刚发起的新一次打开。
 */
export function contentSheetOptions(breakpoint: string,
  backCoordinator?: SheetBackCoordinator): SheetOptions {
  return {
    height: SheetSize.FIT_CONTENT,
    dragBar: true,
    showClose: false,
    preferType: preferTypeFor(breakpoint),
    maskColor: Colors.Scrim,
    onWillDismiss: (action: DismissSheetAction) => {
      // 系统返回：有二级页时回二级页；否则按默认行为关闭半模态。
      if (action.reason === DismissReason.PRESS_BACK &&
        backCoordinator !== undefined && backCoordinator.canGoBack) {
        backCoordinator.goBack();
        return;
      }
      action.dismiss();
    },
    systemMaterial: DIALOG_MATERIAL
  };
}
