/**
 * 课程编辑页的「时段」草稿（状态管理 V2：`@ObservedV2` + `@Trace`）。
 *
 * 背景：同一门课在 `course` 表里是多行（每个时段一行），编辑页把它们作为一个整体
 * 「课程 + 时段列表」编辑（对应上游 Flutter `EditCourseView._MeetingDraft` /
 * `CourseMeetingInput.dart`）。课程级字段（名称 / 信息 / 考试 / 链接 / 颜色）留在
 * `CourseEditPage` 的 `@Local` 上，本类只保存每个时段自己的字段与周次选择状态。
 *
 * 设计约定：
 * - `original` 是打开编辑页时从库里读到的原始行，**只读**，绝不就地修改；
 *   保存时用 `Course.clone()` 派生新行（数据层 `saveMeetingGroup` 会校验 originals 未变化）。
 * - 周次用「全部 / 单周 / 双周 / 自定义」语义保存（与现有表单一致），落库时经
 *   `CourseFormat.buildWeeks` 转成 `weeks: number[]`。
 * - `timePending = true` 表示自由时间 / 时间待定，落库时 `weekTime / startTime / timeCount`
 *   全为 0（与数据模型语义一致）。
 * - `order / removable / expanded / weekError` 是纯 UI 状态，由页面维护，不落库。
 */
import { Course } from '../../data/models/Models';
import { LegacyConfig, LegacyConstant } from '../../common/Constants';
import { WeeksFormat } from '../timetable/WeeksFormat';
import { CourseFormat, WeekSelection } from './CourseFormat';

@ObservedV2
export class CourseMeetingDraft {
  /** 表单内稳定 key（ForEach key 用），不落库。 */
  key: number = 0;
  /** 打开编辑页时对应的原始行；新增时段为 null（只读，保存时 clone 派生新行）。 */
  original: Course | null = null;

  // ---- 页面 UI 状态（由 CourseEditPage 统一维护） ----
  /** 时段在列表中的位置（从 0 开始），用于「时段 N」标题。 */
  @Trace order: number = 0;
  /** 是否允许删除：列表只剩一个时段时为 false（页面保证至少保留一个）。 */
  @Trace removable: boolean = false;
  /** 卡片展开 / 折叠。 */
  @Trace expanded: boolean = true;
  /** 周次为空的校验错误（保存时置位，用户改周次后由页面清掉）。 */
  @Trace weekError: boolean = false;

  // ---- 时段级字段 ----
  @Trace teacher: string = '';
  @Trace classroom: string = '';

  // ---- 周次选择（全部 / 单周 / 双周 / 自定义） ----
  @Trace weekStart: number = 1;
  @Trace weekEnd: number = LegacyConfig.MAX_WEEKS;
  @Trace weekType: number = LegacyConstant.FULL_WEEKS;
  /** 自定义周次（仅 weekType === DEFINED_WEEKS 时使用）。 */
  @Trace customWeeks: number[] = [];

  // ---- 时间（自由时间 / 待定时不占节次） ----
  @Trace pending: boolean = false;
  /** 星期 1-7。 */
  @Trace day: number = 1;
  /** 起始节次（1 基）。 */
  @Trace start: number = 1;
  /** 结束节次（1 基，含）。 */
  @Trace end: number = 1;

  constructor(key: number = 0) {
    this.key = key;
  }

  /** 新增模式下的第一个空时段：周次全选、周一第 1 节。 */
  static blank(key: number): CourseMeetingDraft {
    const draft: CourseMeetingDraft = new CourseMeetingDraft(key);
    draft.expanded = true;
    return draft;
  }

  /**
   * 由上一时段复制出新时段：教师 / 教室 / 周次 / 节次沿用，星期顺延一天。
   * 与上游 `_addDraft(copy: _slots.last)` 一致（时间待定不复用，避免误存自由时间）。
   */
  static copyOf(key: number, source: CourseMeetingDraft): CourseMeetingDraft {
    const draft: CourseMeetingDraft = new CourseMeetingDraft(key);
    draft.teacher = source.teacher;
    draft.classroom = source.classroom;
    draft.weekStart = source.weekStart;
    draft.weekEnd = source.weekEnd;
    draft.weekType = source.weekType;
    draft.customWeeks = source.customWeeks.slice();
    draft.day = source.day >= 1 && source.day < 7 ? source.day + 1 : 1;
    draft.start = source.start;
    draft.end = source.end;
    draft.pending = false;
    draft.expanded = true;
    return draft;
  }

