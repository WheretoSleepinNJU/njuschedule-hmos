/**
 * 用户首选项（旧版 shared_preferences 的 HarmonyOS 对应物）。
 *
 * key 名与旧版 Flutter 项目完全一致，语义、默认值也保持一致（来源见每个字段注释），
 * 这样「其余部分沿用旧项目」在存储层是可核对的。HarmonyOS 侧无历史数据，
 * 打开时不会与旧版共享文件，但键名规范必须一致。
 */
import { preferences } from '@kit.ArkData';
import { AppContext } from './AppContext';

/** 旧版 prefs key 常量（拼写保留旧版，不要"修正"）。 */
export class PrefKeys {
  // 主题（lib/Utils/States/ThemeState.dart）
  static readonly ThemeIndex: string = 'themeIndex';
  static readonly ThemeModeIndex: string = 'themeModeIndex';
  static readonly ThemeCustomColor: string = 'themeCustomColor';
  /** 深色模式下自动提亮主题色（本项目新增，旧版无此 key）。 */
  static readonly AutoDarkAccent: string = 'autoDarkAccent';

  // 当前课表 / 周次（ClassTableState / WeekState / WeekUtil）
  static readonly TableId: string = 'tableId';
  static readonly WeekIndex: string = 'weekIndex';
  static readonly TmpWeekIndex: string = 'tmpWeekIndex';
  static readonly LastWeekMonday: string = 'lastWeekMonday';
  /** 一次性迁移标记：旧版全局周次已复制到各课表。 */
  static readonly TableWeekMigrated: string = 'tableWeekMigrated';

  // 课表显示配置（ConfigState）
  static readonly ShowWeekend: string = 'showWeekend';
  static readonly ShowClassTime: string = 'showClassTime';
  static readonly ShowFreeClass: string = 'showFreeClass';
  static readonly ShowMonth: string = 'showMonth';
  static readonly ClassHeight: string = 'classHeight';
  static readonly ShowDate: string = 'showDate';
  static readonly BgImgPath: string = 'bgImgPath';
  static readonly ShowNonCurrentWeekCourses: string = 'showNonCurrentWeekCourses';

  // 小组件 / 实况窗（暂缓实现，先保留 key 定义）
  static readonly WidgetApproachingMinutes: string = 'widgetApproachingMinutes';
  static readonly WidgetTomorrowPreviewHour: string = 'widgetTomorrowPreviewHour';
  static readonly LiveActivityEnabled: string = 'liveActivityEnabled';
  static readonly LiveActivityTextLeft: string = 'liveActivityTextLeft';
  static readonly LiveActivityTextRight: string = 'liveActivityTextRight';

  // 课程配色池（lib/Utils/ColorUtil.dart）
  static readonly ColorPool: string = 'colorPool';
  /** 重置配色时生成的随机种子，用于打散课程颜色的取模映射。 */
  static readonly ColorPoolSeed: string = 'colorPoolSeed';
  /** 当前选中的课程配色池 id。 */
  static readonly ColorPalette: string = 'colorPalette';

  // 启动次数 / 评价（InitUtil）
}

export class AppPreferences {
  private static store: preferences.Preferences | null = null;

  static async init(): Promise<void> {
    if (AppPreferences.store !== null) {
      return;
    }
    const options: preferences.Options = { name: 'nju_schedule_next' };
    AppPreferences.store = await preferences.getPreferences(AppContext.get(), options);
  }

  private static require(): preferences.Preferences {
    const store: preferences.Preferences | null = AppPreferences.store;
    if (store === null) {
      throw new Error('AppPreferences 未初始化：先 await AppPreferences.init()');
    }
    return store;
  }

  static async getBool(key: string, defaultValue: boolean): Promise<boolean> {
    const value: preferences.ValueType = await AppPreferences.require().get(key, defaultValue);
    return typeof value === 'boolean' ? value : defaultValue;
  }

  static async getInt(key: string, defaultValue: number): Promise<number> {
    const value: preferences.ValueType = await AppPreferences.require().get(key, defaultValue);
    return typeof value === 'number' ? value : defaultValue;
  }

  static async getString(key: string, defaultValue: string): Promise<string> {
    const value: preferences.ValueType = await AppPreferences.require().get(key, defaultValue);
    return typeof value === 'string' ? value : defaultValue;
  }

