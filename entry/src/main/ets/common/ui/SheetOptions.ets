/**
 * 半模态统一配置。
 *
 * 内容型半模态按内容高度自适应，内部 Scroll 负责超长内容滚动；
 * 切换课表等工具型半模态使用 LARGE 高度。
 */
import { Colors } from '../design/Tokens';

/** 内容型半模态：FIT_CONTENT + 可拖动关闭 + 统一遮罩/背景。 */
export function contentSheetOptions(onDisappear: () => void): SheetOptions {
  return {
    height: SheetSize.FIT_CONTENT,
    dragBar: true,
    showClose: false,
    preferType: SheetType.BOTTOM,
    maskColor: Colors.Scrim,
    onDisappear: onDisappear,
    onWillDismiss: (action: DismissSheetAction) => {
      action.dismiss();
    },
    backgroundColor: Colors.Background
  };
}

/** 工具栏型半模态：固定 LARGE 高度。 */
export function pickerSheetOptions(onDisappear: () => void): SheetOptions {
  return {
    height: SheetSize.LARGE,
    dragBar: false,
    showClose: false,
    preferType: SheetType.BOTTOM,
    maskColor: Colors.Scrim,
    onDisappear: onDisappear,
    onWillDismiss: (action: DismissSheetAction) => {
      action.dismiss();
    },
    backgroundColor: Colors.Background
  };
}
