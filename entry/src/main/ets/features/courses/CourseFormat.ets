/**
 * 课程模块内部工具（只被 features/courses 使用）。
 *
 * 职责：
 * - 把「同表同名」的多个 Course 行合并成一张课程卡片所需的分组数据；
 * - 表单侧周次选择（全部/单周/双周/自定义）与 `weeks: number[]` 的双向转换；
 * - 课程时间、教师、地点的展示文案与色值校验。
 *
 * 展示口径统一走 `features/timetable/WeeksFormat`（周次摘要 / 节次 / 星期 / 来源），
 * 这里只补组合逻辑，避免两个模块各写一套文案。
 */
import { Course } from '../../data/models/Models';
import { LegacyConfig, LegacyConstant } from '../../common/Constants';
import { ColorPool } from '../../data/ColorPool';
import { WeeksFormat } from '../timetable/WeeksFormat';

/** 同门课（同表同名）全部时段合并后的一组，用于课程列表的一张卡片。 */
export class CourseGroup {
  name: string = '';
  /** 教师；多时段不同教师时去重后用「、」连接。 */
  teacherText: string = '';
  /** 上课地点；多时段不同地点时去重后用「、」连接。 */
  roomText: string = '';
  /** 周次摘要（所有时段周次的并集）。 */
  weekText: string = '';
  /** 色块颜色，来自 `ColorPool.resolve`。 */
  color: string = '';
  /** 打开详情用的课程行 `id`（取第一个时段）。 */
  courseId: number = 0;
  /** 来源类型（取第一个时段），用于来源徽标。 */
  importType: number = LegacyConstant.ADD_MANUALLY;
  sessions: Course[] = [];
}

/** 星期选择项；`value = 0` 表示自由时间（不占节次）。 */
export class WeekdayOption {
  value: number = 1;
  label: string = '';

  constructor(value: number, label: string) {
    this.value = value;
    this.label = label;
  }
}

/** 表单侧周次选择状态（扁平化字段，V2 下由 `@Local` 观察）。 */
export class WeekSelection {
  startWeek: number = 1;
  endWeek: number = LegacyConfig.MAX_WEEKS;
  weekType: number = LegacyConstant.FULL_WEEKS;
  /** 自定义周次（仅 `weekType === DEFINED_WEEKS` 时使用）。 */
  customWeeks: number[] = [];
}

export class CourseFormat {
  // ---- 课程列表分组 ----

  /** 按课程名分组；同名课程的多个时段合并，颜色取色池解析结果。 */
  static group(courses: Course[], pool: number[]): CourseGroup[] {
    const groups: CourseGroup[] = [];
    for (let i = 0; i < courses.length; i++) {
      const course: Course = courses[i];
      let group: CourseGroup | null = null;
      for (let j = 0; j < groups.length; j++) {
        if (groups[j].name === course.name) {
          group = groups[j];
          break;
        }
      }
      if (group === null) {
        group = new CourseGroup();
        group.name = course.name;
        group.courseId = course.id;
        group.importType = course.importType;
        group.color = ColorPool.resolve(course, pool);
        groups.push(group);
      }
      group.sessions.push(course);
    }
    for (let i = 0; i < groups.length; i++) {
      CourseFormat.summarize(groups[i]);
    }
    groups.sort((a: CourseGroup, b: CourseGroup): number => a.name.localeCompare(b.name));
    return groups;
  }

  private static summarize(group: CourseGroup): void {
    group.sessions.sort((a: Course, b: Course): number => CourseFormat.compareSession(a, b));
    const teachers: string[] = [];
    const rooms: string[] = [];
    const weeks: number[] = [];
    for (let i = 0; i < group.sessions.length; i++) {
      const session: Course = group.sessions[i];
      CourseFormat.pushUnique(teachers, session.teacher.trim());
      CourseFormat.pushUnique(rooms, session.classroom.trim());
      for (let j = 0; j < session.weeks.length; j++) {
        const week: number = session.weeks[j];
        if (weeks.indexOf(week) < 0) {
          weeks.push(week);
        }
      }
    }
    weeks.sort((a: number, b: number): number => a - b);
    group.teacherText = teachers.length > 0 ? teachers.join('、') : '教师未填写';
    group.roomText = rooms.length > 0 ? rooms.join('、') : '地点未填写';
    group.weekText = WeeksFormat.describe(weeks);
  }

  /** 自由时间课程（weekTime = 0）排在所有星期之后。 */
  private static compareSession(a: Course, b: Course): number {
    const weekdayA: number = a.weekTime <= 0 ? 99 : a.weekTime;
    const weekdayB: number = b.weekTime <= 0 ? 99 : b.weekTime;
    if (weekdayA !== weekdayB) {
      return weekdayA - weekdayB;
    }
    return a.startTime - b.startTime;
  }

  private static pushUnique(list: string[], value: string): void {
    if (value !== '' && list.indexOf(value) < 0) {
      list.push(value);
    }
  }

  // ---- 单个时段文案 ----

  /** 如「周一 第3-4节 · 1-16周」。 */
  static sessionTimeText(course: Course): string {
    return `${CourseFormat.courseTimeText(course)} · ${WeeksFormat.describe(course.weeks)}`;
  }

