/**
 * TextPickerDialog 强调色适配。
 *
 * 系统 TextPickerDialog 默认使用系统强调色；这里只把确认按钮和选中项文字
 * 改为应用强调色，其余背景、材质、文字样式全部保持系统默认。
 */
import { AppStore } from '../../app/AppStore';

/** 给 TextPickerDialogOptions 应用强调色（原地修改并返回）。 */
export function applyTextPickerAccent(store: AppStore, options: TextPickerDialogOptions): TextPickerDialogOptions {
  options.acceptButtonStyle = {
    fontColor: store.accentDisplay
  };
  options.selectedTextStyle = {
    color: store.accentDisplay
  };
  return options;
}
