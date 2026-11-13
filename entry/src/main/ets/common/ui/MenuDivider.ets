/**
 * 长按 / 右键 / 下拉菜单统一的分割线样式。
 *
 * 数值与官方 Menu 示例一致：1vp、内嵌在菜单内、系统三级背景色。
 */
import { LengthMetrics } from '@kit.ArkUI';

export function menuItemDividerStyle(): DividerStyleOptions {
  return {
    strokeWidth: LengthMetrics.vp(1),
    color: $r('sys.color.comp_background_tertiary'),
    mode: DividerMode.EMBEDDED_IN_MENU
  };
}