  /** 如「周一 第3-4节」；自由时间课程返回「自由时间」。 */
  static courseTimeText(course: Course): string {
    if (course.weekTime <= 0) {
      return '自由时间';
    }
    const weekday: string = WeeksFormat.weekdayLabel(course.weekTime);
    const period: string = WeeksFormat.periodLabel(course);
    return `${weekday} ${period}`;
  }

  // ---- 周次选择 ----

  static defaultSelection(): WeekSelection {
    return new WeekSelection();
  }

  /** 按「起止周 + 类型」生成落库用的周次数组；自定义时用已勾选的周次。 */
  static buildWeeks(selection: WeekSelection): number[] {
    const weeks: number[] = [];
    const start: number = CourseFormat.clampWeek(selection.startWeek);
    const end: number = Math.max(start, CourseFormat.clampWeek(selection.endWeek));
    if (selection.weekType === LegacyConstant.SINGLE_WEEKS) {
      const first: number = start % 2 === 1 ? start : start + 1;
      for (let week = first; week <= end; week += 2) {
        weeks.push(week);
      }
      return weeks;
    }
    if (selection.weekType === LegacyConstant.DOUBLE_WEEKS) {
      const first: number = start % 2 === 0 ? start : start + 1;
      for (let week = first; week <= end; week += 2) {
        weeks.push(week);
      }
      return weeks;
    }
    if (selection.weekType === LegacyConstant.DEFINED_WEEKS) {
      const sorted: number[] = [];
      for (let i = 0; i < selection.customWeeks.length; i++) {
        const week: number = Math.trunc(selection.customWeeks[i]);
        if (week >= 1 && week <= LegacyConfig.MAX_WEEKS && sorted.indexOf(week) < 0) {
          sorted.push(week);
        }
      }
      sorted.sort((a: number, b: number): number => a - b);
      return sorted;
    }
    for (let week = start; week <= end; week++) {
      weeks.push(week);
    }
    return weeks;
  }

  /** 从已有课程周次反解出表单状态：连续 → 全部，步长 2 → 单/双周，否则自定义。 */
  static fromWeeks(weeks: number[]): WeekSelection {
    const selection: WeekSelection = new WeekSelection();
    if (weeks.length === 0) {
      return selection;
    }
    const sorted: number[] = weeks.slice();
    sorted.sort((a: number, b: number): number => a - b);
    selection.startWeek = CourseFormat.clampWeek(sorted[0]);
    selection.endWeek = Math.max(selection.startWeek, CourseFormat.clampWeek(sorted[sorted.length - 1]));
    selection.customWeeks = sorted;
    if (CourseFormat.isStep(sorted, 1)) {
      selection.weekType = LegacyConstant.FULL_WEEKS;
    } else if (CourseFormat.isStep(sorted, 2) && sorted[0] % 2 === 1) {
      selection.weekType = LegacyConstant.SINGLE_WEEKS;
    } else if (CourseFormat.isStep(sorted, 2) && sorted[0] % 2 === 0) {
      selection.weekType = LegacyConstant.DOUBLE_WEEKS;
    } else {
      selection.weekType = LegacyConstant.DEFINED_WEEKS;
    }
    return selection;
  }

  private static isStep(sorted: number[], step: number): boolean {
    if (sorted.length <= 1) {
      return true;
    }
    for (let i = 1; i < sorted.length; i++) {
      if (sorted[i] - sorted[i - 1] !== step) {
        return false;
      }
    }
    return true;
  }

  static clampWeek(week: number): number {
    const value: number = Math.trunc(week);
    if (value < 1) {
      return 1;
    }
    if (value > LegacyConfig.MAX_WEEKS) {
      return LegacyConfig.MAX_WEEKS;
    }
    return value;
  }

  static clampPeriod(period: number): number {
    const value: number = Math.trunc(period);
    if (value < 1) {
      return 1;
    }
    if (value > LegacyConfig.MAX_CLASSES) {
      return LegacyConfig.MAX_CLASSES;
    }
    return value;
  }

  static weekNumbers(): number[] {
    const weeks: number[] = [];
    for (let week = 1; week <= LegacyConfig.MAX_WEEKS; week++) {
      weeks.push(week);
    }
    return weeks;
  }

  static periodNumbers(): number[] {
    const periods: number[] = [];
    for (let period = 1; period <= LegacyConfig.MAX_CLASSES; period++) {
      periods.push(period);
    }
    return periods;
  }

  /** 星期一至星期日 + 自由时间（`value = 0` 排在最后）。 */
  static weekdayOptions(): WeekdayOption[] {
    const options: WeekdayOption[] = [];
    for (let weekday = 1; weekday <= 7; weekday++) {
      options.push(new WeekdayOption(weekday, LegacyConstant.WEEK_WITH_BIAS[weekday]));
    }
    options.push(new WeekdayOption(0, '自由时间'));
    return options;
  }

  // ---- 颜色 ----

  /** `#RRGGBB` / `RRGGBB` → `#RRGGBB`；非法返回空串。 */
  static normalizeHex(input: string): string {
    const raw: string = input.trim();
    if (raw === '') {
      return '';
    }
    const body: string = raw.startsWith('#') ? raw.substring(1) : raw;
    if (!new RegExp('^[0-9A-Fa-f]{6}$').test(body)) {
      return '';
    }
    return `#${body.toUpperCase()}`;
  }


}
