/**
 * 把当前课表导出到系统日历中与课表同名的独立 LOCAL 账户。
 *
 * 参考：
 * - 上游 Flutter：lib/Utils/CalendarExporter.dart —— 按课程周次展开为逐次日程，
 *   先构建/校验全部日程，再申请权限并写入；
 * - HarmonyOS Calendar Kit：CalendarAccount + Calendar + Event；账户使用 LOCAL 类型，
 *   不读取也不写入系统默认日历或其他应用账户。
 *
 * 每个课表使用自己的 LOCAL 日历账户（displayName 为课表名），重复导出
 * 只替换当前课表账户下的日程；不同课表互不覆盖。
 */
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { calendarManager } from '@kit.CalendarKit';
import { ColorMath } from '../common/design/ColorMath';
import { ClassPeriod } from '../common/Constants';
import { DateUtils } from '../common/DateUtils';
import { Course, CourseTable } from './models/Models';
import { CourseRepository } from './CourseRepository';
import { CourseTableRepository } from './CourseTableRepository';
import { WeekUtil, TableWeekState } from './WeekUtil';

/** 当前课表导出结果。 */
export class CalendarExportResult {
  tableName: string = '';
  eventCount: number = 0;
}

export class CalendarExport {
  private static readonly ACCOUNT_PREFIX: string = 'com.njuschedulenext.jesse.calendar.table.';
  private static readonly PERMISSIONS: Permissions[] = [
    'ohos.permission.READ_CALENDAR',
    'ohos.permission.WRITE_CALENDAR'
  ];
  private static readonly REMINDER_OPTIONS: number[] = [5, 10, 15, 30];

  /**
   * 导出当前课表。reminderMinutes 为 0 表示不提醒；
   * 其余值写入每条 Event.reminderTime。
   */
  static async exportTable(context: common.UIAbilityContext, tableId: number,
    reminderMinutes: number): Promise<CalendarExportResult> {
    if (tableId <= 0) {
      throw new Error('当前课表不存在');
    }
    await CalendarExport.ensurePermission(context);

    const table: CourseTable | null = await CourseTableRepository.getById(tableId);
    if (table === null) {
      throw new Error('当前课表不存在');
    }
    const courses: Course[] = await CourseRepository.getAll(tableId);
    const periods: ClassPeriod[] = await CourseTableRepository.getClassTimeList(tableId);
    const week: TableWeekState = await WeekUtil.ensureWeekForTable(tableId);
    const events: calendarManager.Event[] = CalendarExport.buildEvents(
      table.name, courses, periods, week.week, week.monday, reminderMinutes);
    if (events.length === 0) {
      throw new Error('当前课表没有可导出的课程');
    }

    const manager: calendarManager.CalendarManager = calendarManager.getCalendarManager(context);
    const calendar: calendarManager.Calendar = await CalendarExport.obtainCalendar(
      manager, tableId, table.name);

    // 账户为该课表独有，重复导出时整体替换该账户下的日程。
    const existing: calendarManager.Event[] = await calendar.getEvents();
    const removeIds: number[] = [];
    for (let i = 0; i < existing.length; i++) {
      const eventId: number | undefined = existing[i].id;
      if (eventId !== undefined) {
        removeIds.push(eventId);
      }
    }
    if (removeIds.length > 0) {
      await calendar.deleteEvents(removeIds);
    }
    await calendar.addEvents(events);

    const result: CalendarExportResult = new CalendarExportResult();
    result.tableName = table.name;
    result.eventCount = events.length;
    return result;
  }

  /** 构建逐次日程；调用方在写入前完成全部校验，避免部分导出。 */
  static buildEvents(tableName: string, courses: Course[], periods: ClassPeriod[],
    currentWeek: number, currentMonday: string, reminderMinutes: number): calendarManager.Event[] {
    if (periods.length === 0) {
      throw new Error('当前课表没有作息时间');
    }
    const weekOneMonday: Date = DateUtils.addDays(
      DateUtils.parseIsoDate(currentMonday), -(Math.max(1, currentWeek) - 1) * 7);
    const events: calendarManager.Event[] = [];

    for (let i = 0; i < courses.length; i++) {
      const course: Course = courses[i];
      // weekTime/startTime 为 0 的课程没有固定上课时间，导出跳过。
      // timeCount 是「结束节次 - 开始节次」，单节课为 0（见 TimetableView 的 timeCount + 1）。
      if (course.weekTime <= 0 || course.startTime <= 0 || course.timeCount < 0 ||
        course.weeks.length === 0) {
        continue;
      }
      const startIndex: number = course.startTime - 1;
      const endIndex: number = course.startTime + course.timeCount - 1;
      if (startIndex < 0 || endIndex >= periods.length) {
        throw new Error(`课程「${course.name}」的节次超出作息范围`);
      }
      const startMinutes: number = CalendarExport.clockMinutes(periods[startIndex].start);
      const endMinutes: number = CalendarExport.clockMinutes(periods[endIndex].end);
      if (startMinutes < 0 || endMinutes < 0 || endMinutes <= startMinutes) {
        throw new Error(`课程「${course.name}」的上课时间无效`);
      }

      const weeks: number[] = CalendarExport.uniqueWeeks(course);
      for (let j = 0; j < weeks.length; j++) {
        const week: number = weeks[j];
        const day: Date = DateUtils.addDays(weekOneMonday,
          (week - 1) * 7 + course.weekTime - 1);
        const start: Date = CalendarExport.atMinutes(day, startMinutes);
        const end: Date = CalendarExport.atMinutes(day, endMinutes);
        const event: calendarManager.Event = {
          type: calendarManager.EventType.NORMAL,
          title: course.name,
          startTime: start.getTime(),
          endTime: end.getTime(),
          timeZone: 'Asia/Shanghai',
          description: CalendarExport.description(tableName, course)
        };
        if (course.classroom !== '') {
          event.location = { location: course.classroom };
        }
        if (reminderMinutes > 0) {
          event.reminderTime = [reminderMinutes];
        }
        events.push(event);
      }
    }
    events.sort((a: calendarManager.Event, b: calendarManager.Event) => a.startTime - b.startTime);
    return events;
  }

