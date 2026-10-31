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
import { Course } from '../../data/models/Models';
import { CourseRepository } from '../../data/CourseRepository';
import { ColorPool } from '../../data/ColorPool';
import { AppState } from '../../app/AppState';
import { LegacyConfig, LegacyConstant, LegacyCourseColors } from '../../common/Constants';
import { CourseEditParam } from '../../common/RouteParams';
import { Colors, FontSize, HdsMetrics, Radius, Spacing } from '../../common/design/Tokens';
import { hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import { EmptyState } from '../../common/ui/EmptyState';
import { WeeksFormat } from '../timetable/WeeksFormat';
import { CourseFormat, WeekdayOption, WeekSelection } from './CourseFormat';
import { AppStore } from '../../app/AppStore';
import { ColorSwatch, CourseTextField, FormSection, SelectChip, StepperRow } from './CourseFormParts';

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
  private weekTypeLabels: string[] = ['全部', '单周', '双周', '自定义'];
  private weekNumbers: number[] = CourseFormat.weekNumbers();
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
    } else {
      this.customHex = '';
      this.colorValue = normalized;
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

  private adjustWeekStart(delta: number): void {
    const next: number = CourseFormat.clampWeek(this.weekStart + delta);
    this.weekStart = next;
    if (this.weekEnd < next) {
      this.weekEnd = next;
    }
  }

  private adjustWeekEnd(delta: number): void {
    const next: number = CourseFormat.clampWeek(this.weekEnd + delta);
    this.weekEnd = next;
    if (this.weekStart > next) {
      this.weekStart = next;
    }
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

  private isWeekdaySelected(value: number): boolean {
    if (value === 0) {
      return this.freeTime;
    }
    return !this.freeTime && this.weekTime === value;
  }

  private onWeekdaySelect(value: number): void {
    if (value === 0) {
      this.freeTime = true;
      return;
    }
    this.freeTime = false;
    this.weekTime = value;
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

  private isFollowPool(): boolean {
    return this.colorValue === '' && CourseFormat.normalizeHex(this.customHex) === '';
  }

  private randomizeColor(): void {
    this.colorValue = CourseFormat.randomPoolColor();
    this.customHex = '';
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
      title: '基本信息',
      caption: '课程名必填，教师 / 地点可稍后补充'
    }) {
      Column({ space: Spacing.Md }) {
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
        CourseTextField({
          label: '地点',
          placeholder: '如：仙Ⅰ-109',
          text: this.classroom,
          onTextChange: (value: string): void => {
            this.classroom = value;
          }
        })
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
      title: '时间安排',
      caption: '自由时间课程不占节次，只在课程列表里展示'
    }) {
      Column({ space: Spacing.Sm }) {
        Text('星期')
          .fontSize(FontSize.Caption)
          .fontColor(Colors.TextSecondary)
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.weekdays, (option: WeekdayOption) => {
            SelectChip({
              label: option.label,
              selected: this.isWeekdaySelected(option.value),
              onSelect: () => {
                this.onWeekdaySelect(option.value);
              }
            })
          }, (option: WeekdayOption) => `weekday-${option.value}`)
        }
        .width('100%')

        if (!this.freeTime) {
          Text('起始节')
            .fontSize(FontSize.Caption)
            .fontColor(Colors.TextSecondary)
            .margin({ top: Spacing.Xs })
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.periodNumbers, (period: number) => {
              SelectChip({
                label: `${period}`,
                selected: this.startTime === period,
                onSelect: () => {
                  this.onStartPeriodSelect(period);
                }
              })
            }, (period: number) => `period-${period}`)
          }
          .width('100%')

          Text('节数')
            .fontSize(FontSize.Caption)
            .fontColor(Colors.TextSecondary)
            .margin({ top: Spacing.Xs })
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.spanChoices(), (span: number) => {
              SelectChip({
                label: `${span}节`,
                selected: this.periodCount === span,
                onSelect: () => {
                  this.periodCount = span;
                }
              })
            }, (span: number) => `span-${span}`)
          }
          .width('100%')

          Text(`上课节次：${this.periodPreviewText()}`)
            .fontSize(FontSize.Caption)
            .fontColor(Colors.TextTertiary)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  @Builder
  weekSection() {
    FormSection({
      title: '周次',
      caption: '「全部」= 起止周内每周都上；单 / 双周按起止周筛选；自定义逐周勾选'
    }) {
      Column({ space: Spacing.Sm }) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.weekTypeLabels, (label: string, index: number) => {
            SelectChip({
              label: label,
              selected: this.weekType === index,
              onSelect: () => {
                this.onWeekTypeSelect(index);
              }
            })
          }, (label: string, index: number) => `week-type-${index}`)
        }
        .width('100%')

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
        } else {
          StepperRow({
            label: '起始周',
            valueText: `${this.weekStart}周`,
            canDecrease: this.weekStart > 1,
            canIncrease: this.weekStart < LegacyConfig.MAX_WEEKS,
            onDecrease: () => {
              this.adjustWeekStart(-1);
            },
            onIncrease: () => {
              this.adjustWeekStart(1);
            }
          })
          StepperRow({
            label: '结束周',
            valueText: `${this.weekEnd}周`,
            canDecrease: this.weekEnd > 1,
            canIncrease: this.weekEnd < LegacyConfig.MAX_WEEKS,
            onDecrease: () => {
              this.adjustWeekEnd(-1);
            },
            onIncrease: () => {
              this.adjustWeekEnd(1);
            }
          })
        }

        Text(`上课周次：${this.weeksSummaryText()}`)
          .fontSize(FontSize.Caption)
          .fontColor(Colors.TextTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  @Builder
  colorSection() {
    FormSection({
      title: '颜色',
      caption: '默认按课程从色池取色（同门课颜色一致）；也可挑色、随机或自定义'
    }) {
      Column({ space: Spacing.Sm }) {
        Row({ space: Spacing.Md }) {
          Column()
            .width(28)
            .height(28)
            .borderRadius(Radius.Round)
            .backgroundColor(this.previewColor())
            .border({ width: 1, color: Colors.Outline })
          SelectChip({
            label: '跟随色池',
            selected: this.isFollowPool(),
            onSelect: () => {
              this.colorValue = '';
              this.customHex = '';
            }
          })
          Text('随机')
            .fontSize(FontSize.BodySm)
            .fontColor(this.store.accentDisplay)
            .padding({ left: Spacing.Sm, right: Spacing.Sm, top: Spacing.Xs, bottom: Spacing.Xs })
            .onClick(() => {
              this.randomizeColor();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(LegacyCourseColors.COLOR_LIST, (color: string, index: number) => {
            ColorSwatch({
              color: color,
              selected: this.colorValue === color && CourseFormat.normalizeHex(this.customHex) === '',
              onSelect: () => {
                this.colorValue = color;
                this.customHex = '';
              }
            })
          }, (color: string, index: number) => `swatch-${index}`)
        }
        .width('100%')

        CourseTextField({
          label: '自定义色值',
          placeholder: '#RRGGBB（可选，优先于上方选择）',
          text: this.customHex,
          onTextChange: (value: string): void => {
            this.customHex = value;
          }
        })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  @Builder
  extraSection() {
    FormSection({
      title: '其他信息',
      caption: '备注与考试信息会在课程详情页展示'
    }) {
      Column({ space: Spacing.Md }) {
        CourseTextField({
          label: '备注',
          placeholder: '课程说明、线上会议链接等',
          multiline: true,
          text: this.info,
          onTextChange: (value: string): void => {
            this.info = value;
          }
        })
        CourseTextField({
          label: '考试时间',
          placeholder: '如：2026-01-10 14:00',
          text: this.testTime,
          onTextChange: (value: string): void => {
            this.testTime = value;
          }
        })
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
    Column() {
      Scroll(this.scroller) {
        Row() {
          Column({ space: Spacing.Lg }) {
            if (this.formError !== '') {
              Text(this.formError)
                .fontSize(FontSize.Caption)
                .fontColor(Colors.Error)
                .width('100%')
            }
            this.basicSection()
            this.timeSection()
            this.weekSection()
            this.colorSection()
            this.extraSection()
          }
          .width('100%')
          .constraintSize({ maxWidth: 720 })
          .padding({
            left: Spacing.Lg,
            right: Spacing.Lg,
            // HdsNavDestination 的标题栏覆盖在内容上：让出标题栏高度，避免表单被标题压住。
            top: HdsMetrics.contentTopInset(px2vp(this.store.windowTopInset)) + Spacing.Lg,
            bottom: Spacing.Xl
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .layoutWeight(1)
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
