/**
 * 卡片数据计算（FormExtensionAbility 进程内使用）。
 *
 * 旧版小组件的核心缺陷是「数据依赖主应用推送的快照」：App 很久没打开、跨天、
 * 切周之后卡片就停在旧数据。这里改为**卡片侧自己算**：
 * - 直接读本模块的 preferences（tableId / weekIndex / lastWeekMonday / colorPool）
 * - 直接读 course.db（与主应用同一份 RDB，同一模块目录）
 * - 周次按 lastWeekMonday 现场折算，跨周/跨天都能正确
 * 主应用数据变化时由 WidgetData 直接计算并 updateForm；FormExtension 负责生命周期与边界触发。
 */
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences, relationalStore } from '@kit.ArkData';
import { ColorMath } from '../common/design/ColorMath';
import { LegacyConstant } from '../common/Constants';
import { Course } from '../data/models/Models';
import { CourseColorPalettes } from '../data/CourseColorPalettes';
import { ScheduleModel } from '../data/ScheduleModel';
import { WidgetPreferences } from './WidgetPreferences';

export class WidgetCardCourse {
  name: string = '';
  place: string = '';
  teacher: string = '';
  time: string = '';
  startTime: string = '';
  endTime: string = '';
  period: string = '';
  color: string = '';
  /** done / now / next / normal */
  state: string = 'normal';
}

/** 4x4 周视图卡片里的一节课。 */
export class WidgetWeekCourse {
  name: string = '';
  place: string = '';
  teacher: string = '';
  /** 1=周一 ... 7=周日 */
  day: number = 1;
  start: number = 1;
  count: number = 1;
  period: string = '';
  color: string = '';
  /** 本周已上完 */
  done: boolean = false;
}

/** 4x4 卡片时间轴的一节作息。 */
export class WidgetPeriod {
  start: string = '';
  end: string = '';

  constructor(start: string, end: string) {
    this.start = start;
    this.end = end;
  }
}

export class WidgetCardPayload {
  /** 今天（卡片头部日期/周次）。 */
  date: string = '';
  weekday: string = '';
  weekLabel: string = '';
  /** 今天的课程列表（只含尚未结束的课，用于 2x2/2x4 的「今天」区块）。 */
  courses: WidgetCardCourse[] = [];
  /** 今天是否排了课（不论是否已上完）。 */
  todayHasCourses: boolean = false;
  /** 今天有课但已全部上完。 */
  todayDone: boolean = false;
  /** 今天课程总数（已上完的也算，用于徽标）。 */
  todayTotal: number = 0;
  /** 4x4 周视图用：当前周周一~周五的课程。 */
  week: WidgetWeekCourse[] = [];
  /** 4x4 标题左侧显示的课表名称。 */
  tableName: string = '';
  /** 4x4 周视图时间轴。 */
  periods: WidgetPeriod[] = [];
  /** 4x4 周视图日期（M/D）；开启周末时包含周六、周日。 */
  weekDates: string[] = [];
  /** 4x4 是否显示周末（与主课表「显示周末」设置一致）。 */
  showWeekend: boolean = false;
  /** 周一到周日每天实际课程数（用于「+N」）。 */
  weekTotals: number[] = [];
  /** 今天之后第一个有课的日期（供 2x2/2x4「接下来」区块，与今天并存、可滚动查看）。 */
  nextDate: string = '';
  nextWeekday: string = '';
  nextWeekLabel: string = '';
  nextCourses: WidgetCardCourse[] = [];
  nextFound: boolean = false;
  /** 外观模式：auto（跟随系统）/ light / dark —— 卡片按此强制深浅色，避免只跟随系统而忽略 App 内设置。 */
  mode: string = 'auto';
  /** 当前主题强调色（#RRGGBB），用于「今天」日期高亮与徽标。 */
  accent: string = '#0095F9';
  updatedAt: string = '';
}

