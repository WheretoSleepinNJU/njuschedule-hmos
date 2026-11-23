/**
 * 沉浸光感材质配置。
 *
 * 按组件场景区分材质等级：
 * - Dialog/半模态（AlertDialog/CustomDialog/PickerDialog/Sheet）：ULTRA_THICK；
 * - Menu/Toast：REGULAR；
 * - 标题栏胶囊：ULTRA_THIN/THIN，并保留交互光效。
 *
 * REGULAR/THICK/ULTRA_THICK 不启用 colorInvert：该能力仅在 THIN/ULTRA_THIN 下生效。
 */
import { uiMaterial } from '@kit.ArkUI';

/** 弹窗类材质，官方弹窗默认 ULTRA_THICK。 */
export const DIALOG_MATERIAL: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
  style: uiMaterial.ImmersiveStyle.ULTRA_THICK
});

/** 菜单与 Toast 材质。 */
export const REGULAR_MATERIAL: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
  style: uiMaterial.ImmersiveStyle.REGULAR
});

/** 标题栏/半模态胶囊的普通材质，与顶部课表切换胶囊保持一致。 */
export const CHIP_NORMAL_MATERIAL: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
  style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
  interactive: true,
  lightEffect: {},
  applyShadow: false
});

/** 标题栏/半模态胶囊的选中材质，用浅强调色着色。 */
export function chipSelectedMaterial(materialColor: ResourceColor): uiMaterial.ImmersiveMaterial {
  return new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    materialColor: materialColor,
    interactive: true,
    lightEffect: {},
    applyShadow: false
  });
}
