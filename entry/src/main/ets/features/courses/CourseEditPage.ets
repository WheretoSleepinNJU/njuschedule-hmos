/**
 * 添加 / 编辑课程页（路由名 `course-edit`，参数 `CourseEditParam`）。
 *
 * 页面把「同一门课的多行 Course」当作一个整体编辑（上游 Flutter `EditCourseView`）：
 * - 课程级字段（名称 / 信息 / 考试时间 / 考试地点 / 链接 / 颜色）由所有时段共享；
 * - 时段列表每个时段独立编辑教师、教室、周次、星期与节次，可展开/折叠、增删；
 * - 编辑模式：先 `getById(rowId)` 读到路由指定的行，再 `getMeetings` 取回整组；
 * - 新增模式：默认一个空时段，可继续添加多个；
 * - 保存：`CourseRepository.saveMeetingGroup(originals, meetings)` 整组事务写入，
 *   成功后 `await AppState.bumpDataRevision()` 再 pop；失败留在页面显示错误；
 * - 删除：编辑模式标题栏保留删除入口，`AppState.deleteCourseGroup(originals)` 整组删除。
 *
 * 校验：课程名必填；每个时段周次非空；非待定时星期 1-7、节次在 1-13 节范围内；
 * 自定义色值必须为 `#RRGGBB`。保存前沿用旧版的时间冲突确认（跨全部时段）。
 *
 * 时段草稿模型见 `CourseMeetingDraft.ets`（V2 `@ObservedV2` + `@Trace`）。
 */