/** 与主应用 ColorPool 完全一致的课程取色上下文（色池、配色池预设、随机种子）。 */
class WidgetCourseColors {
  private readonly palette: string[];
  private readonly pool: number[];
  private readonly seed: number;

  constructor(palette: string[], pool: number[], seed: number) {
    this.palette = palette;
    this.pool = pool;
    this.seed = seed;
  }

  resolve(course: Course): string {
    const raw: string = course.color.trim();
    if (raw !== '') {
      const normalized: string = raw.startsWith('#') ? raw.substring(1) : raw;
      if (new RegExp('^[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$').test(normalized)) {
        return raw.startsWith('#') ? raw : `#${raw}`;
      }
    }
    if (course.courseId < 0 || this.pool.length === 0 || this.palette.length === 0) {
      return this.palette.length > 0 ? this.palette[0] : '#8AD297';
    }
    let poolIndex: number = 0;
    if (this.seed === 0) {
      poolIndex = this.pool[course.courseId % this.pool.length];
    } else {
      let mixed: number = Math.imul(course.courseId + 1, 2654435761) + this.seed;
      mixed = mixed ^ (mixed >>> 15);
      poolIndex = this.pool[(mixed >>> 0) % this.pool.length];
    }
    return this.palette[poolIndex >= 0 && poolIndex < this.palette.length ? poolIndex : 0];
  }
}

const TABLE_COURSE: string = 'Course';
const TABLE_TABLES: string = 'CourseTable';

export class WidgetDataProvider {
  static async buildJson(context: common.Context): Promise<string> {
    try {
      const store: preferences.Preferences = await WidgetPreferences.fresh(context);
      const payload: WidgetCardPayload = await WidgetDataProvider.compute(context, store);
      return JSON.stringify(payload);
    } catch (err) {
      console.warn(`[WidgetDataProvider] compute failed: ${JSON.stringify(err)}`);
      return '';
    }
  }

  private static async compute(context: common.Context, store: preferences.Preferences): Promise<WidgetCardPayload> {
    const now: Date = new Date();
    const payload: WidgetCardPayload = new WidgetCardPayload();
    payload.date = `${now.getMonth() + 1}/${now.getDate()}`;
    payload.weekday = LegacyConstant.WEEK_WITH_BIAS[WidgetDataProvider.weekday(now)];
    payload.updatedAt = now.toISOString();

    const tableId: number = WidgetDataProvider.toInt(await store.get('tableId', 1), 1);
    payload.tableName = await WidgetDataProvider.readTableName(context, tableId);
    const weekIndex: number = WidgetDataProvider.toInt(await store.get('weekIndex', 1), 1);
    const lastMonday: string = WidgetDataProvider.toStr(await store.get('lastWeekMonday', ''));
    const currentWeek: number = WidgetDataProvider.resolveWeek(weekIndex, lastMonday, now);
    payload.weekLabel = `第 ${currentWeek} 周`;

    const courses: Course[] = await WidgetDataProvider.readCourses(context, tableId);
    const periods: ClassPeriodLike[] = await WidgetDataProvider.readPeriods(context, tableId);
    const colors: WidgetCourseColors = await WidgetDataProvider.readCourseColors(store);
    payload.periods = WidgetDataProvider.buildPeriods(periods);
    const showWeekendRaw: preferences.ValueType = await store.get('showWeekend', false);
    payload.showWeekend = typeof showWeekendRaw === 'boolean' ? showWeekendRaw : false;
    payload.weekDates = WidgetDataProvider.buildWeekDates(now, payload.showWeekend);

    const schedule: ScheduleModel = new ScheduleModel(courses, currentWeek);
    schedule.init();
    const today: number = WidgetDataProvider.weekday(now);
    const nowMinutes: number = now.getHours() * 60 + now.getMinutes();

    // 头部固定显示今天。
    payload.date = `${now.getMonth() + 1}/${now.getDate()}`;
    payload.weekday = LegacyConstant.WEEK_WITH_BIAS[today];

    // 「今天」区块：今天还没上完的课；今天有课但全上完时由 UI 显示已结束状态。
    payload.courses = WidgetDataProvider.buildDayList(schedule, today, currentWeek, periods, colors, nowMinutes, true);
    payload.todayTotal = WidgetDataProvider.countDayCourses(schedule, today, currentWeek);
    payload.todayHasCourses = payload.todayTotal > 0;
    payload.todayDone = payload.todayHasCourses && payload.courses.length === 0;

    // 「接下来」区块：与系统日历卡片一致，往后搜寻第一个有课的日期，与「今天」并存并支持滚动查看。
    WidgetDataProvider.fillNextCourseDay(payload, courses, periods, colors, currentWeek, today, now);

    // 4x4 周视图数据。
    payload.week = WidgetDataProvider.buildWeek(schedule, currentWeek, today, nowMinutes, colors,
      payload.showWeekend);
    payload.weekTotals = WidgetDataProvider.buildWeekTotals(schedule, currentWeek);

    // 外观与主题色：与主应用设置保持一致（卡片渲染进程无法读 AppStorage，只能通过 payload 下发）。
    payload.mode = WidgetDataProvider.readAppearanceMode(
      WidgetDataProvider.toInt(await store.get('themeModeIndex', 0), 0),
      WidgetDataProvider.contextIsDark(context));
    payload.accent = WidgetDataProvider.readAccent(
      WidgetDataProvider.toInt(await store.get('themeIndex', 0), 0),
      WidgetDataProvider.toStr(await store.get('themeCustomColor', '')));
    // 深色模式下按「自动提亮主题色」开关给出提亮后的强调色（与 App 内一致）
    if (payload.mode === 'dark' && WidgetDataProvider.readAutoDarkAccent(await store.get('autoDarkAccent', true))) {
      payload.accent = ColorMath.deriveDarkAccent(payload.accent);
    }
    return payload;
  }

