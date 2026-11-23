/**
 * TextPickerDialog 强调色与材质适配。
 *
 * 确认按钮/选中项使用应用强调色，取消按钮使用次要文字色；
 * 背景使用系统沉浸材质，其余文字样式保持系统默认。
 */
import { AppStore } from '../../app/AppStore';
import { Colors } from '../design/Tokens';
import { DIALOG_MATERIAL } from './SystemMaterial';

/** 给 TextPickerDialogOptionsExt 应用强调色和系统材质（原地修改并返回）。 */
export function applyTextPickerAccent(store: AppStore,
  options: TextPickerDialogOptionsExt): TextPickerDialogOptionsExt {
  options.systemMaterial = DIALOG_MATERIAL;
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