  /** 提醒候选项（分钟），与设置页文本选择器共用。 */
  static reminderChoices(): number[] {
    return CalendarExport.REMINDER_OPTIONS.slice();
  }

  private static async ensurePermission(context: common.UIAbilityContext): Promise<void> {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const result = await atManager.requestPermissionsFromUser(context, CalendarExport.PERMISSIONS);
    for (let i = 0; i < result.authResults.length; i++) {
      if (result.authResults[i] !== 0) {
        throw new Error('未授予日历权限，请在系统设置中允许“呢喃课表”访问日历');
      }
    }
  }

  private static async obtainCalendar(manager: calendarManager.CalendarManager, tableId: number,
    tableName: string): Promise<calendarManager.Calendar> {
    const accountName: string = `${CalendarExport.ACCOUNT_PREFIX}${tableId}`;
    const displayName: string = CalendarExport.safeDisplayName(tableName, tableId);
    const calendars: calendarManager.Calendar[] = await manager.getAllCalendars();
    let sameNameDifferentDisplay: calendarManager.Calendar | undefined = undefined;
    for (let i = 0; i < calendars.length; i++) {
      const account: calendarManager.CalendarAccount = calendars[i].getAccount();
      if (account.name === accountName && account.type === calendarManager.CalendarType.LOCAL) {
        if (account.displayName === displayName) {
          await calendars[i].setConfig({ enableReminder: true });
          return calendars[i];
        }
        sameNameDifferentDisplay = calendars[i];
      }
    }
    // 课表改名后没有直接更新账户 displayName 的接口；删除重建同名账户。
    if (sameNameDifferentDisplay !== undefined) {
      await manager.deleteCalendar(sameNameDifferentDisplay);
    }
    const created: calendarManager.Calendar = await manager.createCalendar({
      name: accountName,
      type: calendarManager.CalendarType.LOCAL,
      displayName: displayName
    });
    await created.setConfig({
      enableReminder: true,
      color: ColorMath.PRESETS[ColorMath.NJU_PURPLE_INDEX]
    });
    return created;
  }

  private static safeDisplayName(tableName: string, tableId: number): string {
    const trimmed: string = tableName.trim();
    if (trimmed === '') {
      return `课表 ${tableId}`;
    }
    return trimmed.substring(0, 64);
  }

  private static uniqueWeeks(course: Course): number[] {
    const weeks: number[] = [];
    for (let i = 0; i < course.weeks.length; i++) {
      const week: number = course.weeks[i];
      if (week <= 0) {
        throw new Error(`课程「${course.name}」的周次无效`);
      }
      if (weeks.indexOf(week) < 0) {
        weeks.push(week);
      }
    }
    weeks.sort((a: number, b: number) => a - b);
    return weeks;
  }

  private static description(tableName: string, course: Course): string {
    const parts: string[] = [`课表：${tableName}`];
    if (course.teacher !== '') {
      parts.push(`教师：${course.teacher}`);
    }
    if (course.classNumber !== '') {
      parts.push(`班级：${course.classNumber}`);
    }
    if (course.info !== '') {
      parts.push(course.info);
    }
    return parts.join('\n');
  }

  /** "HH:mm" → 当日分钟数；无效返回 -1。 */
  private static clockMinutes(text: string): number {
    const parts: string[] = text.split(':');
    if (parts.length !== 2) {
      return -1;
    }
    const hour: number = Number(parts[0]);
    const minute: number = Number(parts[1]);
    if (!Number.isInteger(hour) || !Number.isInteger(minute) ||
      hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return -1;
    }
    return hour * 60 + minute;
  }

  private static atMinutes(day: Date, minutes: number): Date {
    return new Date(day.getFullYear(), day.getMonth(), day.getDate(),
      Math.floor(minutes / 60), minutes % 60);
  }
}