  /**
   * 某一天的课程列表：已上完的课不返回（系统日历卡片语义）；
   * isToday=true 时计算 now/next 状态用于「进行中/下一节」徽标。
   */
  private static buildDayList(schedule: ScheduleModel, day: number, currentWeek: number, periods: ClassPeriodLike[],
    colors: WidgetCourseColors, nowMinutes: number, isToday: boolean): WidgetCardCourse[] {
    const dayCourses: Course[] = [];
    for (let i = 0; i < schedule.activeCourses.length; i++) {
      if (schedule.activeCourses[i].weekTime === day) {
        dayCourses.push(schedule.activeCourses[i]);
      }
    }
    // 时间冲突的课程在 ScheduleModel 里归到 multiCourses（首项代表该时段）。
    for (let i = 0; i < schedule.multiCourses.length; i++) {
      const group: Course[] = schedule.multiCourses[i];
      if (group.length > 0 && group[0].weekTime === day && group[0].weeks.indexOf(currentWeek) >= 0) {
        dayCourses.push(group[0]);
      }
    }
    dayCourses.sort((a: Course, b: Course) => a.startTime - b.startTime);

    const list: WidgetCardCourse[] = [];
    let nextMarked: boolean = false;
    for (let i = 0; i < dayCourses.length; i++) {
      const course: Course = dayCourses[i];
      const item: WidgetCardCourse = new WidgetCardCourse();
      item.name = course.name;
      item.place = course.classroom;
      item.teacher = course.teacher;
      item.color = colors.resolve(course);
      item.period = course.timeCount > 0 ?
        `第${course.startTime}-${course.startTime + course.timeCount}节` : `第${course.startTime}节`;

      const startIndex: number = Math.max(course.startTime - 1, 0);
      const endIndex: number = Math.min(startIndex + course.timeCount, Math.max(periods.length - 1, 0));
      if (periods.length > 0) {
        item.startTime = periods[Math.min(startIndex, periods.length - 1)].start;
        item.endTime = periods[endIndex].end;
        item.time = `${item.startTime}-${item.endTime}`;
      }

      const startMinutes: number = WidgetDataProvider.toMinutes(item.startTime);
      const endMinutes: number = WidgetDataProvider.toMinutes(item.endTime);
      if (!isToday) {
        item.state = 'normal';
      } else if (startMinutes >= 0 && endMinutes >= 0 && nowMinutes >= startMinutes && nowMinutes < endMinutes) {
        item.state = 'now';
      } else if (endMinutes >= 0 && nowMinutes >= endMinutes) {
        // 已上完：不再展示
        continue;
      } else if (!nextMarked && startMinutes >= 0 && nowMinutes < startMinutes) {
        item.state = 'next';
        nextMarked = true;
      } else {
        item.state = 'normal';
      }
      list.push(item);
    }
    return list;
  }

