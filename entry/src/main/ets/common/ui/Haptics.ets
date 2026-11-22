/**
 * 轻量触觉反馈。
 *
 * 长按类交互统一使用系统预置的 soft 效果，保持与 HarmonyOS 原生振感一致。
 * 设备不支持振动或用户关闭系统振动时静默失败，不影响主流程。
 */
import { vibrator } from '@kit.SensorServiceKit';

export class Haptics {
  private static lastLongPressAt: number = 0;

  /** 长按触发；250ms 内重复调用只响应一次，避免菜单/动效重建时连续振动。 */
  static longPress(): void {
    const now: number = Date.now();
    if (now - Haptics.lastLongPressAt < 250) {
      return;
    }
    Haptics.lastLongPressAt = now;
    try {
      vibrator.startVibration({
        type: 'preset',
        effectId: vibrator.HapticFeedback.EFFECT_SOFT,
        count: 1
      }, {
        id: 0,
        usage: 'touch'
      }).catch(() => {
        // 设备无马达或系统振动关闭时忽略。
      });
    } catch (err) {
      // 不支持振动的设备静默降级。
    }
  }
}