import { resolveNavStack } from '../../common/NavStackResolver';
import { Feedback } from '../../common/ui/Feedback';
import {
  HdsNavDestination,
  HdsNavigationMenuContentOptions,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitleBarOptions
} from '@kit.UIDesignKit';
import {
  CapsuleSegmentButtonV2,
  ColorMetrics,
  LengthMetrics,
  SegmentButtonV2Items,
  SymbolGlyphModifier
} from '@kit.ArkUI';
import { Course } from '../../data/models/Models';
import { CourseRepository } from '../../data/CourseRepository';
import { ColorPool } from '../../data/ColorPool';
import { AppState } from '../../app/AppState';
import { ScheduleModel } from '../../data/ScheduleModel';
import { LegacyConfig, LegacyConstant, LegacyCourseColors } from '../../common/Constants';
import { CourseEditParam } from '../../common/RouteParams';
import { Colors, FontSize, HdsMetrics, Radius, Spacing } from '../../common/design/Tokens';
import { hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import { EmptyState } from '../../common/ui/EmptyState';
import { CourseFormat } from './CourseFormat';
import { AppStore } from '../../app/AppStore';
import { CourseTextField, FormSection } from './CourseFormParts';
import { SettingsItemDivider, SettingsRow, SettingsSwitchRow } from '../../common/ui/SettingsListItems';
import { applyTextPickerAccent } from '../../common/ui/TextPickerStyle';
import { CourseMeetingDraft } from './CourseMeetingDraft';

// ---------------------------------------------------------------------------
// 模块级只读数据：星期 / 周次 / 节次标签与分段按钮配置（所有时段卡片共用语义）。
// ---------------------------------------------------------------------------

/** 周一至周日（下标与 LegacyConstant.WEEK_WITH_BIAS 的 1-7 对齐）。 */
function buildDayLabels(): string[] {
  const labels: string[] = [];
  for (let day = 1; day <= 7; day++) {
    labels.push(LegacyConstant.WEEK_WITH_BIAS[day]);
  }
  return labels;
}

function buildWeekLabels(): string[] {
  const labels: string[] = [];
  for (let week = 1; week <= LegacyConfig.MAX_WEEKS; week++) {
    labels.push(`第${week}周`);
  }
  return labels;
}

function buildPeriodLabels(): string[] {
  const labels: string[] = [];
  for (let period = 1; period <= LegacyConfig.MAX_CLASSES; period++) {
    labels.push(`第${period}节`);
  }
  return labels;
}

/** 周次选择分段按钮（全部 / 单周 / 双周 / 自定义）；每个卡片独立实例。 */
function buildWeekTypeItems(): SegmentButtonV2Items {
  return new SegmentButtonV2Items([
    { text: '全部' },
    { text: '单周' },
    { text: '双周' },
    { text: '自定义' }
  ]);
}

const DAY_LABELS: string[] = buildDayLabels();
const WEEK_LABELS: string[] = buildWeekLabels();
const PERIOD_LABELS: string[] = buildPeriodLabels();

// ---------------------------------------------------------------------------
// 单个时段编辑卡片（展开 / 折叠 + 时段级字段）。
// ---------------------------------------------------------------------------

/**
 * 时段卡片：标题行显示「时段 N + 时间摘要」，点标题行或箭头展开/折叠；
 * 剩余多个时段时右上角提供删除入口（至少保留一个）。
 *
 * 状态全部落在 `@Param draft`（`@ObservedV2` 对象）上，卡片本身不持有表单状态，
 * 因此增删时段、切换展开时不会丢草稿；父页面负责校验与保存。
 */
@ComponentV2
struct CourseMeetingCard {
  @Local store: AppStore = AppStore.connect();
  @Param draft: CourseMeetingDraft = new CourseMeetingDraft();
  @Event onRemove: () => void = () => {
  };

  private weekTypeItems: SegmentButtonV2Items = buildWeekTypeItems();
  private weekNumbers: number[] = CourseFormat.weekNumbers();

  private toggleExpanded(): void {
    // 按官方「折叠展开动效」示例：显式动画驱动折叠状态，卡片本身 clip 裁剪高度变化。
    this.getUIContext().animateTo({
      duration: 300,
      curve: Curve.Smooth
    }, () => {
      this.draft.expanded = !this.draft.expanded;
    });
  }

  /** 结束节选项从当前起始节开始，保证「结束节 >= 开始节」。 */
  private endChoices(): string[] {
    const labels: string[] = [];
    for (let period = this.draft.start; period <= LegacyConfig.MAX_CLASSES; period++) {
      labels.push(PERIOD_LABELS[period - 1]);
    }
    return labels;
  }

  private openDayPicker(): void {
    this.getUIContext().showTextPickerDialog(applyTextPickerAccent(this.store, {
      range: DAY_LABELS,
      selected: Math.max(0, this.draft.day - 1),
      canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const index: number = Array.isArray(result.index) ? result.index[0] : result.index as number;
        if (index >= 0 && index < DAY_LABELS.length) {
          this.draft.setDay(index + 1);
        }
      }
    }));
  }

  private openStartPeriodPicker(): void {
    this.getUIContext().showTextPickerDialog(applyTextPickerAccent(this.store, {
      range: PERIOD_LABELS,
      selected: Math.max(0, this.draft.start - 1),
      canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const index: number = Array.isArray(result.index) ? result.index[0] : result.index as number;
        if (index >= 0 && index < PERIOD_LABELS.length) {
          this.draft.setStart(index + 1);
        }
      }
    }));
  }

  private openEndPeriodPicker(): void {
    const labels: string[] = this.endChoices();
    this.getUIContext().showTextPickerDialog(applyTextPickerAccent(this.store, {
      range: labels,
      selected: Math.max(0, this.draft.end - this.draft.start),
      canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const index: number = Array.isArray(result.index) ? result.index[0] : result.index as number;
        if (index >= 0 && index < labels.length) {
          this.draft.setEnd(this.draft.start + index);
        }
      }
    }));
  }

  private openStartWeekPicker(): void {
    this.getUIContext().showTextPickerDialog(applyTextPickerAccent(this.store, {
      range: WEEK_LABELS,
      selected: Math.max(0, this.draft.weekStart - 1),
      canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const index: number = Array.isArray(result.index) ? result.index[0] : result.index as number;
        if (index >= 0 && index < WEEK_LABELS.length) {
          this.draft.setWeekStart(index + 1);
        }
      }
    }));
  }

  private openEndWeekPicker(): void {
    this.getUIContext().showTextPickerDialog(applyTextPickerAccent(this.store, {
      range: WEEK_LABELS,
      selected: Math.max(0, this.draft.weekEnd - 1),
      canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const index: number = Array.isArray(result.index) ? result.index[0] : result.index as number;
        if (index >= 0 && index < WEEK_LABELS.length) {
          this.draft.setWeekEnd(index + 1);
        }
      }
    }));
  }

  @Builder
  private cardHeader() {
    Row({ space: Spacing.Sm }) {
      Column({ space: 2 }) {
        Text(`时段 ${this.draft.order + 1}`)
          .fontSize(FontSize.Body)
          .fontColor(Colors.TextPrimary)
        Text(this.draft.timeSummary())
          .fontSize(FontSize.BodySm)
          .fontColor(Colors.TextTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .onClick(() => {
        this.toggleExpanded();
      })

      if (this.draft.removable) {
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([Colors.TextTertiary])
        }
        .width(36)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .borderRadius(Radius.Round)
        .onClick(() => {
          this.onRemove();
        })
      }

      Row() {
        Image($r('sys.media.ohos_ic_public_arrow_right'))
          .width(12)
          .height(24)
          .fillColor(Colors.TextTertiary)
          .rotate({ angle: this.draft.expanded ? 90 : 0 })
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.toggleExpanded();
      })
    }
    .width('100%')
    .padding({ left: Spacing.Md, right: Spacing.Sm, top: Spacing.Sm, bottom: Spacing.Sm })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private weekEditor() {
    Text('周次')
      .fontSize(FontSize.Body)
      .fontColor(Colors.TextSecondary)
      .width('100%')
      .padding({ left: Spacing.Md, right: Spacing.Md, top: Spacing.Md })

    Row() {
      CapsuleSegmentButtonV2({
        items: this.weekTypeItems,
        selectedIndex: this.draft.weekType,
        $selectedIndex: (index: number): void => {
          this.draft.onWeekTypeSelect(index);
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
    .padding({ left: Spacing.Md, right: Spacing.Md, top: Spacing.Sm, bottom: Spacing.Sm })

    if (this.draft.weekType === LegacyConstant.DEFINED_WEEKS) {
      Row({ space: Spacing.Sm }) {
        Button('全选')
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .controlSize(ControlSize.SMALL)
          .fontSize(FontSize.BodySm)
          .fontColor(this.store.accentDisplay)
          .onClick(() => {
            this.draft.selectAllWeeks();
          })
        Button('清空')
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .controlSize(ControlSize.SMALL)
          .fontSize(FontSize.BodySm)
          .fontColor(Colors.TextSecondary)
          .onClick(() => {
            this.draft.clearWeeks();
          })
      }
      .width('100%')
      .padding({ left: Spacing.Md, right: Spacing.Md })

      Grid() {
        ForEach(this.weekNumbers, (week: number) => {
          GridItem() {
            Text(`${week}`)
              .fontSize(FontSize.Body)
              .fontColor(this.draft.customWeeks.indexOf(week) >= 0 ?
                this.store.accentOn : Colors.TextPrimary)
              .width('100%')
              .height(44)
              .textAlign(TextAlign.Center)
              .backgroundColor(this.draft.customWeeks.indexOf(week) >= 0 ?
                this.store.accentDisplay : Colors.SurfaceHigh)
              .borderRadius(Radius.Md)
              .onClick(() => {
                this.draft.toggleWeek(week);
              })
          }
        }, (week: number) => `meeting-week-${this.draft.key}-${week}`)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
      .columnsGap(Spacing.Sm)
      .rowsGap(Spacing.Sm)
      .width('100%')
      .height(5 * 44 + 4 * Spacing.Sm)
      .padding({ left: Spacing.Md, right: Spacing.Md, bottom: Spacing.Sm })
    } else {
      SettingsRow({
        title: '起始周',
        trailingText: `第${this.draft.weekStart}周`,
        onTap: () => {
          this.openStartWeekPicker();
        }
      })
      SettingsItemDivider({ startMargin: 12 })
      SettingsRow({
        title: '结束周',
        trailingText: `第${this.draft.weekEnd}周`,
        onTap: () => {
          this.openEndWeekPicker();
        }
      })
    }

    Text(`上课周次：${this.draft.weekSummary()}`)
      .fontSize(FontSize.Caption)
      .fontColor(Colors.TextTertiary)
      .width('100%')
      .padding({ left: Spacing.Md, right: Spacing.Md, top: Spacing.Sm, bottom: Spacing.Md })

    if (this.draft.weekError) {
      Text('至少选择一周')
        .fontSize(FontSize.Caption)
        .fontColor(Colors.Error)
        .width('100%')
        .padding({ left: Spacing.Md, right: Spacing.Md, bottom: Spacing.Md })
    }
  }

  @Builder
  private cardBody() {
    Column() {
      CourseTextField({
        label: '教师',
        placeholder: '如：李老师',
        text: this.draft.teacher,
        onTextChange: (value: string): void => {
          this.draft.teacher = value;
        }
      })
      SettingsItemDivider({ startMargin: 12 })
      CourseTextField({
        label: '教室',
        placeholder: '如：仙Ⅰ-109',
        text: this.draft.classroom,
        onTextChange: (value: string): void => {
          this.draft.classroom = value;
        }
      })
      SettingsItemDivider({ startMargin: 12 })

      this.weekEditor()

      SettingsItemDivider({ startMargin: 12 })
      SettingsSwitchRow({
        title: '时间待定',
        subtitle: '自由时间课程不占用节次',
        isOn: this.draft.pending,
        onToggle: (isOn: boolean): void => {
          this.draft.pending = isOn;
        }
      })

      if (!this.draft.pending) {
        SettingsItemDivider({ startMargin: 12 })
        SettingsRow({
          title: '星期',
          trailingText: LegacyConstant.WEEK_WITH_BIAS[this.draft.day],
          onTap: () => {
            this.openDayPicker();
          }
        })
        SettingsItemDivider({ startMargin: 12 })
        SettingsRow({
          title: '开始节次',
          trailingText: `第${this.draft.start}节`,
          onTap: () => {
            this.openStartPeriodPicker();
          }
        })
        SettingsItemDivider({ startMargin: 12 })
        SettingsRow({
          title: '结束节次',
          trailingText: `第${this.draft.end}节`,
          onTap: () => {
            this.openEndPeriodPicker();
          }
        })
        Text(this.draft.timeSummary())
          .fontSize(FontSize.Caption)
          .fontColor(Colors.TextTertiary)
          .width('100%')
          .padding({ left: Spacing.Md, right: Spacing.Md, top: Spacing.Sm })
      }
    }
    .width('100%')
    .padding({ bottom: Spacing.Xs })
  }

  build() {
    Column() {
      this.cardHeader()
      if (this.draft.expanded) {
        Divider()
          .strokeWidth(1)
          .color(Colors.OutlineLight)
          .margin({ left: Spacing.Md, right: Spacing.Md })
        this.cardBody()
      }
    }
    .width('100%')
    .backgroundColor(Colors.Surface)
    .borderRadius(Radius.Xxl)
    .clip(true)
  }
}

// ---------------------------------------------------------------------------
// 课程编辑页。
// ---------------------------------------------------------------------------

@ComponentV2
export struct CourseEditPage {
  /** V2 全局 Store（主题色 / 避让区）。 */
  @Local store: AppStore = AppStore.connect();
  /** 外壳显式传入的课程 id；0 表示新增。 */
  /** 外壳可选传入的导航栈；正常走 onReady 里的 pathStack。 */
  @Param pageStack: NavPathStack = new NavPathStack();
  /** 本地承接的路由参数（@Param 不可回写）。 */
  @Local pageTableId: number = 0;
  @Local pageCourseId: number = 0;

  // ---- 课程级表单状态（所有时段共享） ----
  @Local name: string = '';
  @Local info: string = '';
  @Local testTime: string = '';
  @Local testLocation: string = '';
  @Local link: string = '';
  @Local colorValue: string = '';
  @Local customHex: string = '';
  @Local colorMode: number = 0;

  // ---- 时段列表与页面状态 ----
  @Local meetings: CourseMeetingDraft[] = [];
  @Local nameError: string = '';
  @Local formError: string = '';
  @Local saving: boolean = false;
  @Local loading: boolean = true;
  @Local loadFailed: boolean = false;

  private stack: NavPathStack | null = null;
  private scroller: Scroller = new Scroller();
  /** 打开页面时从库里读到的整组原始行（只读快照，用于 save / delete 的一致性校验）。 */
  private originals: Course[] = [];
  /** 打开页面时的课程级字段基线；未修改时保留各历史行自己的值。 */
  private initialInfo: string = '';
  private initialTestTime: string = '';
  private initialTestLocation: string = '';
  private initialLink: string = '';
  private pool: number[] = [];
  private serial: number = 0;
  private colorModeItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '跟随色池' },
    { text: '自定义' }
  ]);

  private navStack(): NavPathStack {
    return resolveNavStack(this.stack, this.pageStack);
  }

  private isEditing(): boolean {
    return this.pageCourseId > 0;
  }

  private nextKey(): number {
    const key: number = this.serial;
    this.serial += 1;
    return key;
  }

  // ---- 加载 ----

  private async load(): Promise<void> {
    try {
      this.pool = await ColorPool.get();
    } catch (err) {
      this.pool = [];
    }
    if (this.pageCourseId <= 0) {
      // 新增：默认一个空时段（周次全选、周一第 1 节）。
      this.addMeetingDraft();
      this.loading = false;
      return;
    }
    try {
      const course: Course | null = await CourseRepository.getById(this.pageCourseId);
      if (course === null) {
        this.loadFailed = true;
      } else {
        const meetings: Course[] = await CourseRepository.getMeetings(course);
        if (meetings.length === 0) {
          this.loadFailed = true;
        } else {
          this.applyGroup(meetings);
        }
      }
    } catch (err) {
      this.loadFailed = true;
    }
    this.loading = false;
  }

  /** 回填整组时段（课程级字段取第一行；路由指定的那一行默认展开）。 */
  private applyGroup(meetings: Course[]): void {
    const ordered: Course[] = meetings.slice();
    ordered.sort((a: Course, b: Course): number => CourseFormat.compareSession(a, b));
    this.originals = ordered;
    const head: Course = ordered[0];
    this.pageTableId = head.tableId > 0 ? head.tableId : this.pageTableId;
    this.name = head.name;
    this.info = head.info;
    this.testTime = head.testTime;
    this.testLocation = head.testLocation;
    this.link = head.link;
    this.initialInfo = head.info;
    this.initialTestTime = head.testTime;
    this.initialTestLocation = head.testLocation;
    this.initialLink = head.link;
    this.applyColor(head.color);

    let focus: number = -1;
    for (let i = 0; i < ordered.length; i++) {
      if (ordered[i].id === this.pageCourseId) {
        focus = i;
        break;
      }
    }
    if (focus < 0) {
      focus = 0;
    }
    const drafts: CourseMeetingDraft[] = [];
    for (let i = 0; i < ordered.length; i++) {
      drafts.push(CourseMeetingDraft.fromCourse(this.nextKey(), ordered[i], i === focus));
    }
    this.meetings = drafts;
    this.syncMeetingOrder();
  }

  private applyColor(color: string): void {
    const normalized: string = CourseFormat.normalizeHex(color);
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

  // ---- 时段增删 ----

  private addMeetingDraft(): void {
    if (this.saving) {
      return;
    }
    const next: CourseMeetingDraft[] = this.meetings.slice();
    let draft: CourseMeetingDraft;
    if (next.length === 0) {
      draft = CourseMeetingDraft.blank(this.nextKey());
    } else {
      draft = CourseMeetingDraft.copyOf(this.nextKey(), next[next.length - 1]);
    }
    next.push(draft);
    this.meetings = next;
    this.syncMeetingOrder();
  }

  private removeMeetingDraft(target: CourseMeetingDraft): void {
    if (this.saving || this.meetings.length <= 1) {
      return;
    }
    const next: CourseMeetingDraft[] = [];
    for (let i = 0; i < this.meetings.length; i++) {
      if (this.meetings[i].key !== target.key) {
        next.push(this.meetings[i]);
      }
    }
    this.meetings = next;
    this.syncMeetingOrder();
  }

  /** 列表变化后重排序号 / 删除入口可见性（卡片通过 @Trace 字段自动刷新）。 */
  private syncMeetingOrder(): void {
    for (let i = 0; i < this.meetings.length; i++) {
      this.meetings[i].order = i;
      this.meetings[i].removable = this.meetings.length > 1;
    }
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
    if (this.saving || this.loading || this.loadFailed) {
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
    if (this.meetings.length === 0) {
      this.formError = '请至少添加一个时段';
      return;
    }

    // 逐时段校验：周次非空；非待定时星期 / 节次合法。展开出错的卡片方便直接修改。
    let invalid: boolean = false;
    for (let i = 0; i < this.meetings.length; i++) {
      const draft: CourseMeetingDraft = this.meetings[i];
      draft.weekError = false;
      let bad: boolean = false;
      if (draft.weeks().length === 0) {
        draft.weekError = true;
        bad = true;
      }
      if (!draft.isTimeValid()) {
        bad = true;
      }
      if (bad) {
        draft.expanded = true;
        invalid = true;
      }
    }
    if (invalid) {
      this.formError = '请检查各时段的周次与时间设置';
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

    const tableId: number = this.pageTableId > 0 ? this.pageTableId : AppState.effectiveTableId(0);
    const meetings: Course[] = this.buildMeetings(name, color, tableId);

    // 查冲突期间置 saving，避免连点「保存」重复提交。
    this.saving = true;
    let conflicts: Course[] = [];
    try {
      conflicts = await this.findConflicts(meetings, tableId);
    } finally {
      this.saving = false;
    }
    if (conflicts.length > 0) {
      this.confirmConflict(meetings, conflicts);
      return;
    }
    await this.persistGroup(meetings);
  }

  /**
   * 生成待落库的整组时段行：
   * - 已有行 `original.clone()` 派生并保留 id；新增行用组内第一行（模板）派生，id = 0；
   * - 课程级字段写进每一行；时段级字段来自草稿；
   * - 全新课程统一 `importType = ADD_MANUALLY`、`courseId = -1`（数据层负责分配同组 courseId）。
   */
  private buildMeetings(name: string, color: string, tableId: number): Course[] {
    const result: Course[] = [];
    const template: Course | null = this.originals.length > 0 ? this.originals[0] : null;
    const info: string = this.info;
    const testTime: string = this.testTime.trim();
    const testLocation: string = this.testLocation.trim();
    const link: string = this.link.trim();
    const infoChanged: boolean = info !== this.initialInfo;
    const testTimeChanged: boolean = testTime !== this.initialTestTime;
    const testLocationChanged: boolean = testLocation !== this.initialTestLocation;
    const linkChanged: boolean = link !== this.initialLink;
    for (let i = 0; i < this.meetings.length; i++) {
      const draft: CourseMeetingDraft = this.meetings[i];
      const original: Course | null = draft.original;
      let course: Course;
      if (original !== null) {
        course = original.clone();
      } else if (template !== null) {
        course = template.clone();
      } else {
        course = new Course(name, tableId);
      }
      course.id = original !== null ? original.id : 0;
      course.tableId = tableId;
      course.name = name;
      if (original === null || infoChanged) {
        course.info = info;
      }
      if (original === null || testTimeChanged) {
        course.testTime = testTime;
      }
      if (original === null || testLocationChanged) {
        course.testLocation = testLocation;
      }
      if (original === null || linkChanged) {
        course.link = link;
      }
      course.color = color;
      if (original === null && template === null) {
        course.importType = LegacyConstant.ADD_MANUALLY;
        course.courseId = -1;
        course.classNumber = '';
      }
      course.teacher = draft.teacher.trim();
      course.classroom = draft.classroom.trim();
      course.weeks = draft.weeks();
      course.weekTime = draft.pending ? 0 : draft.day;
      course.startTime = draft.pending ? 0 : draft.start;
      course.timeCount = draft.pending ? 0 : draft.end - draft.start;
      result.push(course);
    }
    return result;
  }

  /** 全部时段与表内其他课程（排除本组）的同日节次 + 周次重叠检查。 */
  private async findConflicts(meetings: Course[], tableId: number): Promise<Course[]> {
    try {
      const all: Course[] = await CourseRepository.getAll(tableId);
      const originalIds: number[] = [];
      for (let i = 0; i < this.originals.length; i++) {
        originalIds.push(this.originals[i].id);
      }
      const conflicts: Course[] = [];
      for (let i = 0; i < meetings.length; i++) {
        const meeting: Course = meetings[i];
        if (meeting.weekTime <= 0) {
          continue;
        }
        for (let j = 0; j < all.length; j++) {
          const other: Course = all[j];
          if (originalIds.indexOf(other.id) >= 0) {
            continue;
          }
          if (!ScheduleModel.checkIfOverlapping(meeting, other)) {
            continue;
          }
          let sameWeek: boolean = false;
          for (let w = 0; w < other.weeks.length; w++) {
            if (meeting.weeks.indexOf(other.weeks[w]) >= 0) {
              sameWeek = true;
              break;
            }
          }
          if (!sameWeek) {
            continue;
          }
          let exists: boolean = false;
          for (let k = 0; k < conflicts.length; k++) {
            if (conflicts[k].id === other.id) {
              exists = true;
              break;
            }
          }
          if (!exists) {
            conflicts.push(other);
          }
        }
      }
      return conflicts;
    } catch (err) {
      // 冲突检查失败不阻塞保存（与旧版一致：查不到就当无冲突）。
      return [];
    }
  }

  private confirmConflict(meetings: Course[], conflicts: Course[]): void {
    const names: string[] = [];
    for (let i = 0; i < conflicts.length && i < 3; i++) {
      names.push(`「${conflicts[i].name}」`);
    }
    const suffix: string = conflicts.length > 3 ? ` 等 ${conflicts.length} 门课` : '';
    Feedback.confirm(this.getUIContext(), '时间冲突',
      `与 ${names.join('、')}${suffix} 的上课时间重叠，仍要保存吗？`, '仍要保存', () => {
        this.persistGroup(meetings);
      });
  }

  private async persistGroup(meetings: Course[]): Promise<void> {
    if (this.saving) {
      return;
    }
    this.saving = true;
    try {
      const saved: boolean = await CourseRepository.saveMeetingGroup(this.originals, meetings);
      if (!saved) {
        this.formError = '保存失败，课程可能已被修改，请返回重试';
        return;
      }
      await AppState.bumpDataRevision();
      this.navStack().pop();
    } catch (err) {
      this.formError = this.isEditing() ? '保存失败，请重试' : '添加失败，请重试';
    } finally {
      this.saving = false;
    }
  }

  // ---- 删除 ----

  private confirmDelete(): void {
    if (this.originals.length === 0 || this.saving) {
      return;
    }
    const name: string = this.originals[0].name;
    const count: number = this.originals.length;
    Feedback.confirmDanger(this.getUIContext(), '删除课程',
      `确定删除「${name}」的全部 ${count} 个时段吗？删除后不可恢复。`, '删除', () => {
        this.deleteGroup();
      });
  }

  private async deleteGroup(): Promise<void> {
    if (this.saving || this.originals.length === 0) {
      return;
    }
    this.saving = true;
    try {
      const deleted: boolean = await AppState.deleteCourseGroup(this.originals);
      if (!deleted) {
        this.formError = '删除失败，课程可能已被修改，请返回重试';
        return;
      }
      this.navStack().pop();
    } catch (err) {
      this.formError = '删除失败，请重试';
    } finally {
      this.saving = false;
    }
  }

  // ---- UI ----

  @Builder
  private basicSection() {
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
          label: '课程信息',
          placeholder: '课程说明、线上会议链接等',
          multiline: true,
          text: this.info,
          onTextChange: (value: string): void => {
            this.info = value;
          }
        })
      }
      .width('100%')
    }
  }

  @Builder
  private meetingsHeader() {
    Row({ space: Spacing.Sm }) {
      Text('课程时段')
        .fontSize(FontSize.BodySm)
        .fontColor(Colors.TextTertiary)
      Blank()
      Button('添加时段')
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .controlSize(ControlSize.SMALL)
        .fontSize(FontSize.BodySm)
        .fontColor(this.store.accentDisplay)
        .onClick(() => {
          this.addMeetingDraft();
        })
    }
    .width('100%')
    .padding({ left: Spacing.Md, right: Spacing.Md })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private colorSection() {
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
  private extraSection() {
    FormSection({
      title: '其他信息'
    }) {
      Column() {
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
        SettingsItemDivider({ startMargin: 12 })
        CourseTextField({
          label: '链接',
          placeholder: '如：https://…（线上课程地址）',
          text: this.link,
          onTextChange: (value: string): void => {
            this.link = value;
          }
        })
      }
      .width('100%')
    }
  }

  @Builder
  private formBody() {
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
        this.meetingsHeader()
      }
      ForEach(this.meetings, (draft: CourseMeetingDraft) => {
        ListItem() {
          CourseMeetingCard({
            draft: draft,
            onRemove: (): void => {
              this.removeMeetingDraft(draft);
            }
          })
        }
      }, (draft: CourseMeetingDraft) => `meeting-${draft.key}`)
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
  private missingBody() {
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
    const items: HdsNavigationMenuItemOptions[] = [];
    const ready: boolean = !this.loading && !this.loadFailed;
    if (this.isEditing() && ready) {
      items.push({
        content: {
          icon: new SymbolGlyphModifier($r('sys.symbol.trash')).fontColor([Colors.Error]),
          label: '删除',
          isEnabled: !this.saving,
          action: () => {
            this.confirmDelete();
          }
        }
      });
    }
    items.push({
      content: {
        icon: $r('sys.symbol.checkmark'),
        label: '保存',
        isEnabled: ready && !this.saving,
        action: () => {
          this.save();
        }
      }
    });
    const menu: HdsNavigationMenuContentOptions = { value: items };
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
