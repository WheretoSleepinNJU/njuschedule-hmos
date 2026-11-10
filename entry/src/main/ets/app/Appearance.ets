/**
 * 外观模式（移植旧版 `themeModeIndex`：0 = 跟随系统，1 = 浅色，2 = 深色）。
 *
 * HarmonyOS 侧通过 `ApplicationContext.setColorMode` 切换应用级深浅色；
 * 颜色本身仍由 `resources/base` 与 `resources/dark` 的资源限定词提供，
 * 所以这里只负责模式选择与持久化，不碰具体颜色值。
 */
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { WidgetData } from '../data/WidgetData';
import { AppPreferences, PrefKeys } from './AppPreferences';
import { AppState } from './AppState';
import { AppStore } from './AppStore';

export class Appearance {
  static readonly MODE_SYSTEM: number = 0;
  static readonly MODE_LIGHT: number = 1;
  static readonly MODE_DARK: number = 2;

  static index(): number {
    const value: number = AppState.store().themeModeIndex;
    return value >= Appearance.MODE_SYSTEM && value <= Appearance.MODE_DARK ? value : Appearance.MODE_SYSTEM;
  }

  /** 切换并持久化（旧版 key `themeModeIndex`）。 */
  static async apply(index: number, context: common.UIAbilityContext): Promise<void> {
    if (Appearance.index() === index) {
      return;
    }
    AppState.setThemeModeIndex(index);
    await AppPreferences.put(PrefKeys.ThemeModeIndex, index);
    Appearance.applyColorMode(index, context.getApplicationContext());
    // 立即按用户选择确定生效深浅色，不依赖 setColorMode 之后配置回调的到达时序
    // （之前读 resourceManager 有延迟：从深色切到浅色时仍读到深色，导致主题色自动提亮在浅色下也生效）。
    let dark: boolean = false;
    if (index === Appearance.MODE_DARK) {
      dark = true;
    } else if (index === Appearance.MODE_LIGHT) {
      dark = false;
    } else {
      // 触发式：使用启动时/系统回调记录的真正系统深浅色；不再用定时器校正
      dark = Appearance.systemDark(context);
    }
    AppState.setIsDark(dark);
    // 桌面小组件跟随深浅色：重算并推送卡片（异步，不阻塞主界面重绘）
    WidgetData.write().catch((err: Error) => {
      console.warn(`[Appearance] refresh widgets failed: ${JSON.stringify(err)}`);
    });
  }

  /**
   * 系统（跟随系统）的深色状态：只使用 EntryAbility 记录的值（系统回调/启动 config），
   * 不读 resourceManager.getConfigurationSync()——在主线程启动路径读配置曾导致卡死。
   */
  static systemDark(context: common.UIAbilityContext): boolean {
    const store: AppStore = AppState.store();
    if (store.systemIsDarkKnown) {
      return store.systemIsDark;
    }
    return context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  /**
   * 按「外观模式」确定生效的深色状态（课程块标题/次要文字/主题色提亮都依赖 isDark）：
   * - 强制浅色 → false；强制深色 → true；
   * - 跟随系统 → 系统深浅色（由 EntryAbility 记录，未知时读配置兜底）。
   * 不再直接读 resourceManager 的当前 Configuration（setColorMode 后存在更新延迟）。
   */
  static syncIsDark(context: common.UIAbilityContext): void {
    const index: number = AppState.store().themeModeIndex;
    let dark: boolean = false;
    if (index === Appearance.MODE_DARK) {
      dark = true;
    } else if (index === Appearance.MODE_LIGHT) {
      dark = false;
    } else {
      dark = Appearance.systemDark(context);
    }
    AppState.setIsDark(dark);
  }

  /** 启动时恢复。 */
  static async restore(context: common.UIAbilityContext): Promise<void> {
    const stored: number = await AppPreferences.getInt(PrefKeys.ThemeModeIndex, Appearance.MODE_SYSTEM);
    const index: number = stored >= Appearance.MODE_SYSTEM && stored <= Appearance.MODE_DARK ? stored : Appearance.MODE_SYSTEM;
    AppState.setThemeModeIndex(index);
    Appearance.applyColorMode(index, context.getApplicationContext());
  }

  private static applyColorMode(index: number, context: common.ApplicationContext): void {
    let mode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (index === Appearance.MODE_LIGHT) {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } else if (index === Appearance.MODE_DARK) {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    try {
      context.setColorMode(mode);
    } catch (err) {
      console.error(`[Appearance] setColorMode failed: ${JSON.stringify(err)}`);
    }
  }
}
