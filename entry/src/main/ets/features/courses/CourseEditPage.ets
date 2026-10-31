/**
 * 添加 / 编辑课程页（路由名 `course-edit`，参数 `CourseEditParam`）。
 *
 * - `courseId > 0` 为编辑（按行 id 读库并回填），`courseId = 0` 为新增；
 * - 新增时 `importType = LegacyConstant.ADD_MANUALLY` 且 `courseId = -1`，
 *   由 `CourseRepository.insert` 自动分配同门课共享的 `course_id`；
 * - 保存成功后 await `AppState.bumpDataRevision()`，等小组件同步完成再 pop。
 *
 * 校验：课程名必填；节次落在 1-13 节内；周次非空（自定义周次至少一周）；
 * 自定义色值必须为 `#RRGGBB`。
 */
import { resolveNavStack } from '../../common/NavStackResolver';
import { Feedback } from '../../common/ui/Feedback';
import { HdsNavDestination, HdsNavigationMenuContentOptions, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit';
import { CapsuleSegmentButtonV2, ColorMetrics, LengthMetrics, SegmentButtonV2Items } from '@kit.ArkUI';
import { Course } from '../../data/models/Models';
import { CourseRepository } from '../../data/CourseRepository';
import { ColorPool } from '../../data/ColorPool';
import { AppState } from '../../app/AppState';
import { LegacyConfig, LegacyConstant, LegacyCourseColors } from '../../common/Constants';
import { CourseEditParam } from '../../common/RouteParams';
import { Colors, FontSize, HdsMetrics, Spacing } from '../../common/design/Tokens';
import { hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import { EmptyState } from '../../common/ui/EmptyState';
import { WeeksFormat } from '../timetable/WeeksFormat';
import { CourseFormat, WeekdayOption, WeekSelection } from './CourseFormat';
import { AppStore } from '../../app/AppStore';
import { CourseTextField, FormSection, SelectChip } from './CourseFormParts';
import { SettingsItemDivider, SettingsRow } from '../../common/ui/SettingsListItems';

@ComponentV2
export struct CourseEditPage {
  /** V2 全局 Store（主题色 / 避让区）。 */
  @Local store: AppStore = AppStore.connect();
  /** 外壳显式传入的目标课表（路由参数优先，落本地后可回写）。 */
  /** 外壳显式传入的课程 id；0 表示新增。 */
  @Param courseId: number = 0;
  /** 外壳可选传入的导航栈；正常走 onReady 里的 pathStack。 */
  @Param pageStack: NavPathStack = new NavPathStack();
  /** 本地承接的路由参数（@Param 不可回写）。 */
  @Local pageTableId: number = 0;
  @Local pageCourseId: number = 0;

  // ---- 表单状态（扁平化，V2 @Local） ----
  @Local name: string = '';
  @Local classroom: string = '';
  @Local teacher: string = '';
  @Local info: string = '';
  @Local testTime: string = '';
  @Local testLocation: string = '';
  @Local freeTime: boolean = false;
  @Local weekTime: number = 1;
  @Local startTime: number = 1;
  @Local periodCount: number = 1;
  @Local weekStart: number = 1;
  @Local weekEnd: number = LegacyConfig.MAX_WEEKS;
  @Local weekType: number = LegacyConstant.FULL_WEEKS;
  @Local customWeeks: number[] = [];
  @Local colorValue: string = '';
  @Local customHex: string = '';
  @Local colorMode: number = 0;
  @Local nameError: string = '';
  @Local formError: string = '';
  @Local saving: boolean = false;
  @Local loading: boolean = true;
  @Local loadFailed: boolean = false;

  private stack: NavPathStack | null = null;
  private scroller: Scroller = new Scroller();
  private loadedCourse: Course | null = null;
  private pool: number[] = [];
  private weekdays: WeekdayOption[] = CourseFormat.weekdayOptions();
  private weekTypeItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '全部' },
    { text: '单周' },
    { text: '双周' },
    { text: '自定义' }
  ]);
  private weekNumbers: number[] = CourseFormat.weekNumbers();
  private colorModeItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '跟随色池' },
    { text: '自定义' }
  ]);
  private periodNumbers: number[] = CourseFormat.periodNumbers();

  private navStack(): NavPathStack {
    return resolveNavStack(this.stack, this.pageStack);
  }

  private isEditing(): boolean {
    return this.pageCourseId > 0;
  }

  // ---- 加载 ----

  private async load(): Promise<void> {
    try {
      this.pool = await ColorPool.get();
    } catch (err) {
      this.pool = [];
    }
    if (this.pageCourseId <= 0) {
      this.loading = false;
      return;
    }
    try {
      const course: Course | null = await CourseRepository.getById(this.pageCourseId);
      if (course === null) {
        this.loadFailed = true;
      } else {
        this.applyCourse(course);
      }
    } catch (err) {
      this.loadFailed = true;
    }
    this.loading = false;
  }

  private applyCourse(course: Course): void {
    this.loadedCourse = course;
    this.pageTableId = course.tableId > 0 ? course.tableId : this.pageTableId;
    this.name = course.name;
    this.classroom = course.classroom;
    this.teacher = course.teacher;
    this.info = course.info;
    this.testTime = course.testTime;
    this.testLocation = course.testLocation;

    this.freeTime = course.weekTime === 0;
    this.weekTime = course.weekTime > 0 ? course.weekTime : 1;
    this.startTime = CourseFormat.clampPeriod(course.startTime > 0 ? course.startTime : 1);
    const span: number = course.timeCount + 1;
    const maxSpan: number = LegacyConfig.MAX_CLASSES - this.startTime + 1;
    this.periodCount = Math.max(1, Math.min(span, maxSpan));

    const selection: WeekSelection = CourseFormat.fromWeeks(course.weeks);
    this.weekStart = selection.startWeek;
    this.weekEnd = selection.endWeek;
    this.weekType = selection.weekType;
    this.customWeeks = selection.customWeeks;

    const normalized: string = CourseFormat.normalizeHex(course.color);
    if (normalized !== '' && LegacyCourseColors.COLOR_LIST.indexOf(normalized) < 0) {
      this.customHex = normalized;
      this.colorValue = '';
      this.colorMode = 1;
    } else {
      this.customHex = '';
      this.colorValue = normalized;
      this.colorMode = normalized === '' ? 0 : 1;
    }
  }

  // ---- 周次 / 节次交互 ----

  private currentSelection(): WeekSelection {
    const selection: WeekSelection = new WeekSelection();
    selection.startWeek = this.weekStart;
    selection.endWeek = this.weekEnd;
    selection.weekType = this.weekType;
    selection.customWeeks = this.customWeeks;
    return selection;
  }

  private onWeekTypeSelect(index: number): void {
    this.weekType = index;
    if (index === LegacyConstant.DEFINED_WEEKS && this.customWeeks.length === 0) {
      const base: WeekSelection = this.currentSelection();
      base.weekType = LegacyConstant.FULL_WEEKS;
      this.customWeeks = CourseFormat.buildWeeks(base);
    }
  }

  private toggleCustomWeek(week: number): void {
    const next: number[] = this.customWeeks.slice();
    const index: number = next.indexOf(week);
    if (index >= 0) {
      next.splice(index, 1);
    } else {
      next.push(week);
    }
    this.customWeeks = next;
  }

  private selectAllWeeks(): void {
    this.customWeeks = this.weekNumbers.slice();
  }

  private clearCustomWeeks(): void {
    this.customWeeks = [];
  }

  private weeksSummaryText(): string {
    const weeks: number[] = CourseFormat.buildWeeks(this.currentSelection());
    return weeks.length === 0 ? '未选择周次' : WeeksFormat.describe(weeks);
  }

  private onStartPeriodSelect(period: number): void {
    this.startTime = CourseFormat.clampPeriod(period);
    const maxSpan: number = LegacyConfig.MAX_CLASSES - this.startTime + 1;
    if (this.periodCount > maxSpan) {
      this.periodCount = maxSpan;
    }
  }

  private spanChoices(): number[] {
    const maxSpan: number = LegacyConfig.MAX_CLASSES - this.startTime + 1;
    const spans: number[] = [];
    for (let span = 1; span <= maxSpan; span++) {
      spans.push(span);
    }
    return spans;
  }

  private periodPreviewText(): string {
    const end: number = this.startTime + this.periodCount - 1;
    return `第${this.startTime}-${end}节`;
  }

  private onWeekdaySelect(value: number): void {
    if (value === 0) {
      this.freeTime = true;
      return;
    }
    this.freeTime = false;
    this.weekTime = value;
  }

  private weekdayLabels(): string[] {
    const labels: string[] = [];
    for (let i = 0; i < this.weekdays.length; i++) {
      labels.push(this.weekdays[i].label);
    }
    return labels;
  }

  private currentWeekdayIndex(): number {
    if (this.freeTime) {
      return this.weekdays.length - 1;
    }
    for (let i = 0; i < this.weekdays.length; i++) {
      if (this.weekdays[i].value === this.weekTime) {
        return i;
      }
    }
    return 0;
  }

  private currentWeekdayLabel(): string {
    return this.weekdays[this.currentWeekdayIndex()].label;
  }

  private openWeekdayPicker(): void {
    this.getUIContext().showTextPickerDialog({
      range: this.weekdayLabels(),
      selected: this.currentWeekdayIndex(),
      canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const index: number = Array.isArray(result.index) ? result.index[0] : result.index as number;
        if (index >= 0 && index < this.weekdays.length) {
          this.onWeekdaySelect(this.weekdays[index].value);
        }
      }
    });
  }

  private openStartPeriodPicker(): void {
    const choices: string[] = [];
    for (let i = 0; i < this.periodNumbers.length; i++) {
      choices.push(`第${this.periodNumbers[i]}节`);
    }
    this.getUIContext().showTextPickerDialog({
      range: choices,
      selected: Math.max(0, this.periodNumbers.indexOf(this.startTime)),
      canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const index: number = Array.isArray(result.index) ? result.index[0] : result.index as number;
        if (index >= 0 && index < this.periodNumbers.length) {
          this.onStartPeriodSelect(this.periodNumbers[index]);
        }
      }
    });
  }

  private openSpanPicker(): void {
    const spans: number[] = this.spanChoices();
    const choices: string[] = [];
    for (let i = 0; i < spans.length; i++) {
      choices.push(`${spans[i]}节`);
    }
    this.getUIContext().showTextPickerDialog({
      range: choices,
      selected: Math.max(0, spans.indexOf(this.periodCount)),
      canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const index: number = Array.isArray(result.index) ? result.index[0] : result.index as number;
        if (index >= 0 && index < spans.length) {
          this.periodCount = spans[index];
        }
      }
    });
  }

  private weekChoices(): string[] {
    const choices: string[] = [];
    for (let i = 0; i < this.weekNumbers.length; i++) {
      choices.push(`第${this.weekNumbers[i]}周`);
    }
    return choices;
  }

  private openStartWeekPicker(): void {
    this.getUIContext().showTextPickerDialog({
      range: this.weekChoices(),
      selected: Math.max(0, this.weekNumbers.indexOf(this.weekStart)),
      canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const index: number = Array.isArray(result.index) ? result.index[0] : result.index as number;
        if (index >= 0 && index < this.weekNumbers.length) {
          const week: number = this.weekNumbers[index];
          this.weekStart = week;
          if (this.weekEnd < week) {
            this.weekEnd = week;
          }
        }
      }
    });
  }

  private openEndWeekPicker(): void {
    this.getUIContext().showTextPickerDialog({
      range: this.weekChoices(),
      selected: Math.max(0, this.weekNumbers.indexOf(this.weekEnd)),
      canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const index: number = Array.isArray(result.index) ? result.index[0] : result.index as number;
        if (index >= 0 && index < this.weekNumbers.length) {
          const week: number = this.weekNumbers[index];
          this.weekEnd = week;
          if (this.weekStart > week) {
            this.weekStart = week;
          }
        }
      }
    });
  }

  // ---- 颜色 ----

  private previewColor(): string {
    const custom: string = CourseFormat.normalizeHex(this.customHex);
    if (custom !== '') {
      return custom;
    }
    const selected: string = CourseFormat.normalizeHex(this.colorValue);
    if (selected !== '') {
      return selected;
    }
    if (this.pool.length > 0) {
      const index: number = this.pool[0];
      if (index >= 0 && index < LegacyCourseColors.COLOR_LIST.length) {
        return LegacyCourseColors.COLOR_LIST[index];
      }
    }
    return LegacyCourseColors.COLOR_LIST[0];
  }

  private onColorModeSelect(index: number): void {
    if (index === 0) {
      this.colorMode = 0;
      this.colorValue = '';
      this.customHex = '';
      return;
    }
    this.colorMode = 1;
    if (this.colorValue === '' && CourseFormat.normalizeHex(this.customHex) === '') {
      this.customHex = this.previewColor();
    }
  }

  // ---- 保存 ----

  private async save(): Promise<void> {
    if (this.saving) {
      return;
    }
    this.nameError = '';
    this.formError = '';

    const name: string = this.name.trim();
    if (name === '') {
      this.nameError = '课程名必填';
      this.formError = '请填写课程名';
      return;
    }

    // 自由时间课程不占节次：startTime / timeCount / weekTime 都落库为 0。
    let startTime: number = 0;
    let timeCount: number = 0;
    if (!this.freeTime) {
      if (this.weekTime < 1 || this.weekTime > 7) {
        this.formError = '请选择星期';
        return;
      }
      const endPeriod: number = this.startTime + this.periodCount - 1;
      if (this.startTime < 1 || this.startTime > LegacyConfig.MAX_CLASSES ||
        this.periodCount < 1 || endPeriod > LegacyConfig.MAX_CLASSES) {
        this.formError = `节次需在 1-${LegacyConfig.MAX_CLASSES} 节范围内`;
        return;
      }
      startTime = this.startTime;
      timeCount = this.periodCount - 1;
    }

    const weeks: number[] = CourseFormat.buildWeeks(this.currentSelection());
    if (weeks.length === 0) {
      if (this.weekType === LegacyConstant.DEFINED_WEEKS) {
        this.formError = '自定义周次至少选择一周';
      } else if (this.weekType === LegacyConstant.SINGLE_WEEKS ||
        this.weekType === LegacyConstant.DOUBLE_WEEKS) {
        this.formError = '当前起止周内没有符合单/双周的周次，请调整起止周';
      } else {
        this.formError = '周次不能为空';
      }
      return;
    }

    let color: string = '';
    const customInput: string = this.customHex.trim();
    if (customInput !== '') {
      const normalized: string = CourseFormat.normalizeHex(customInput);
      if (normalized === '') {
        this.formError = '自定义色值格式应为 #RRGGBB';
        return;
      }
      color = normalized;
    } else {
      color = CourseFormat.normalizeHex(this.colorValue);
    }

    const tableId: number = AppState.effectiveTableId(this.pageTableId);
    const source: Course | null = this.loadedCourse;
    const editing: boolean = this.isEditing() && source !== null;
    let course: Course;
    if (editing && source !== null) {
      course = source.clone();
    } else {
      course = new Course(name, tableId);
    }

    course.name = name;
    course.tableId = tableId;
    course.classroom = this.classroom.trim();
    course.teacher = this.teacher.trim();
    course.info = this.info;
    course.testTime = this.testTime.trim();
    course.testLocation = this.testLocation.trim();
    course.weeks = weeks;
    course.weekTime = this.freeTime ? 0 : this.weekTime;
    course.startTime = startTime;
    course.timeCount = timeCount;
    course.color = color;
    if (!editing) {
      course.importType = LegacyConstant.ADD_MANUALLY;
      course.courseId = -1;
    }

    // 旧版在写入课表前会提示时间冲突，这里保持同样的保护。
    if (course.weekTime > 0) {
      const conflicts: Course[] = await this.findConflicts(course, editing);
      if (conflicts.length > 0) {
        this.confirmConflict(course, editing, conflicts);
        return;
      }
    }
    await this.persistCourse(course, editing);
  }

  /** 同一天、课次区间重叠、且周次有交集的课程（排除自身）。 */
  private async findConflicts(course: Course, editing: boolean): Promise<Course[]> {
    try {
      const all: Course[] = await CourseRepository.getAll(course.tableId);
      const conflicts: Course[] = [];
      const start: number = course.startTime;
      const end: number = course.startTime + course.timeCount;
      for (let i = 0; i < all.length; i++) {
        const other: Course = all[i];
        if (editing && other.id === course.id) {
          continue;
        }
        if (other.weekTime !== course.weekTime) {
          continue;
        }
        const otherStart: number = other.startTime;
        const otherEnd: number = other.startTime + other.timeCount;
        if (start > otherEnd || otherStart > end) {
          continue;
        }
        let sameWeek: boolean = false;
        for (let w = 0; w < other.weeks.length; w++) {
          if (course.weeks.indexOf(other.weeks[w]) >= 0) {
            sameWeek = true;
            break;
          }
        }
        if (sameWeek) {
          conflicts.push(other);
        }
      }
      return conflicts;
    } catch (err) {
      return [];
    }
  }

  private confirmConflict(course: Course, editing: boolean, conflicts: Course[]): void {
    const names: string[] = [];
    for (let i = 0; i < conflicts.length && i < 3; i++) {
      names.push(`「${conflicts[i].name}」`);
    }
    const suffix: string = conflicts.length > 3 ? ` 等 ${conflicts.length} 门课` : '';
    Feedback.confirm(this.getUIContext(), '时间冲突', `与 ${names.join('、')}${suffix} 的上课时间重叠，仍要保存吗？`, '仍要保存', () => {
      this.persistCourse(course, editing);
    });
  }

  private async persistCourse(course: Course, editing: boolean): Promise<void> {
    if (this.saving) {
      return;
    }
    this.saving = true;
    try {
      let affected: number = 1;
      if (editing) {
        affected = await CourseRepository.update(course);
        if (affected <= 0) {
          throw new Error(`课程 ${course.id} 不存在，更新 0 行`);
        }
      } else {
        await CourseRepository.insert(course);
      }
      await AppState.bumpDataRevision();
      this.navStack().pop();
    } catch (err) {
      this.formError = editing ? '保存失败，请重试' : '添加失败，请重试';
    } finally {
      this.saving = false;
    }
  }

  // ---- UI ----

  @Builder
  basicSection() {
    FormSection({
      title: '基本信息'
    }) {
      Column() {
        CourseTextField({
          label: '课程名',
          placeholder: '如：高等数学',
          required: true,
          error: this.nameError,
          text: this.name,
          onTextChange: (value: string): void => {
            this.name = value;
          }
        })
        SettingsItemDivider({ startMargin: 12 })
        CourseTextField({
          label: '地点',
          placeholder: '如：仙Ⅰ-109',
          text: this.classroom,
          onTextChange: (value: string): void => {
            this.classroom = value;
          }
        })
        SettingsItemDivider({ startMargin: 12 })
        CourseTextField({
          label: '教师',
          placeholder: '如：李老师',
          text: this.teacher,
          onTextChange: (value: string): void => {
            this.teacher = value;
          }
        })
      }
      .width('100%')
    }
  }

  @Builder
  timeSection() {
    FormSection({
      title: '时间安排'
    }) {
      Column() {
        SettingsRow({
          title: '星期',
          trailingText: this.currentWeekdayLabel(),
          onTap: () => {
            this.openWeekdayPicker();
          }
        })
        if (!this.freeTime) {
          SettingsItemDivider({ startMargin: 12 })
          SettingsRow({
            title: '起始节',
            trailingText: `第${this.startTime}节`,
            onTap: () => {
              this.openStartPeriodPicker();
            }
          })
          SettingsItemDivider({ startMargin: 12 })
          SettingsRow({
            title: '节数',
            trailingText: `${this.periodCount}节`,
            onTap: () => {
              this.openSpanPicker();
            }
          })
          Text(`上课节次：${this.periodPreviewText()}`)
            .fontSize(FontSize.Caption)
            .fontColor(Colors.TextTertiary)
            .padding({ left: Spacing.Md, top: Spacing.Sm, bottom: Spacing.Sm })
        } else {
          Text('自由时间课程不占节次')
            .fontSize(FontSize.Caption)
            .fontColor(Colors.TextTertiary)
            .padding({ left: Spacing.Md, top: Spacing.Sm, bottom: Spacing.Sm })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  @Builder
  weekSection() {
    FormSection({
      title: '周次'
    }) {
      Column() {
        Row() {
          CapsuleSegmentButtonV2({
            items: this.weekTypeItems,
            selectedIndex: this.weekType,
            $selectedIndex: (index: number): void => {
              this.onWeekTypeSelect(index);
            },
            buttonBackgroundColor: ColorMetrics.resourceColor(Colors.SurfaceHigh),
            itemSelectedBackgroundColor: ColorMetrics.resourceColor(this.store.accentDisplay),
            itemFontColor: ColorMetrics.resourceColor(Colors.TextSecondary),
            itemSelectedFontColor: ColorMetrics.resourceColor(this.store.accentOn),
            itemFontSize: LengthMetrics.fp(FontSize.BodySm),
            itemSelectedFontSize: LengthMetrics.fp(FontSize.BodySm)
          })
        }
        .width('100%')
        .padding({ left: Spacing.Md, right: Spacing.Md, top: Spacing.Md, bottom: Spacing.Md })

        if (this.weekType === LegacyConstant.DEFINED_WEEKS) {
          Row({ space: Spacing.Lg }) {
            Text('全选')
              .fontSize(FontSize.BodySm)
              .fontColor(this.store.accentDisplay)
              .onClick(() => {
                this.selectAllWeeks();
              })
            Text('清空')
              .fontSize(FontSize.BodySm)
              .fontColor(Colors.TextSecondary)
              .onClick(() => {
                this.clearCustomWeeks();
              })
          }
          .width('100%')
          .padding({ left: Spacing.Md, right: Spacing.Md })

          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.weekNumbers, (week: number) => {
              SelectChip({
                label: `${week}`,
                selected: this.customWeeks.indexOf(week) >= 0,
                onSelect: () => {
                  this.toggleCustomWeek(week);
                }
              })
            }, (week: number) => `custom-week-${week}`)
          }
          .width('100%')
          .padding({ left: Spacing.Md, right: Spacing.Md, bottom: Spacing.Md })
        } else {
          SettingsRow({
            title: '起始周',
            trailingText: `第${this.weekStart}周`,
            onTap: () => {
              this.openStartWeekPicker();
            }
          })
          SettingsItemDivider({ startMargin: 12 })
          SettingsRow({
            title: '结束周',
            trailingText: `第${this.weekEnd}周`,
            onTap: () => {
              this.openEndWeekPicker();
            }
          })
        }

        Text(`上课周次：${this.weeksSummaryText()}`)
          .fontSize(FontSize.Caption)
          .fontColor(Colors.TextTertiary)
          .padding({ left: Spacing.Md, right: Spacing.Md, top: Spacing.Sm, bottom: Spacing.Md })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  colorSection() {
    FormSection({
      title: '颜色'
    }) {
      Column({ space: Spacing.Md }) {
        Row() {
          CapsuleSegmentButtonV2({
            items: this.colorModeItems,
            selectedIndex: this.colorMode,
            $selectedIndex: (index: number): void => {
              this.onColorModeSelect(index);
            },
            buttonBackgroundColor: ColorMetrics.resourceColor(Colors.SurfaceHigh),
            itemSelectedBackgroundColor: ColorMetrics.resourceColor(this.store.accentDisplay),
            itemFontColor: ColorMetrics.resourceColor(Colors.TextSecondary),
            itemSelectedFontColor: ColorMetrics.resourceColor(this.store.accentOn),
            itemFontSize: LengthMetrics.fp(FontSize.BodySm),
            itemSelectedFontSize: LengthMetrics.fp(FontSize.BodySm)
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.colorMode === 1) {
          CourseTextField({
            label: '自定义色值',
            placeholder: '#RRGGBB',
            text: this.customHex,
            showLeadingColor: true,
            leadingColor: CourseFormat.normalizeHex(this.customHex),
            onTextChange: (value: string): void => {
              this.colorMode = 1;
              this.customHex = value;
            }
          })
        }
      }
      .width('100%')
      .padding(Spacing.Md)
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  extraSection() {
    FormSection({
      title: '其他信息'
    }) {
      Column() {
        CourseTextField({
          label: '备注',
          placeholder: '课程说明、线上会议链接等',
          multiline: true,
          text: this.info,
          onTextChange: (value: string): void => {
            this.info = value;
          }
        })
        SettingsItemDivider({ startMargin: 12 })
        CourseTextField({
          label: '考试时间',
          placeholder: '如：2026-01-10 14:00',
          text: this.testTime,
          onTextChange: (value: string): void => {
            this.testTime = value;
          }
        })
        SettingsItemDivider({ startMargin: 12 })
        CourseTextField({
          label: '考试地点',
          placeholder: '如：逸夫楼 302',
          text: this.testLocation,
          onTextChange: (value: string): void => {
            this.testLocation = value;
          }
        })
      }
      .width('100%')
    }
  }

  @Builder
  formBody() {
    List({ space: Spacing.Md, scroller: this.scroller }) {
      if (this.formError !== '') {
        ListItem() {
          Text(this.formError)
            .fontSize(FontSize.Caption)
            .fontColor(Colors.Error)
            .width('100%')
            .padding({ left: Spacing.Md, right: Spacing.Md })
        }
      }
      ListItem() {
        this.basicSection()
      }
      ListItem() {
        this.timeSection()
      }
      ListItem() {
        this.weekSection()
      }
      ListItem() {
        this.colorSection()
      }
      ListItem() {
        this.extraSection()
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: 720 })
    .layoutWeight(1)
    .padding({
      left: Spacing.Md,
      right: Spacing.Md,
      top: HdsMetrics.contentTopInset(px2vp(this.store.windowTopInset)) + Spacing.Md,
      bottom: Spacing.Xl
    })
    .clip(false)
    .cachedCount(3, true)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  missingBody() {
    EmptyState({
      title: '课程不存在',
      description: '该课程可能已被删除，无法编辑',
      actionText: '返回',
      onAction: () => {
        this.navStack().pop();
      }
    })
  }

  private titleBarOptions(): HdsNavigationTitleBarOptions {
    const menu: HdsNavigationMenuContentOptions = {
      value: [{
        content: {
          icon: $r('sys.symbol.checkmark'),
          label: '保存',
          isEnabled: !this.saving,
          action: () => {
            this.save();
          }
        }
      }]
    };
    return hdsSubPageTitleBar(this.isEditing() ? '编辑课程' : '添加课程', '', menu);
  }

  build() {
    HdsNavDestination() {
      Column() {
        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(this.store.accentDisplay)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.loadFailed) {
          Column() {
            this.missingBody()
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          this.formBody()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.Background)
    }
    .titleBar(this.titleBarOptions())
    .bindToScrollable([this.scroller])
    .onReady((ctx: NavDestinationContext) => {
      this.stack = ctx.pathStack;
      const raw: Object | undefined = ctx.pathInfo.param as Object;
      if (raw instanceof CourseEditParam) {
        if (this.pageCourseId <= 0) {
          this.pageCourseId = raw.courseId;
        }
        if (this.pageTableId <= 0) {
          this.pageTableId = raw.tableId;
        }
      }
      this.load();
    })
  }
}
