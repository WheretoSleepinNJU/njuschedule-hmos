/**
 * 全局状态写入口（状态管理 V2）。
 *
 * 约定：**显示类配置以 `AppStore` 为运行时真源，preferences 只做持久化**。
 * 启动时 `AppBootstrap` 用 prefs 初始化 AppStore；页面改动统一调用本类 setter，
 * 课表/课程/设置页通过 `@Local store` 读取，V2 的 @ObservedV2/@Trace 自动通知刷新。
 * 迁移过程与映射见 `docs/porting/state-v2-migration.md`。
 */
import { WidgetData } from '../data/WidgetData';
import { AppStore } from './AppStore';
import { AppPreferences } from './AppPreferences';
import { WeekUtil, TableWeekState } from '../data/WeekUtil';

export class AppState {
  /** V2 全局 Store。 */
  static store(): AppStore {
    return AppStore.connect();
  }

  static setThemeAccentIndex(index: number): void {
    const store: AppStore = AppState.store();
    if (store.themeAccentIndex === index) {
      return;
    }
    store.themeAccentIndex = index;
    store.recomputeAccent();
  }

  static setThemeCustomColor(hex: string): void {
    const store: AppStore = AppState.store();
    store.themeCustomColor = hex;
    store.recomputeAccent();
  }

  static setAutoDarkAccent(value: boolean): void {
    const store: AppStore = AppState.store();
    if (store.autoDarkAccent === value) {
      return;
    }
    store.autoDarkAccent = value;
    store.recomputeAccent();
  }

  static setThemeModeIndex(index: number): void {
    AppState.store().themeModeIndex = index;
  }

  static setIsDark(dark: boolean): void {
    const store: AppStore = AppState.store();
    if (store.isDark === dark) {
      return;
    }
    store.isDark = dark;
    store.recomputeAccent();
  }

  /**
   * 记录「系统」的深浅色（来自 EntryAbility 的 config）。与 App 内强制深浅色解耦：
   * 只有外观模式为「跟随系统」时才同时更新生效的 isDark，强制深色/浅色时不能覆盖。
   */
  static setSystemIsDark(dark: boolean): void {
    const store: AppStore = AppState.store();
    store.systemIsDark = dark;
    store.systemIsDarkKnown = true;
    if (store.themeModeIndex === 0) {
      store.isDark = dark;
      store.recomputeAccent();
    }
  }

  /** 记录真正的系统深浅色（来自 ApplicationContext.onSystemConfigurationUpdated）。 */
  static noteSystemColorMode(dark: boolean): void {
    const store: AppStore = AppState.store();
    store.systemIsDark = dark;
    store.systemIsDarkKnown = true;
    if (store.themeModeIndex === 0 && store.isDark !== dark) {
      store.isDark = dark;
      store.recomputeAccent();
      // 跟随系统时，系统深浅色变化也要刷新桌面卡片（强调色在深色下会提亮）。
      WidgetData.write();
    }
  }

  static setBackgroundImagePath(path: string): void {
    AppState.store().backgroundImagePath = path;
  }

  static setShowWeekend(value: boolean): void {
    AppState.store().showWeekend = value;
  }

  static setShowClassTime(value: boolean): void {
    AppState.store().showClassTime = value;
  }

  static setShowFreeClass(value: boolean): void {
    AppState.store().showFreeClass = value;
  }

  static setShowDate(value: boolean): void {
    AppState.store().showDate = value;
  }

  static setClassHeight(value: number): void {
    AppState.store().classHeight = value;
  }

  static setWindowInsets(topPx: number, bottomPx: number): void {
    const store: AppStore = AppState.store();
    store.windowTopInset = topPx;
    store.windowBottomInset = bottomPx;
  }

  static setWindowSize(widthPx: number, heightPx: number): void {
    const store: AppStore = AppState.store();
    store.windowWidth = widthPx;
    store.windowHeight = heightPx;
  }

  static setBreakpoint(value: string): void {
    AppState.store().breakpoint = value;
  }

  static setReady(ready: boolean): void {
    AppState.store().ready = ready;
  }

  static setCurrentTable(tableId: number): void {
    AppState.store().tableId = tableId;
  }

  /** 切换当前课表（唯一写入口）：持久化 + 写 Store + 通知课表页/小组件重载。 */
  static async switchTable(tableId: number): Promise<void> {
    if (tableId <= 0) {
      return;
    }
    await AppPreferences.setTableId(tableId);
    const weekState: TableWeekState = await WeekUtil.ensureWeekForTable(tableId);
    const store: AppStore = AppState.store();
    store.weekIndex = weekState.week;
    store.tmpWeekIndex = weekState.week;
    AppState.setCurrentTable(tableId);
    await AppState.bumpDataRevision();
  }

  /** 当前课表 id；Store 未就绪时用调用方兜底值，仍无效则回落到 1。 */
  static effectiveTableId(fallback: number = 0): number {
    const current: number = AppState.store().tableId;
    if (current > 0) {
      return current;
    }
    return fallback > 0 ? fallback : 1;
  }

  static currentTableId(): number {
    return AppState.store().tableId;
  }

  static async setCurrentWeek(week: number): Promise<void> {
    const store: AppStore = AppState.store();
    store.weekIndex = week;
    store.tmpWeekIndex = week;
    // 等小组件即时推送完成后再返回，避免改完周数立刻退出时错过刷新。
    await WidgetData.write();
  }

  static setWeekPickerOpen(open: boolean): void {
    AppState.store().weekPickerOpen = open;
  }

  static setTabBarHidden(hidden: boolean): void {
    AppState.store().tabBarHidden = hidden;
  }

  static setDisplayWeek(week: number): void {
    AppState.store().tmpWeekIndex = week;
  }

  /** 课程/课表/外观变化后调用：先递增 revision 通知 UI，再排队刷新小组件。 */
  static async bumpDataRevision(): Promise<void> {
    const current: number = AppState.store().dataRevision;
    AppState.store().dataRevision = current + 1;
    await WidgetData.write();
  }

  static dataRevision(): number {
    return AppState.store().dataRevision;
  }
}
