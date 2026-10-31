/**
 * 周次计算与每个课表独立的当前周。
 *
 * 旧版把「某个周一的日期 + 那天的周序号」写进 shared_preferences，之后靠
 * 日期差推算周次。现在每个课表有自己的 `tableWeek_<id>_index/monday`，
 * 同时把当前课表的值镜像到旧全局 key，供桌面小组件等旧读取方使用。
 */
import { AppPreferences } from '../app/AppPreferences';
import { DateUtils } from '../common/DateUtils';

export class TableWeekState {
  week: number = 1;
  monday: string = '';

  constructor(week: number = 1, monday: string = '') {
    this.week = week;
    this.monday = monday;
  }
}

export class WeekUtil {
  /**
   * 从旧版全局周次迁移到每个课表：把所有已有课表初始化为同一个当前周，
   * 之后各课表独立维护。只执行一次。
   */
  static async migrateLegacyToTables(tableIds: number[]): Promise<void> {
    if (await AppPreferences.isTableWeekMigrated()) {
      return;
    }
    const legacyMonday: string = await AppPreferences.getString('lastWeekMonday', '');
    const legacyWeek: number = await AppPreferences.getInt('weekIndex', 1);
    const monday: string = legacyMonday === '' ? DateUtils.currentMondayString() : legacyMonday;
    const week: number = legacyMonday === '' ? 1 : legacyWeek;
    for (let i = 0; i < tableIds.length; i++) {
      const tableId: number = tableIds[i];
      if (tableId <= 0) {
        continue;
      }
      const existingMonday: string = await AppPreferences.getTableWeekMonday(tableId);
      if (existingMonday === '') {
        await AppPreferences.setTableWeek(tableId, week, monday);
      }
    }
    await AppPreferences.markTableWeekMigrated();
  }

  /**
   * 读取并校正某个课表的当前周。
   * 该课表还没有独立周次时：迁移期间沿用旧全局周次，迁移完成后新表从第 1 周开始。
   */
  static async ensureWeekForTable(tableId: number): Promise<TableWeekState> {
    let monday: string = await AppPreferences.getTableWeekMonday(tableId);
    let week: number = await AppPreferences.getTableWeekIndex(tableId);
    if (monday === '' || week < 1) {
      if (await AppPreferences.isTableWeekMigrated()) {
        monday = DateUtils.currentMondayString();
        week = 1;
      } else {
        const legacyMonday: string = await AppPreferences.getString('lastWeekMonday', '');
        const legacyWeek: number = await AppPreferences.getInt('weekIndex', 1);
        monday = legacyMonday === '' ? DateUtils.currentMondayString() : legacyMonday;
        week = legacyMonday === '' ? 1 : legacyWeek;
      }
    }

    const thisMonday: string = DateUtils.currentMondayString();
    const bias: number = WeekUtil.weekBias(monday, thisMonday);
    if (bias !== 0) {
      week += bias;
      monday = thisMonday;
    }
    if (week < 1) {
      week = 1;
    }
    await WeekUtil.writeTableWeek(tableId, week, monday);
    return new TableWeekState(week, monday);
  }

  /** 直接设定当前周（设置页当前周用）。 */
  static async setNowWeek(weekNum: number, tableId: number = 0): Promise<void> {
    const id: number = await WeekUtil.resolveTableId(tableId);
    const monday: string = DateUtils.currentMondayString();
    const week: number = weekNum < 1 ? 1 : weekNum;
    await WeekUtil.writeTableWeek(id, week, monday);
  }

  /** 某天属于第几周（旧版 getWeekNumOfDay）。 */
  static async getWeekNumOfDay(date: Date): Promise<number> {
    const state: TableWeekState = await WeekUtil.activeWeekState();
    if (state.monday === '') {
      return 1;
    }
    const lastMonday: Date = DateUtils.parseIsoDate(state.monday);
    const targetMonday: Date = DateUtils.mondayOf(date);
    const weekBias: number = Math.floor(DateUtils.daysBetween(lastMonday, targetMonday) / 7);
    return state.week + weekBias;
  }

  /** 距离第 1 周还有几周：由 `semester_start_monday` 推算当前周。 */
  static async getWeekFromSemesterStart(monday: string): Promise<number> {
    if (monday === '') {
      return 1;
    }
    const startMonday: Date = DateUtils.parseIsoDate(monday);
    const thisMonday: Date = DateUtils.mondayOf(DateUtils.today());
    const bias: number = Math.floor(DateUtils.daysBetween(startMonday, thisMonday) / 7);
    return bias + 1;
  }

  private static async resolveTableId(tableId: number): Promise<number> {
    if (tableId > 0) {
      return tableId;
    }
    return AppPreferences.getTableId();
  }

  private static async activeWeekState(): Promise<TableWeekState> {
    const tableId: number = await AppPreferences.getTableId();
    let week: number = await AppPreferences.getTableWeekIndex(tableId);
    let monday: string = await AppPreferences.getTableWeekMonday(tableId);
    if (monday === '' || week < 1) {
      monday = await AppPreferences.getString('lastWeekMonday', '');
      week = await AppPreferences.getInt('weekIndex', 1);
      if (monday === '') {
        monday = DateUtils.currentMondayString();
      }
    }
    return new TableWeekState(week < 1 ? 1 : week, monday);
  }

  private static async writeTableWeek(tableId: number, week: number, monday: string): Promise<void> {
    await AppPreferences.setTableWeek(tableId, week, monday);
    await WeekUtil.mirrorGlobal(week, monday);
  }

  private static async mirrorGlobal(week: number, monday: string): Promise<void> {
    await AppPreferences.put('lastWeekMonday', monday);
    await AppPreferences.put('weekIndex', week);
    await AppPreferences.put('tmpWeekIndex', week);
  }

  private static weekBias(lastMondayString: string, thisMondayString: string): number {
    const lastMonday: Date = DateUtils.parseIsoDate(lastMondayString);
    const thisMonday: Date = DateUtils.parseIsoDate(thisMondayString);
    return Math.floor(DateUtils.daysBetween(lastMonday, thisMonday) / 7);
  }
}