  /** 从库里的课程行回填一个时段草稿（`expanded` 只让第一个时段展开）。 */
  static fromCourse(key: number, course: Course, expanded: boolean): CourseMeetingDraft {
    const draft: CourseMeetingDraft = new CourseMeetingDraft(key);
    draft.original = course;
    draft.teacher = course.teacher;
    draft.classroom = course.classroom;
    draft.pending = course.weekTime === 0;
    draft.day = course.weekTime >= 1 && course.weekTime <= 7 ? course.weekTime : 1;
    draft.start = CourseFormat.clampPeriod(course.startTime > 0 ? course.startTime : 1);
    const rawEnd: number = course.startTime + course.timeCount;
    draft.end = rawEnd >= draft.start ? Math.min(rawEnd, LegacyConfig.MAX_CLASSES) : draft.start;
    const selection: WeekSelection = CourseFormat.fromWeeks(course.weeks);
    draft.weekStart = selection.startWeek;
    draft.weekEnd = selection.endWeek;
    draft.weekType = selection.weekType;
    draft.customWeeks = selection.customWeeks;
    draft.expanded = expanded;
    return draft;
  }

  // ---- 周次 ----

  /** 当前周次选择（起止周 + 类型 + 自定义列表）。 */
  selection(): WeekSelection {
    const selection: WeekSelection = new WeekSelection();
    selection.startWeek = this.weekStart;
    selection.endWeek = this.weekEnd;
    selection.weekType = this.weekType;
    selection.customWeeks = this.customWeeks;
    return selection;
  }

  /** 落库用的周次数组（已排序、去重、只保留 1-MAX_WEEKS）。 */
  weeks(): number[] {
    return CourseFormat.buildWeeks(this.selection());
  }

  /** 如「1-16周」「1-15单周」「1,3,5周」；空数组返回「未选择周次」。 */
  weekSummary(): string {
    const weeks: number[] = this.weeks();
    return weeks.length === 0 ? '未选择周次' : WeeksFormat.describe(weeks);
  }

  /** 切换「全部 / 单周 / 双周 / 自定义」；首次切到自定义时用当前周次范围填充，避免空网格。 */
  onWeekTypeSelect(index: number): void {
    this.weekType = index;
    this.weekError = false;
    if (index === LegacyConstant.DEFINED_WEEKS && this.customWeeks.length === 0) {
      const base: WeekSelection = this.selection();
      base.weekType = LegacyConstant.FULL_WEEKS;
      this.customWeeks = CourseFormat.buildWeeks(base);
    }
  }

  toggleWeek(week: number): void {
    const next: number[] = this.customWeeks.slice();
    const index: number = next.indexOf(week);
    if (index >= 0) {
      next.splice(index, 1);
    } else {
      next.push(week);
    }
    this.customWeeks = next;
    this.weekError = false;
  }

  selectAllWeeks(): void {
    this.customWeeks = CourseFormat.weekNumbers();
    this.weekError = false;
  }

  clearWeeks(): void {
    this.customWeeks = [];
  }

  /** 改起始周；结束周早于起始周时顺带抬到起始周。 */
  setWeekStart(week: number): void {
    this.weekStart = CourseFormat.clampWeek(week);
    if (this.weekEnd < this.weekStart) {
      this.weekEnd = this.weekStart;
    }
  }

  /** 改结束周；结束周早于起始周时收窄起始周。 */
  setWeekEnd(week: number): void {
    this.weekEnd = CourseFormat.clampWeek(week);
    if (this.weekStart > this.weekEnd) {
      this.weekStart = this.weekEnd;
    }
  }

  // ---- 时间 ----

  setDay(day: number): void {
    this.day = day >= 1 && day <= 7 ? day : 1;
  }

  /** 改起始节次；结束节早于起始节时顺带抬到起始节。 */
  setStart(period: number): void {
    this.start = CourseFormat.clampPeriod(period);
    if (this.end < this.start) {
      this.end = this.start;
    }
  }

  /** 改结束节次；结束节早于起始节收窄起始节（与上游 `start = min(start, end)` 一致）。 */
  setEnd(period: number): void {
    this.end = CourseFormat.clampPeriod(period);
    if (this.start > this.end) {
      this.start = this.end;
    }
  }

  /** 如「周一 · 第3-4节」；时间待定返回「时间待定」。 */
  timeSummary(): string {
    if (this.pending) {
      return '时间待定';
    }
    const weekday: string = LegacyConstant.WEEK_WITH_BIAS[this.day];
    if (this.end <= this.start) {
      return `${weekday} · 第${this.start}节`;
    }
    return `${weekday} · 第${this.start}-${this.end}节`;
  }

  /** 非待定时的星期 / 节次合法性（1-7、1-MAX_CLASSES、end >= start）。 */
  isTimeValid(): boolean {
    if (this.pending) {
      return true;
    }
    return this.day >= 1 && this.day <= 7 &&
      this.start >= 1 && this.start <= LegacyConfig.MAX_CLASSES &&
      this.end >= this.start && this.end <= LegacyConfig.MAX_CLASSES;
  }
}
