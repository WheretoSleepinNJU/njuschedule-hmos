/**
 * TextPickerDialog 强调色适配。
 *
 * 确认按钮/选中项使用应用强调色，取消按钮使用次要文字色；
 * 其余背景、材质、文字样式全部保持系统默认。
 */
import { AppStore } from '../../app/AppStore';
import { Colors } from '../design/Tokens';

/** 给 TextPickerDialogOptions 应用强调色（原地修改并返回）。 */
export function applyTextPickerAccent(store: AppStore, options: TextPickerDialogOptions): TextPickerDialogOptions {
  options.acceptButtonStyle = {
    fontColor: store.accentDisplay
  };
  options.selectedTextStyle = {
    color: store.accentDisplay
  };
  options.cancelButtonStyle = {
    fontColor: Colors.TextSecondary
  };
  return options;
}
