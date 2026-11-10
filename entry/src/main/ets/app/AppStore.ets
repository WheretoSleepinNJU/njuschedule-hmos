/**
 * 状态管理 V2 全局 Store。
 *
 * - `@ObservedV2` + `@Trace`：所有全局状态字段可被 V2 组件深度观测；
 * - `AppStorageV2.connect`：跨页面 / 跨 Ability 共享同一实例；
 * - 写入口统一走 `AppState.setXxx`（本 Store 为唯一运行时真源，prefs 只做持久化）；
 * - 迁移过程与例外见 `docs/porting/state-v2-migration.md`。
 */
import { AppStorageV2 } from '@kit.ArkUI';
import { ColorMath } from '../common/design/ColorMath';
import { TimetableMetrics } from '../common/design/Tokens';

/** 全局 Store 在 AppStorageV2 中的 key。 */
export const APP_STORE_KEY: string = 'appStore';

@ObservedV2
export class AppStore {
  // ---- 窗口 / 沉浸式 ----
  @Trace breakpoint: string = 'sm';
  @Trace windowWidth: number = 0;
  @Trace windowHeight: number = 0;
  @Trace windowTopInset: number = 0;
  @Trace windowBottomInset: number = 0;

  // ---- 外壳 / 导航 ----
  @Trace weekPickerOpen: boolean = false;
  @Trace ready: boolean = false;

  // ---- 课表选择 ----
  @Trace tableId: number = 0;
  @Trace weekIndex: number = 1;
  @Trace tmpWeekIndex: number = 1;
  @Trace dataRevision: number = 0;

  // ---- 外观 ----
  @Trace colorMode: number = 0;
  /** 当前生效的深色状态（决定课程块/主题色等所有深浅色分支）。 */
  @Trace isDark: boolean = false;
  /** 系统（跟随系统）的深色状态；与 App 内强制深浅色解耦。 */
  @Trace systemIsDark: boolean = false;
  @Trace systemIsDarkKnown: boolean = false;
  @Trace themeAccentIndex: number = 0;
  @Trace themeModeIndex: number = 0;
  /** 自定义主题色（themeAccentIndex = 9 时使用）。 */
  @Trace themeCustomColor: string = '';
  /** 深色模式下是否自动提亮主题色（自定义外观里的选项，默认开启）。 */
  @Trace autoDarkAccent: boolean = true;
  /** 当前生效的强调色（浅色=预设色；深色开启自动提亮时=提亮后的变体）。 */
  @Trace accentDisplay: string = ColorMath.PRESETS[0];
  /** 强调色上的文字/图标颜色。 */
  @Trace accentOn: string = '#FFFFFF';
  /** 强调色的 12% 透明叠加色（徽标/选中底）。 */
  @Trace accentSoft: string = '#26' + ColorMath.PRESETS[0].substring(1);
  @Trace backgroundImagePath: string = '';

  // ---- 课表显示配置 ----
  @Trace showWeekend: boolean = false;
  @Trace showClassTime: boolean = true;
  @Trace showFreeClass: boolean = true;
  @Trace showMonth: boolean = false;
  @Trace showDate: boolean = true;
  @Trace showNonCurrentWeekCourses: boolean = true;
  @Trace classHeight: number = TimetableMetrics.DefaultClassHeight;

  /** 重新计算当前生效的强调色（主题色 / 自定义色 / 深浅色 / 自动提亮开关变化时调用）。 */
  recomputeAccent(): void {
    let base: string = ColorMath.preset(this.themeAccentIndex);
    if (this.themeAccentIndex === ColorMath.CUSTOM_INDEX && ColorMath.isValidHex(this.themeCustomColor)) {
      base = this.themeCustomColor;
    }
    const derivedForDark: boolean = this.isDark && this.autoDarkAccent;
    const display: string = derivedForDark ? ColorMath.deriveDarkAccent(base) : base;
    const on: string = ColorMath.onAccent(display, derivedForDark);
    const soft: string = `#26${display.substring(1)}`;
    if (this.accentDisplay === display && this.accentOn === on && this.accentSoft === soft) {
      return;
    }
    this.accentDisplay = display;
    this.accentOn = on;
    this.accentSoft = soft;
  }

  /** 取全局 Store（首次调用创建；跨 Ability 共享同一实例）。 */
  static connect(): AppStore {
    const store: AppStore | undefined = AppStorageV2.connect<AppStore>(AppStore, APP_STORE_KEY,
      () => new AppStore());
    return store === undefined ? new AppStore() : store;
  }
}
