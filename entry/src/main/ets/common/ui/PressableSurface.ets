/**
 * 通用卡片按压反馈。
 *
 * 设置行与课程卡片共用同一套按下态：按下时背景从 Surface 变为 SurfaceHigh。
 * 使用 AttributeModifier 的 pressed 状态由框架管理，避免 onTouch 手动维护状态时
 * 在滑动/取消手势后卡在按下态。
 */
import { Colors } from '../design/Tokens';

class PressedSurfaceModifier implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(instance: CommonAttribute): void {
    instance.backgroundColor(Colors.Surface);
  }

  applyPressedAttribute(instance: CommonAttribute): void {
    instance.backgroundColor(Colors.SurfaceHigh);
  }
}

/** 单例即可复用；按压状态由组件实例自行管理。 */
export const PRESSED_SURFACE: AttributeModifier<CommonAttribute> = new PressedSurfaceModifier();
