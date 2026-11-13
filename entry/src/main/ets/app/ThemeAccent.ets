/**
 * 主题强调色（移植旧版 `AppThemes.presetHexColors` 的 9 个预设）。
 *
 * 运行时"生效色"统一由 `AppStore.recomputeAccent()` + `ColorMath` 推导后写入
 * `accentDisplay / accentOn / accentSoft`，页面直接读 Store 字段；
 * 本类只负责预设/自定义色的持久化与启动恢复。
 */
import { ColorMath } from '../common/design/ColorMath';
import { WidgetData } from '../data/WidgetData';
import { AppPreferences, PrefKeys } from './AppPreferences';
import { AppState } from './AppState';

export class ThemeAccent {
  /** 与旧版 `lib/Resources/Themes.dart` 的 presetHexColors 一致、顺序一致（9 个预设）。 */
  /**
   * 预设主题色（顺序固定，widget 侧 THEME_PRESETS 需与此保持一致）。
   * 第 4 个「南哪紫」= 南京大学标准紫：官方 CMYK C50 M100 Y0 K40，
   * 换算 sRGB ≈ #4D0099。
   */
  static readonly PRESETS: string[] = ColorMath.PRESETS.slice();

  static readonly DEFAULT_INDEX: number = 0;
  static readonly CUSTOM_INDEX: number = 9;
  /** 当前自定义色（空串表示未设置）。 */
  private static customHex: string = '';

  /** 预设色（下标越界回落到默认色；自定义色下标不在此数组内）。 */
  static preset(index: number): string {
    if (index < 0 || index >= ThemeAccent.PRESETS.length) {
      return ThemeAccent.PRESETS[ThemeAccent.DEFAULT_INDEX];
    }
    return ThemeAccent.PRESETS[index];
  }

  static isHex(hex: string): boolean {
    return new RegExp('^#[0-9A-Fa-f]{6}$').test(hex);
  }

  static currentCustomHex(): string {
    return ThemeAccent.customHex;
  }

  /** 应用自定义色（旧版 themeCustomColor）：写入下标 9，持久化 hex。 */
  static async applyCustom(hex: string): Promise<boolean> {
    const normalized: string = hex.trim().toUpperCase();
    if (!ThemeAccent.isHex(normalized)) {
      return false;
    }
    ThemeAccent.customHex = normalized;
    AppState.setThemeCustomColor(normalized);
    AppState.setThemeAccentIndex(ThemeAccent.CUSTOM_INDEX);
    await AppPreferences.put(PrefKeys.ThemeCustomColor, normalized);
    await ThemeAccent.persistIndex(ThemeAccent.CUSTOM_INDEX);
    return true;
  }

  /** 切换主题并持久化（旧版 key `themeIndex`）。 */
  static async apply(index: number): Promise<void> {
    AppState.setThemeAccentIndex(index);
    await ThemeAccent.persistIndex(index);
  }

  /** 持久化主题下标并刷新桌面小组件。 */
  private static async persistIndex(index: number): Promise<void> {
    await AppPreferences.put(PrefKeys.ThemeIndex, index);
    ThemeAccent.refreshWidgets();
  }

  private static refreshWidgets(): void {
    WidgetData.write().catch((err: Error) => {
      console.warn(`[ThemeAccent] refresh widgets failed: ${JSON.stringify(err)}`);
    });
  }

  /** 启动时从 prefs 恢复主题色（含自定义色）。 */
  static async restore(): Promise<void> {
    const stored: number = await AppPreferences.getInt(PrefKeys.ThemeIndex, ThemeAccent.DEFAULT_INDEX);
    if (stored === ThemeAccent.CUSTOM_INDEX) {
      const custom: string = await AppPreferences.getString(PrefKeys.ThemeCustomColor, '');
      if (ThemeAccent.isHex(custom)) {
        ThemeAccent.customHex = custom.toUpperCase();
        AppState.setThemeCustomColor(ThemeAccent.customHex);
        AppState.setThemeAccentIndex(ThemeAccent.CUSTOM_INDEX);
        return;
      }
    }
    const index: number = stored >= 0 && stored < ThemeAccent.PRESETS.length ? stored : ThemeAccent.DEFAULT_INDEX;
    AppState.setThemeAccentIndex(index);
  }
}