  /** 统计某天课程数（含冲突课程代表项，按课表周次过滤）。 */
  private static countDayCourses(schedule: ScheduleModel, day: number, currentWeek: number): number {
    let count: number = 0;
    for (let i = 0; i < schedule.activeCourses.length; i++) {
      if (schedule.activeCourses[i].weekTime === day) {
        count += 1;
      }
    }
    for (let i = 0; i < schedule.multiCourses.length; i++) {
      const group: Course[] = schedule.multiCourses[i];
      if (group.length > 0 && group[0].weekTime === day && group[0].weeks.indexOf(currentWeek) >= 0) {
        count += 1;
      }
    }
    return count;
  }

  /** 从明天起最多向后找 7 天，填「下一个有课的日期」区块。 */
  private static fillNextCourseDay(payload: WidgetCardPayload, courses: Course[], periods: ClassPeriodLike[],
    colors: WidgetCourseColors, currentWeek: number, today: number, now: Date): void {
    for (let offset = 1; offset <= 7; offset++) {
      const targetDate: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset);
      const targetWeek: number = currentWeek + Math.floor((offset + (today - 1)) / 7);
      if (targetWeek < 1 || targetWeek > 25) {
        continue;
      }
      const targetDay: number = WidgetDataProvider.weekday(targetDate);
      const targetSchedule: ScheduleModel = new ScheduleModel(courses, targetWeek);
      targetSchedule.init();
      const list: WidgetCardCourse[] = WidgetDataProvider.buildDayList(targetSchedule, targetDay, targetWeek,
        periods, colors, 0, false);
      if (list.length > 0) {
        payload.nextDate = `${targetDate.getMonth() + 1}/${targetDate.getDate()}`;
        payload.nextWeekday = LegacyConstant.WEEK_WITH_BIAS[targetDay];
        payload.nextWeekLabel = `第 ${targetWeek} 周`;
        payload.nextCourses = list;
        payload.nextFound = true;
        return;
      }
    }
    payload.nextFound = false;
  }

  /** 4x4 卡片：本周工作日；开启周末时包含周六、周日。 */
  private static buildWeek(schedule: ScheduleModel, currentWeek: number, today: number, nowMinutes: number,
    colors: WidgetCourseColors, showWeekend: boolean): WidgetWeekCourse[] {
    const result: WidgetWeekCourse[] = [];
    const byDay: Course[][] = [];
    for (let d = 1; d <= 7; d++) {
      byDay.push([]);
    }
    const flat: Course[] = [];
    for (let i = 0; i < schedule.activeCourses.length; i++) {
      flat.push(schedule.activeCourses[i]);
    }
    // 时间冲突的课程在 ScheduleModel 里被归到 multiCourses（首项代表该时段），
    // 周视图卡片同样要展示它们，否则周四的两门冲突课会消失。
    for (let i = 0; i < schedule.multiCourses.length; i++) {
      const group: Course[] = schedule.multiCourses[i];
      if (group.length > 0 && group[0].weeks.indexOf(currentWeek) >= 0) {
        flat.push(group[0]);
      }
    }
    for (let i = 0; i < flat.length; i++) {
      const course: Course = flat[i];
      if (course.weekTime < 1 || course.weekTime > 7) {
        continue;
      }
      byDay[course.weekTime - 1].push(course);
    }
    const dayEnd: number = showWeekend ? 7 : 5;
    for (let d = 1; d <= dayEnd; d++) {
      const dayCourses: Course[] = byDay[d - 1];
      for (let k = 0; k < dayCourses.length; k++) {
        const course: Course = dayCourses[k];
        const item: WidgetWeekCourse = new WidgetWeekCourse();
        item.name = course.name;
        item.place = course.classroom;
        item.teacher = course.teacher;
        item.day = d;
        item.start = course.startTime;
        item.count = course.timeCount + 1;
        item.period = course.timeCount > 0 ?
          `${course.startTime}-${course.startTime + course.timeCount}节` : `${course.startTime}节`;
        item.color = colors.resolve(course);
        item.done = d < today;
        result.push(item);
      }
    }
    return result;
  }

  private static buildPeriods(periods: ClassPeriodLike[]): WidgetPeriod[] {
    const result: WidgetPeriod[] = [];
    for (let i = 0; i < periods.length; i++) {
      result.push(new WidgetPeriod(periods[i].start, periods[i].end));
    }
    return result;
  }

  /** 当前周日期，格式 M/D；按需包含周末。 */
  private static buildWeekDates(now: Date, showWeekend: boolean): string[] {
    const monday: Date = WidgetDataProvider.mondayOf(now);
    const dates: string[] = [];
    const dayCount: number = showWeekend ? 7 : 5;
    for (let i = 0; i < dayCount; i++) {
      const day: Date = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i);
      dates.push(`${day.getMonth() + 1}/${day.getDate()}`);
    }
    return dates;
  }

  /** 周一到周日每天的课程数。 */
  private static buildWeekTotals(schedule: ScheduleModel, currentWeek: number): number[] {
    const totals: number[] = [0, 0, 0, 0, 0, 0, 0];
    const count = (course: Course): void => {
      if (course.weekTime >= 1 && course.weekTime <= 7) {
        totals[course.weekTime - 1] += 1;
      }
    };
    for (let i = 0; i < schedule.activeCourses.length; i++) {
      count(schedule.activeCourses[i]);
    }
    for (let i = 0; i < schedule.multiCourses.length; i++) {
      const group: Course[] = schedule.multiCourses[i];
      if (group.length > 0 && group[0].weeks.indexOf(currentWeek) >= 0) {
        count(group[0]);
      }
    }
    return totals;
  }

  // ---- 读取 ----

  private static async readCourses(context: common.Context, tableId: number): Promise<Course[]> {
    const rdb: relationalStore.RdbStore = await WidgetDataProvider.openRdb(context);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_COURSE);
    predicates.equalTo('tableid', tableId);
    const resultSet: relationalStore.ResultSet = await rdb.query(predicates);
    const courses: Course[] = [];
    try {
      while (resultSet.goToNextRow()) {
        const course: Course = new Course();
        course.tableId = tableId;
        course.name = WidgetDataProvider.colStr(resultSet, 'name');
        course.classroom = WidgetDataProvider.colStr(resultSet, 'classroom');
        course.teacher = WidgetDataProvider.colStr(resultSet, 'teacher');
        course.weeks = WidgetDataProvider.parseIntArray(WidgetDataProvider.colStr(resultSet, 'weeks'));
        course.weekTime = WidgetDataProvider.colNum(resultSet, 'week_time');
        course.startTime = WidgetDataProvider.colNum(resultSet, 'start_time');
        course.timeCount = WidgetDataProvider.colNum(resultSet, 'time_count');
        course.importType = WidgetDataProvider.colNum(resultSet, 'import_type');
        course.courseId = WidgetDataProvider.colNum(resultSet, 'course_id');
        course.color = WidgetDataProvider.colStr(resultSet, 'color');
        courses.push(course);
      }
    } finally {
      resultSet.close();
    }
    return courses;
  }

  private static async readTableName(context: common.Context, tableId: number): Promise<string> {
    try {
      const rdb: relationalStore.RdbStore = await WidgetDataProvider.openRdb(context);
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_TABLES);
      predicates.equalTo('id', tableId);
      const resultSet: relationalStore.ResultSet = await rdb.query(predicates, ['name']);
      try {
        if (resultSet.goToNextRow()) {
          const name: string = WidgetDataProvider.colStr(resultSet, 'name').trim();
          return name === '' ? '我的课表' : name;
        }
      } finally {
        resultSet.close();
      }
    } catch (err) {
      console.warn(`[WidgetDataProvider] readTableName failed: ${JSON.stringify(err)}`);
    }
    return '我的课表';
  }

  private static async readPeriods(context: common.Context, tableId: number): Promise<ClassPeriodLike[]> {
    const fallback: ClassPeriodLike[] = [];
    for (let i = 0; i < LegacyConstant.CLASS_TIME_LIST.length; i++) {
      fallback.push(new ClassPeriodLike(LegacyConstant.CLASS_TIME_LIST[i].start, LegacyConstant.CLASS_TIME_LIST[i].end));
    }
    try {
      const rdb: relationalStore.RdbStore = await WidgetDataProvider.openRdb(context);
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_TABLES);
      predicates.equalTo('id', tableId);
      const resultSet: relationalStore.ResultSet = await rdb.query(predicates, ['data']);
      let data: string = '';
      try {
        if (resultSet.goToNextRow()) {
          data = WidgetDataProvider.colStr(resultSet, 'data');
        }
      } finally {
        resultSet.close();
      }
      if (data === '') {
        return fallback;
      }
      const parsed: Record<string, Object> = JSON.parse(data) as Record<string, Object>;
      const raw: Object | undefined = parsed.class_time_list;
      if (raw === undefined || !Array.isArray(raw)) {
        return fallback;
      }
      const list: Object[] = raw as Object[];
      const periods: ClassPeriodLike[] = [];
      for (let i = 0; i < list.length; i++) {
        const item: Record<string, Object> = list[i] as Record<string, Object>;
        periods.push(new ClassPeriodLike(WidgetDataProvider.toStr(item.start), WidgetDataProvider.toStr(item.end)));
      }
      return periods.length > 0 ? periods : fallback;
    } catch (err) {
      return fallback;
    }
  }

  private static async openRdb(context: common.Context): Promise<relationalStore.RdbStore> {
    const config: relationalStore.StoreConfig = {
      name: 'course.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    return relationalStore.getRdbStore(context, config);
  }

  // ---- 工具 ----

  private static weekday(date: Date): number {
    const day: number = date.getDay();
    return day === 0 ? 7 : day;
  }

  private static resolveWeek(weekIndex: number, lastMonday: string, now: Date): number {
    if (lastMonday === '') {
      return Math.max(weekIndex, 1);
    }
    const parsed: Date = WidgetDataProvider.parseDate(lastMonday);
    if (parsed.getTime() === 0) {
      return Math.max(weekIndex, 1);
    }
    const thisMonday: Date = WidgetDataProvider.mondayOf(now);
    const days: number = Math.floor(
      (WidgetDataProvider.utcDay(thisMonday) - WidgetDataProvider.utcDay(parsed)) / 86400000);
    const bias: number = Math.floor(days / 7);
    return Math.max(weekIndex + bias, 1);
  }

  private static mondayOf(date: Date): Date {
    const day: Date = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    const weekday: number = WidgetDataProvider.weekday(day);
    return new Date(day.getFullYear(), day.getMonth(), day.getDate() - (weekday - 1));
  }

  private static utcDay(date: Date): number {
    return Date.UTC(date.getFullYear(), date.getMonth(), date.getDate());
  }

  private static parseDate(text: string): Date {
    const parts: string[] = text.split('-');
    if (parts.length !== 3) {
      return new Date(0);
    }
    return new Date(parseInt(parts[0], 10), parseInt(parts[1], 10) - 1, parseInt(parts[2], 10));
  }

  /** "08:00" → 480；非法返回 -1。 */
  private static toMinutes(text: string): number {
    const parts: string[] = text.split(':');
    if (parts.length < 2) {
      return -1;
    }
    const hour: number = parseInt(parts[0], 10);
    const minute: number = parseInt(parts[1], 10);
    if (isNaN(hour) || isNaN(minute)) {
      return -1;
    }
    return hour * 60 + minute;
  }

  private static parsePool(raw: string): number[] {
    if (raw === '') {
      return [];
    }
    try {
      const parsed: number[] = JSON.parse(raw) as number[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (err) {
      return [];
    }
  }

  /** 0 跟随系统 / 1 浅色 / 2 深色（旧版 themeModeIndex）。 */
  private static readAppearanceMode(index: number, systemDark: boolean): string {
    if (index === 2) {
      return 'dark';
    }
    if (index === 1) {
      return 'light';
    }
    return systemDark ? 'dark' : 'light';
  }

  private static contextIsDark(context: common.Context): boolean {
    try {
      const formContext: common.FormExtensionContext = context as common.FormExtensionContext;
      return formContext.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } catch (err) {
      return false;
    }
  }

  private static readAccent(index: number, customHex: string): string {
    if (index === ColorMath.CUSTOM_INDEX) {
      const raw: string = customHex.trim().toUpperCase();
      if (ColorMath.isValidHex(raw)) {
        return raw;
      }
    }
    return ColorMath.preset(index);
  }

  /** 自动提亮主题色开关：prefs 可能存 boolean / number / string，统一转 bool。 */
  private static readAutoDarkAccent(value: preferences.ValueType): boolean {
    if (typeof value === 'boolean') {
      return value;
    }
    if (typeof value === 'number') {
      return value !== 0;
    }
    return `${value}` !== 'false' && `${value}` !== '0';
  }

  private static async readCourseColors(store: preferences.Preferences): Promise<WidgetCourseColors> {
    const paletteId: string = WidgetDataProvider.toStr(await store.get('colorPalette', CourseColorPalettes.DEFAULT_ID));
    const palette: string[] = CourseColorPalettes.get(paletteId).colors;
    const pool: number[] = WidgetDataProvider.parsePool(WidgetDataProvider.toStr(await store.get('colorPool', '')));
    const seed: number = WidgetDataProvider.toInt(await store.get('colorPoolSeed', 0), 0);
    return new WidgetCourseColors(palette, pool, seed);
  }

  private static colStr(resultSet: relationalStore.ResultSet, column: string): string {
    const index: number = resultSet.getColumnIndex(column);
    if (index < 0 || resultSet.isColumnNull(index)) {
      return '';
    }
    return resultSet.getString(index);
  }

  private static colNum(resultSet: relationalStore.ResultSet, column: string): number {
    const index: number = resultSet.getColumnIndex(column);
    if (index < 0 || resultSet.isColumnNull(index)) {
      return 0;
    }
    return resultSet.getLong(index);
  }

  private static parseIntArray(raw: string): number[] {
    if (raw === '') {
      return [];
    }
    try {
      const parsed: number[] = JSON.parse(raw) as number[];
      const result: number[] = [];
      for (let i = 0; i < parsed.length; i++) {
        if (typeof parsed[i] === 'number') {
          result.push(parsed[i]);
        }
      }
      return result;
    } catch (err) {
      return [];
    }
  }

  private static toStr(value: Object | undefined): string {
    return value === undefined || value === null ? '' : `${value}`;
  }

  private static toInt(value: preferences.ValueType, fallback: number): number {
    if (typeof value === 'number') {
      return Math.trunc(value);
    }
    const parsed: number = parseInt(`${value}`, 10);
    return isNaN(parsed) ? fallback : parsed;
  }
}

/** 卡片侧用的作息项（不依赖 data/Constants 的 ClassPeriod，便于独立编译）。 */
export class ClassPeriodLike {
  start: string = '';
  end: string = '';

  constructor(start: string, end: string) {
    this.start = start;
    this.end = end;
  }
}