  static async put(key: string, value: preferences.ValueType): Promise<void> {
    const store: preferences.Preferences = AppPreferences.require();
    await store.put(key, value);
    await store.flush();
  }

  // ---- 常用读写（默认值与旧版一致） ----

  static async getTableId(): Promise<number> {
    return AppPreferences.getInt(PrefKeys.TableId, 0);
  }

  static async setTableId(tableId: number): Promise<void> {
    await AppPreferences.put(PrefKeys.TableId, tableId);
  }

  static async setTmpWeekIndex(week: number): Promise<void> {
    await AppPreferences.put(PrefKeys.TmpWeekIndex, week);
  }

  // ---- 每个课表独立的当前周 ----

  private static tableWeekKey(tableId: number, suffix: string): string {
    return `tableWeek_${tableId}_${suffix}`;
  }

  static async getTableWeekIndex(tableId: number): Promise<number> {
    return AppPreferences.getInt(AppPreferences.tableWeekKey(tableId, 'index'), -1);
  }

  static async getTableWeekMonday(tableId: number): Promise<string> {
    return AppPreferences.getString(AppPreferences.tableWeekKey(tableId, 'monday'), '');
  }

  static async setTableWeek(tableId: number, week: number, monday: string): Promise<void> {
    await AppPreferences.put(AppPreferences.tableWeekKey(tableId, 'index'), week);
    await AppPreferences.put(AppPreferences.tableWeekKey(tableId, 'monday'), monday);
  }

  static async isTableWeekMigrated(): Promise<boolean> {
    return AppPreferences.getBool(PrefKeys.TableWeekMigrated, false);
  }

  static async markTableWeekMigrated(): Promise<void> {
    await AppPreferences.put(PrefKeys.TableWeekMigrated, true);
  }

  static async getClassHeight(): Promise<number> {
    return AppPreferences.getInt(PrefKeys.ClassHeight, 50);
  }

  static async setClassHeight(height: number): Promise<void> {
    await AppPreferences.put(PrefKeys.ClassHeight, height);
  }

  static async getAutoDarkAccent(): Promise<boolean> {
    return AppPreferences.getBool(PrefKeys.AutoDarkAccent, true);
  }

  static async setAutoDarkAccent(value: boolean): Promise<void> {
    await AppPreferences.put(PrefKeys.AutoDarkAccent, value);
  }

  static async getShowWeekend(): Promise<boolean> {
    return AppPreferences.getBool(PrefKeys.ShowWeekend, false);
  }

  static async getShowClassTime(): Promise<boolean> {
    return AppPreferences.getBool(PrefKeys.ShowClassTime, true);
  }

  static async getShowFreeClass(): Promise<boolean> {
    return AppPreferences.getBool(PrefKeys.ShowFreeClass, true);
  }

  static async getShowMonth(): Promise<boolean> {
    return AppPreferences.getBool(PrefKeys.ShowMonth, true);
  }

  static async getShowDate(): Promise<boolean> {
    return AppPreferences.getBool(PrefKeys.ShowDate, true);
  }

  static async getShowNonCurrentWeekCourses(): Promise<boolean> {
    return AppPreferences.getBool(PrefKeys.ShowNonCurrentWeekCourses, true);
  }

  static async getColorPoolRaw(): Promise<string> {
    return AppPreferences.getString(PrefKeys.ColorPool, '');
  }

  static async setColorPoolRaw(value: string): Promise<void> {
    await AppPreferences.put(PrefKeys.ColorPool, value);
  }

  static async getColorPoolSeed(): Promise<number> {
    const raw: string = await AppPreferences.getString(PrefKeys.ColorPoolSeed, '0');
    const parsed: number = parseInt(raw, 10);
    return isNaN(parsed) ? 0 : parsed;
  }

  static async setColorPoolSeed(value: number): Promise<void> {
    await AppPreferences.put(PrefKeys.ColorPoolSeed, `${value}`);
  }

  static async getColorPalette(): Promise<string> {
    return AppPreferences.getString(PrefKeys.ColorPalette, 'default');
  }

  static async setColorPalette(value: string): Promise<void> {
    await AppPreferences.put(PrefKeys.ColorPalette, value);
  }
}
