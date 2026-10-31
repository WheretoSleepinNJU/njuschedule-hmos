/**
 * 启动初始化（对应旧版 `lib/Utils/InitUtil.dart`）。
 *
 * 顺序：Context → 偏好 → 数据库建表 → 默认课表兜底 → 周次校正 → 配色池 →
 * 恢复「当前课表 / 当前周」。完成后把 `AppStore.ready` 置 true，
 * 外壳页据此从加载态切到内容态。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from './AppContext';
import { AppPreferences } from './AppPreferences';
import { Appearance } from './Appearance';
import { BackgroundImage } from '../data/BackgroundImage';
import { WidgetData } from '../data/WidgetData';
import { ThemeAccent } from './ThemeAccent';
import { AppState } from './AppState';
import { ColorPool } from '../data/ColorPool';
import { CourseTableRepository } from '../data/CourseTableRepository';
import { Db } from '../data/Db';
import { CourseTable } from '../data/models/Models';
import { WeekUtil } from '../data/WeekUtil';

const DOMAIN: number = 0x0000;

export class AppBootstrap {
  private static started: boolean = false;

  static async run(context: common.UIAbilityContext): Promise<void> {
    if (AppBootstrap.started) {
      return;
    }
    AppBootstrap.started = true;
    try {
      AppContext.init(context);
      await AppPreferences.init();
      await Db.open();
      await CourseTableRepository.ensureDefaultTable();
      await ColorPool.check();
      await AppBootstrap.restoreSelection();
      await ThemeAccent.restore();
      await Appearance.restore(context);
      Appearance.syncIsDark(context);
      AppState.setAutoDarkAccent(await AppPreferences.getAutoDarkAccent());
      await BackgroundImage.restore();
      await WidgetData.write();
      AppState.setReady(true);
      hilog.info(DOMAIN, 'NjuSchedule', 'bootstrap done');
    } catch (err) {
      AppState.setReady(false);
      hilog.error(DOMAIN, 'NjuSchedule', 'bootstrap failed: %{public}s', JSON.stringify(err));
    }
  }

  private static async restoreSelection(): Promise<void> {
    const tables: CourseTable[] = await CourseTableRepository.getAll();
    let tableId: number = await AppPreferences.getTableId();
    let found: boolean = false;
    for (let i = 0; i < tables.length; i++) {
      if (tables[i].id === tableId) {
        found = true;
        break;
      }
    }
    if (!found && tables.length > 0) {
      tableId = tables[0].id;
      await AppPreferences.setTableId(tableId);
    }
    const ids: number[] = [];
    for (let i = 0; i < tables.length; i++) {
      ids.push(tables[i].id);
    }
    await WeekUtil.migrateLegacyToTables(ids);
    const weekState = await WeekUtil.ensureWeekForTable(tableId);
    const store = AppState.store();
    store.tableId = tableId;
    store.weekIndex = weekState.week;
    store.tmpWeekIndex = weekState.week;
    await AppBootstrap.restoreDisplayOptions();
  }

  /** 显示配置：prefs → AppStore（运行时真源）。 */
  private static async restoreDisplayOptions(): Promise<void> {
    AppState.setShowWeekend(await AppPreferences.getShowWeekend());
    AppState.setShowClassTime(await AppPreferences.getShowClassTime());
    AppState.setShowFreeClass(await AppPreferences.getShowFreeClass());
    AppState.store().showMonth = await AppPreferences.getShowMonth();
    AppState.setShowDate(await AppPreferences.getShowDate());
    AppState.store().showNonCurrentWeekCourses = await AppPreferences.getShowNonCurrentWeekCourses();
    AppState.setClassHeight(await AppPreferences.getClassHeight());
    AppState.store().dataRevision = 0;
  }
}
