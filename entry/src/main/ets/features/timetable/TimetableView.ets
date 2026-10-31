/**
 * 课表周视图（「课表」Tab）。
 *
 * 布局基线来自旧版 `lib/Pages/CourseTable/CourseTableView.dart`：
 * 左侧节次时间列 + 7 天网格；课程块绝对定位，块高 = (timeCount + 1) 节；
 * 非本周课程灰色淡显；时间冲突的课程合成一块并显示数量角标；自由时间课程浮动在底部。
 *
 * 交互重做为 HarmonyOS 原生：周切换用 Swiper 周页面（顶部周次/日期同步），
 * 点击课程弹半模态详情，长按删课，详情内可编辑。
 *
 * 文件职责（巨石文件拆分后）：本文件只留数据加载/筛选、几何计算、周页面网格与主 build
 * （含 bindSheet 开关与数据准备）；展示零件与数据源见 TimetableViewParts.ets，
 * 四个半模态内容见 TimetableSheets.ets。
 */
import { Feedback } from '../../common/ui/Feedback';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { AppState } from '../../app/AppState';
import { AppStore } from '../../app/AppStore';
import { AppPreferences } from '../../app/AppPreferences';
import { ClassPeriod, LegacyConfig, LegacyConstant } from '../../common/Constants';
import { DateUtils } from '../../common/DateUtils';
import { Colors, FontSize, HdsMetrics, Spacing, TimetableMetrics } from '../../common/design/Tokens';
import { CourseEditParam } from '../../common/RouteParams';
import { BackgroundImage } from '../../data/BackgroundImage';
import { ColorPool } from '../../data/ColorPool';
import { CourseRepository } from '../../data/CourseRepository';
import { CourseTableRepository } from '../../data/CourseTableRepository';
import { Course, CourseTable } from '../../data/models/Models';
import { ScheduleModel } from '../../data/ScheduleModel';
import { CourseBlock } from './CourseBlock';
import { TabBarAutoHide } from '../../common/ui/TabBarAutoHide';
import {
  BackToCurrentWeekButton,
  FreeCourseEntryButton,
  WeekHeaderRow,
  WeekPageDataSource,
  makeWeekPageDataSource
} from './TimetableViewParts';
import { DetailSheetContent, FreeCourseSheetContent, MultiSheetContent, WeekPickerSheetContent } from './TimetableSheets';

/** 一个待渲染的课程块（几何信息在 build 时按当前宽度/课高算）。 */
class LayoutBlock {
  key: string = '';
  course: Course = new Course();
  color: string = '#8AD297';
  faded: boolean = false;
  conflictCount: number = 0;
  group: Course[] = [];
  x: number = 0;
  y: number = 0;
  w: number = 0;
  h: number = 0;
}

@ComponentV2
export struct TimetableView {
  /** V2 全局 Store（主题色 / 背景图 / 课表与周次 / 显示配置）。 */
  @Local store: AppStore = AppStore.connect();
  @Param pageStack: NavPathStack = new NavPathStack();
  /** 课表 Tab 是否处于激活状态：切回时重新读取配色池，保证重置颜色立即生效。 */
  @Param active: boolean = true;
  /** 外壳可传入自己的 Scroller（用于标题栏模糊联动）；不传时用内置的。 */
  @Param scroller: Scroller = new Scroller();
  /** 外壳传入的 25 个周页面滚动控制器（用于标题栏模糊绑定）。 */
  @Param weekScrollers: Scroller[] = [];
  /** 当前周页面的滚动容器变化回调（外壳据此把 Scroller 绑定给 HdsTabs，保持滚动联动）。 */
  @Event onActiveScrollerChange: (scroller: Scroller) => void = () => {
  };
  /** 所有课程（不按周过滤）：每个周页面自行构建，等价旧版 presenter.refreshClasses(tableIndex, weekN)。 */
  @Local allCourses: Course[] = [];
  private weekSwiper: SwiperController = new SwiperController();
  /** 周页面数据源：用 LazyForEach 按需构建（25 个复杂课表页全量构建是切换卡顿的主因）。 */
  private weekPages: WeekPageDataSource = makeWeekPageDataSource();
  /** Swiper 当前页（只在 onChange 里更新，不与周次状态绑定，避免滑动中重设页码导致闪动）。 */
  @Local currentIndex: number = 0;
  /** 用户手势滑动中：此时不响应外部跳页，避免打断 / 回弹。 */
  private userSwiping: boolean = false;
  /** 外部跳周时是否使用滑动动画（「回到本周」按钮使用）。 */
  private animateWeekJump: boolean = false;

  @Local backgroundPixel: image.PixelMap | undefined = undefined;

  /** 自由时间课程半模态开关（由右下角时钟按钮打开）。 */
  @Local freeCourseSheetShown: boolean = false;
  @Local freeSheetIndex: number = 0;

  @Local loading: boolean = true;
  @Local periods: ClassPeriod[] = [];
  @Local pool: number[] = [];
  @Local activeCourses: Course[] = [];
  @Local multiGroups: Course[][] = [];
  @Local freeCourses: Course[] = [];
  @Local containerWidth: number = 0;
  @Local todayWeekday: number = 1;
  /** 当前课表名（对齐系统日历标题：课表名 + 周次）。 */
  @Local tableName: string = '我的课表';

  @Local detailShown: boolean = false;
  @Local detailCourse: Course = new Course();
  @Local multiShown: boolean = false;
  @Local multiGroup: Course[] = [];
  /** 底部「切换课表」半模态：课表列表 / 待确认的课表 / 待确认的周次。 */
  @Local sheetTables: CourseTable[] = [];
  @Local sheetSelectedTableId: number = 0;
  @Local sheetSelectedWeek: number = 1;

  aboutToAppear(): void {
    this.todayWeekday = DateUtils.weekdayOneBased(new Date());
    this.onActiveScrollerChange(this.pageScroller(this.store.tmpWeekIndex));
    this.loadBackground();
    this.reload();
  }

  @Monitor('store.backgroundImagePath')
  onBackgroundChanged(_monitor: IMonitor): void {
    this.loadBackground();
  }

  private async loadBackground(): Promise<void> {
    const pixelMap: image.PixelMap | undefined = await BackgroundImage.loadPixelMap(this.store.backgroundImagePath);
    this.backgroundPixel = pixelMap;
  }

  @Monitor('store.tableId')
  onTableChanged(_monitor: IMonitor): void {
    this.reload();
  }

  @Monitor('store.weekIndex', 'store.tmpWeekIndex')
  onWeekChanged(_monitor: IMonitor): void {
    this.refreshCurrentWeekData();
    this.onActiveScrollerChange(this.pageScroller(this.store.tmpWeekIndex));
    // 外部改周（箭头 / 选择器 / 设置）：把 Swiper 跳到对应页（等价旧版 jumpToPage）
    if (this.userSwiping) {
      return;
    }
    const target: number = Math.max(0, Math.min(this.store.tmpWeekIndex - 1, LegacyConfig.MAX_WEEKS - 1));
    if (this.currentIndex !== target) {
      this.currentIndex = target;
      const useAnimation: boolean = this.animateWeekJump;
      this.animateWeekJump = false;
      setTimeout(() => {
        try {
          this.weekSwiper.changeIndex(target, useAnimation);
        } catch (err) {
          console.warn(`[Timetable] jump page failed: ${JSON.stringify(err)}`);
        }
      }, 0);
    }
  }

  @Monitor('store.dataRevision')
  onDataChanged(_monitor: IMonitor): void {
    this.reload();
  }

  @Monitor('active')
  onActiveChanged(_monitor: IMonitor): void {
    if (this.active) {
      this.reload();
    }
  }

  // ------------------------------------------------------------------ 数据

  private async reload(): Promise<void> {
    this.loading = true;
    try {
      this.todayWeekday = DateUtils.weekdayOneBased(new Date());
      this.periods = await CourseTableRepository.getClassTimeList(this.store.tableId);
      hilog.info(0x0000, 'NjuTable', 'tableId=%{public}d periods=%{public}d', this.store.tableId, this.periods.length);
      this.pool = await ColorPool.get();
      try {
        const table = await CourseTableRepository.getById(this.store.tableId);
        if (table !== null && table.name !== '') {
          this.tableName = table.name;
        }
      } catch (err) {
        // 课表名读取失败不阻塞课表渲染。
      }
      const courses: Course[] = await CourseRepository.getAll(this.store.tableId);
      hilog.info(0x0000, 'NjuTable', 'courses=%{public}d ch=%{public}d', courses.length, this.store.classHeight);
      this.allCourses = courses;
      this.refreshCurrentWeekData();
    } catch (err) {
      console.error(`[Timetable] 加载失败: ${JSON.stringify(err)}`);
      this.allCourses = [];
      this.activeCourses = [];
      this.multiGroups = [];
      this.freeCourses = [];
    } finally {
      this.loading = false;
    }
  }

  /** 滚动内容底部留白：悬浮胶囊页签 + 手势条（有自由时间栏时再加一层）。 */
  private gridBottomSpace(): number {
    const freeBar: number = (this.store.showFreeClass && this.freeCourses.length > 0) ? 64 : 0;
    return px2vp(this.store.windowBottomInset) + 88 + freeBar;
  }

  /** 滚动内容顶部留白：标题栏 + 状态栏。 */
  private pageTopPadding(): number {
    // HDS 标题栏（MODAL 模式：大标题 + 副标题）覆盖在内容上，内容需让出状态栏 + 标题栏高度
    return HdsMetrics.TitleBarHeight + HdsMetrics.TitleBarBreathing + px2vp(this.store.windowTopInset);
  }

  // ------------------------------------------------------------------ 几何

  private daysCount(): number {
    return this.store.showWeekend ? 7 : 5;
  }

  private dayWidth(): number {
    const width: number = this.containerWidth > 0 ? this.containerWidth : 360;
    const available: number = width - TimetableMetrics.TimeColumnWidth;
    const perDay: number = available / this.daysCount();
    return perDay > 40 ? perDay : 40;
  }

  private gridHeight(): number {
    return this.periods.length * this.store.classHeight;
  }

  /** 某一周的课表数据（等价旧版 presenter.refreshClasses(tableIndex, weekNum) 的结果）。 */
  private modelFor(week: number): ScheduleModel {
    const model: ScheduleModel = new ScheduleModel(this.allCourses, week);
    model.init();
    return model;
  }

  /** 当前周数据用于自由时间栏 / 空态等浮层。 */
  private refreshCurrentWeekData(): void {
    const model: ScheduleModel = this.modelFor(this.store.tmpWeekIndex);
    this.activeCourses = model.activeCourses;
    this.multiGroups = model.multiCourses;
    this.freeCourses = model.freeCourses;
  }

  private pageScroller(week: number): Scroller {
    if (week >= 1 && week <= this.weekScrollers.length) {
      return this.weekScrollers[week - 1];
    }
    return this.scroller;
  }

  /** 当前显示周的周一（用于表头日期）。 */
  private weekMonday(): Date {
    const thisMonday: Date = DateUtils.mondayOf(DateUtils.today());
    return DateUtils.addDays(thisMonday, (this.store.tmpWeekIndex - this.store.weekIndex) * 7);
  }

  private dayDate(index: number): string {
    return DateUtils.formatMonthDay(DateUtils.addDays(this.weekMonday(), index));
  }

  private weekMondayOf(week: number): Date {
    const thisMonday: Date = DateUtils.mondayOf(DateUtils.today());
    return DateUtils.addDays(thisMonday, (week - this.store.weekIndex) * 7);
  }

  private dayDateFor(week: number, index: number): string {
    return DateUtils.formatMonthDay(DateUtils.addDays(this.weekMondayOf(week), index));
  }

  private weekRangeText(): string {
    const monday: Date = this.weekMonday();
    const sunday: Date = DateUtils.addDays(monday, this.daysCount() - 1);
    return `${DateUtils.formatMonthDay(monday)} - ${DateUtils.formatMonthDay(sunday)}`;
  }

  private makeBlock(course: Course, faded: boolean, conflictCount: number, group: Course[]): LayoutBlock {
    const block: LayoutBlock = new LayoutBlock();
    block.key = `${course.id}-${course.weekTime}-${course.startTime}`;
    block.course = course;
    block.color = ColorPool.resolve(course, this.pool);
    block.faded = faded;
    block.conflictCount = conflictCount;
    block.group = group;
    const gap: number = TimetableMetrics.CourseBlockGap;
    const dayWidth: number = this.dayWidth();
    block.x = TimetableMetrics.TimeColumnWidth + (course.weekTime - 1) * dayWidth + gap;
    block.y = (course.startTime - 1) * this.store.classHeight + gap;
    block.w = dayWidth - gap * 2;
    block.h = Math.max((course.timeCount + 1) * this.store.classHeight - gap * 2, this.store.classHeight - gap * 2);
    return block;
  }

  private layoutBlocksFor(week: number): LayoutBlock[] {
    const model: ScheduleModel = this.modelFor(week);
    const blocks: LayoutBlock[] = [];
    for (let i = 0; i < model.activeCourses.length; i++) {
      const course: Course = model.activeCourses[i];
      if (!this.store.showWeekend && course.weekTime > 5) {
        continue;
      }
      blocks.push(this.makeBlock(course, false, 1, []));
    }
    for (let i = 0; i < model.multiCourses.length; i++) {
      const group: Course[] = model.multiCourses[i];
      if (group.length === 0) {
        continue;
      }
      const first: Course = group[0];
      if (!this.store.showWeekend && first.weekTime > 5) {
        continue;
      }
      // 本周不上的课不再灰显，直接不显示（多课冲突组只保留含本周课程的组）
      const isThisWeek: boolean = first.weeks.indexOf(week) >= 0;
      if (!isThisWeek) {
        continue;
      }
      blocks.push(this.makeBlock(first, false, group.length, group));
    }
    return blocks;
  }

  // ------------------------------------------------------------------ 交互

  private changeWeek(target: number): void {
    if (target < 1 || target > LegacyConfig.MAX_WEEKS) {
      return;
    }
    AppState.setDisplayWeek(target);
    AppPreferences.setTmpWeekIndex(target).catch((err: Error) => {
      console.warn(`[Timetable] 保存显示周失败: ${JSON.stringify(err)}`);
    });
  }

  private backToCurrentWeek(): void {
    // 模拟快速滑回本周：走 Swiper 的滑动动画，而不是瞬间跳页
    this.animateWeekJump = true;
    this.changeWeek(this.store.weekIndex);
  }

  private openCreate(): void {
    this.pageStack.pushPathByName('course-edit', new CourseEditParam(this.store.tableId, 0),
      (popInfo: PopInfo) => {
        this.reload();
      });
  }

  private openEdit(course: Course): void {
    this.detailShown = false;
    this.multiShown = false;
    this.pageStack.pushPathByName('course-edit', new CourseEditParam(this.store.tableId, course.id),
      (popInfo: PopInfo) => {
        this.reload();
      });
  }

  private openDetail(course: Course): void {
    this.detailCourse = course;
    this.detailShown = true;
  }

  private openMulti(group: Course[]): void {
    this.multiGroup = group;
    this.multiShown = true;
  }

  private confirmDelete(course: Course): void {
    Feedback.confirmDanger(this.getUIContext(), '删除课程', `确定删除「${course.name}」吗？`, '删除', () => {
      this.deleteCourse(course);
    });
  }

  private async deleteCourse(course: Course): Promise<void> {
    try {
      await CourseRepository.delete(course.id);
      this.detailShown = false;
      this.multiShown = false;
      await AppState.bumpDataRevision();
      await this.reload();
    } catch (err) {
      console.error(`[Timetable] 删除失败: ${JSON.stringify(err)}`);
    }
  }

  // ------------------------------------------------------------------ 视图

  /** 星期/日期行的标签数据（颜色由子组件读 Store，避免主题色变化时重绘整个 25 页课表）。 */
  private weekdayLabels(): string[] {
    const labels: string[] = [];
    for (let i = 0; i < this.daysCount(); i++) {
      labels.push(LegacyConstant.WEEK_WITHOUT_BIAS[i].replace('周', ''));
    }
    return labels;
  }

  private dayDatesFor(week: number): string[] {
    const dates: string[] = [];
    for (let i = 0; i < this.daysCount(); i++) {
      dates.push(this.dayDateFor(week, i));
    }
    return dates;
  }

  /** 今天在该周中的列下标（不是本周返回 -1）。 */
  private todayColumnFor(week: number): number {
    return week === this.store.weekIndex ? this.todayWeekday - 1 : -1;
  }

  private dayIndexes(): number[] {
    const result: number[] = [];
    for (let i = 0; i < this.daysCount(); i++) {
      result.push(i);
    }
    return result;
  }

  private isToday(index: number): boolean {
    return this.store.tmpWeekIndex === this.store.weekIndex && this.todayWeekday === index + 1;
  }

  private isTodayFor(week: number, index: number): boolean {
    return week === this.store.weekIndex && this.todayWeekday === index + 1;
  }

  @Builder
  private timeColumn() {
    Column() {
      ForEach(this.periods, (period: ClassPeriod, index: number) => {
        Column({ space: 1 }) {
          Text(`${index + 1}`)
            .fontSize(FontSize.BodySm)
            .fontColor(Colors.TextSecondary)
          if (this.store.showClassTime) {
            Text(period.start)
              .fontSize(9)
              .fontColor(Colors.TextTertiary)
            Text(period.end)
              .fontSize(9)
              .fontColor(Colors.TextTertiary)
          }
        }
        .width(TimetableMetrics.TimeColumnWidth)
        .height(this.store.classHeight)
        .justifyContent(FlexAlign.Center)
        .border({ width: { bottom: 1 }, color: Colors.GridLine, style: BorderStyle.Dashed })
      }, (period: ClassPeriod, index: number) => `t-${this.store.classHeight}-${index}`)
    }
    .width(TimetableMetrics.TimeColumnWidth)
  }

  @Builder
  private gridBackground() {
    Row() {
      this.timeColumn()
      ForEach(this.dayIndexes(), (dayIndex: number) => {
        Column() {
          ForEach(this.periods, (period: ClassPeriod, periodIndex: number) => {
            Row()
              .width('100%')
              .height(this.store.classHeight)
              .backgroundColor(Color.Transparent)
              .border({ width: { bottom: 1 }, color: Colors.GridLine, style: BorderStyle.Dashed })
          }, (period: ClassPeriod, periodIndex: number) => `c-${this.store.classHeight}-${this.containerWidth}-${dayIndex}-${periodIndex}`)
        }
        .width(this.dayWidth())
      }, (dayIndex: number) => `col-${this.daysCount()}-${this.containerWidth}-${dayIndex}`)
    }
    .alignItems(VerticalAlign.Top)
  }

  /** 单周网格页面（Swiper 的每个子页面，等价旧版 PageView.builder 的单页内容）。 */
  @Builder
  private gridFor(week: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      this.gridBackground()
      ForEach(this.layoutBlocksFor(week), (block: LayoutBlock) => {
        CourseBlock({
          course: block.course,
          color: block.color,
          widthPx: block.w,
          heightPx: block.h,
          faded: block.faded,
          conflictCount: block.conflictCount,
          showPlace: true,
          showTeacher: this.store.classHeight >= 60,
          onTap: () => {
            if (block.conflictCount > 1) {
              this.openMulti(block.group);
            } else {
              this.openDetail(block.course);
            }
          },
          onLongPress: () => {
            this.confirmDelete(block.course);
          }
        })
          .position({ x: block.x, y: block.y })
      }, (block: LayoutBlock) => `w${week}-${this.daysCount()}-${this.store.classHeight}-${this.containerWidth}-${block.key}-${block.color}`)
    }
    .width('100%')
    .height(this.gridHeight())
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const width: number = Number(newValue.width);
      if (width > 0 && Math.abs(width - this.containerWidth) > 1) {
        this.containerWidth = width;
      }
    })
  }

  @Monitor('store.weekPickerOpen')
  private onWeekPickerShownChanged(_monitor: IMonitor): void {
    if (!this.store.weekPickerOpen) {
      return;
    }
    this.sheetSelectedWeek = this.store.tmpWeekIndex;
    this.sheetSelectedTableId = this.store.tableId;
    this.loadSheetTables();
  }

  private async loadSheetTables(): Promise<void> {
    try {
      this.sheetTables = await CourseTableRepository.getAll();
    } catch (err) {
      console.warn(`[Timetable] 加载课表列表失败: ${JSON.stringify(err)}`);
      this.sheetTables = [];
    }
  }

  /** 确认「切换课表」半模态：应用课表与周次。 */
  private async applySheetSelection(): Promise<void> {
    this.store.weekPickerOpen = false;
    if (this.sheetSelectedTableId > 0 && this.sheetSelectedTableId !== this.store.tableId) {
      try {
        await AppState.switchTable(this.sheetSelectedTableId);
      } catch (err) {
        console.warn(`[Timetable] 切换课表失败: ${JSON.stringify(err)}`);
      }
    }
    this.changeWeek(this.sheetSelectedWeek);
  }

  // ------------------------------------------------------------ 半模态内容
  //
  // 内容组件在 TimetableSheets.ets：本组件只负责 bindSheet 开关、传数据、在 @Event 回调里复用原有交互。
  @Builder
  private detailSheetContent() {
    DetailSheetContent({
      course: this.detailCourse, periods: this.periods, pool: this.pool,
      onClose: () => { this.detailShown = false; },
      onEdit: (course: Course) => { this.openEdit(course); },
      onDelete: (course: Course) => { this.confirmDelete(course); }
    })
  }

  @Builder
  private multiSheetContent() {
    MultiSheetContent({
      group: this.multiGroup, pool: this.pool,
      onSelect: (course: Course) => { this.openDetail(course); },
      onClose: () => { this.multiShown = false; }
    })
  }

  @Builder
  private freeCourseSheetContent() {
    FreeCourseSheetContent({
      courses: this.freeCourses, sheetIndex: this.freeSheetIndex, pool: this.pool,
      onClose: () => { this.freeCourseSheetShown = false; },
      onIndexChange: (index: number) => { this.freeSheetIndex = index; },
      onOpenCourse: (course: Course) => { this.openDetail(course); }
    })
  }

  @Builder
  private weekPickerSheetContent() {
    WeekPickerSheetContent({
      tables: this.sheetTables, selectedTableId: this.sheetSelectedTableId,
      selectedWeek: this.sheetSelectedWeek,
      onClose: () => { this.store.weekPickerOpen = false; },
      onSelectTable: (tableId: number) => { this.sheetSelectedTableId = tableId; },
      onSelectWeek: (week: number) => { this.sheetSelectedWeek = week; },
      onOpenTables: () => { this.store.weekPickerOpen = false; this.pageStack.pushPathByName('tables', null); },
      onConfirm: () => { this.applySheetSelection(); }
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 背景图（若有）+ 半透明遮罩，保证网格与文字可读
      if (this.backgroundPixel !== undefined) {
        Stack() {
          Image(this.backgroundPixel)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .opacity(0.62)
          Row()
            .width('100%')
            .height('100%')
            .backgroundColor(Colors.Background)
            .opacity(0.5)
        }
        .width('100%')
        .height('100%')
      }

      Column() {
        // 一周一页，Swiper 原生提供左右滑动与翻页动画（等价旧版 PageView.builder + PageController）
        Swiper(this.weekSwiper) {
          LazyForEach(this.weekPages, (weekValue: number) => {
            Column() {
              Scroll(this.pageScroller(weekValue)) {
                Column() {
                  // 顶部留白 + 星期/日期行都放进滚动内容：
                  // 内容向上滚入 HDS 标题栏下方，标题栏才会显示「静止透明、滚动渐变模糊」效果
                  Row()
                    .width('100%')
                    .height(this.pageTopPadding())
                  WeekHeaderRow({
                    week: weekValue,
                    labels: this.weekdayLabels(),
                    dates: this.dayDatesFor(weekValue),
                    todayColumn: this.todayColumnFor(weekValue),
                    dayWidth: this.dayWidth(),
                    showDate: this.store.showDate
                  })
                  this.gridFor(weekValue)
                  Row()
                    .width('100%')
                    .height(this.gridBottomSpace())
                }
                .width('100%')
              }
              .width('100%')
              .layoutWeight(1)
              .scrollable(ScrollDirection.Vertical)
              .scrollBar(BarState.Off)
              .edgeEffect(EdgeEffect.Spring)
              .align(Alignment.TopStart)
              // 下滑收起悬浮页签、上滑恢复；回到顶部一定恢复
              .onDidScroll((xOffset: number, yOffset: number) => {
                TabBarAutoHide.onScroll(this.pageScroller(weekValue));
              })
              .onReachStart(() => {
                TabBarAutoHide.resetAndShow();
              })
            }
            .width('100%')
            .height('100%')
          }, (weekValue: number) => `week-page-${weekValue}`)
        }
        .width('100%')
        .layoutWeight(1)
        .loop(false)
        .indicator(false)
        .duration(280)
        .cachedCount(1)
        .onAppear(() => {
          // 初次进入：跳到当前周（等价 PageController(initialPage: tmpWeek-1)）
          const target: number = Math.max(0, Math.min(this.store.tmpWeekIndex - 1, LegacyConfig.MAX_WEEKS - 1));
          this.currentIndex = target;
          setTimeout(() => {
            try {
              this.weekSwiper.changeIndex(target);
            } catch (err) {
              console.warn(`[Timetable] init page failed: ${JSON.stringify(err)}`);
            }
          }, 0);
        })
        // 用户滑动开始即更新顶部周次（标题响应快）；但不改 Swiper 页码，避免动画中重设导致闪动
        .onAnimationStart((index: number, targetIndex: number) => {
          if (targetIndex === index || targetIndex + 1 === this.store.tmpWeekIndex) {
            return;
          }
          this.userSwiping = true;
          this.changeWeek(targetIndex + 1);
          this.refreshCurrentWeekData();
        })
        .onChange((index: number) => {
          this.currentIndex = index;
          this.userSwiping = false;
          const target: number = index + 1;
          if (target !== this.store.tmpWeekIndex) {
            this.changeWeek(target);
            this.refreshCurrentWeekData();
          }
        })
      }
      .width('100%')
      .height('100%')

      // 右下角浮动按钮：回到本周（仅划离本周时显示）在自由时间课程入口上方
      if (this.store.tmpWeekIndex !== this.store.weekIndex ||
        (this.store.showFreeClass && this.freeCourses.length > 0)) {
        Column({ space: Spacing.Md }) {
          if (this.store.tmpWeekIndex !== this.store.weekIndex) {
            BackToCurrentWeekButton({
              onTap: (): void => {
                this.backToCurrentWeek();
              }
            })
          }
          if (this.store.showFreeClass && this.freeCourses.length > 0) {
            FreeCourseEntryButton({
              count: this.freeCourses.length,
              onTap: (): void => {
                this.freeSheetIndex = 0;
                this.freeCourseSheetShown = true;
              }
            })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.End)
        .padding({ right: Spacing.Lg })
        .margin({ bottom: px2vp(this.store.windowBottomInset) + 88 })
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // 标题栏副标题热区：只在课表 Tab 内容层响应；子页面（NavDestination）在它之上，
      // 因此打开课程编辑等子页面后点击标题栏不会再误触周次选择器。
      Row()
        .width('100%')
        .height(30)
        .position({ x: 0, y: this.pageTopPadding() - 30 })
        .hitTestBehavior(HitTestMode.Default)
        .onClick(() => {
          AppState.setWeekPickerOpen(true);
        })

      // ArkUI 同一组件挂多个 bindSheet 会互相干扰（详情 sheet 只暗屏不弹内容），
      // 每个半模态挂到独立隐形锚点上。
      Stack() {
      }
      .width(0)
      .height(0)
      .bindSheet($$this.detailShown, this.detailSheetContent(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: false,
        preferType: SheetType.BOTTOM,
        maskColor: Colors.Scrim,
        onDisappear: () => {
          this.detailShown = false;
        },
        onWillDismiss: (action: DismissSheetAction) => {
          action.dismiss();
        },
        backgroundColor: Colors.Background
      })

      Stack() {
      }
      .width(0)
      .height(0)
      .bindSheet($$this.multiShown, this.multiSheetContent(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: false,
        preferType: SheetType.BOTTOM,
        maskColor: Colors.Scrim,
        onDisappear: () => {
          this.multiShown = false;
        },
        onWillDismiss: (action: DismissSheetAction) => {
          action.dismiss();
        },
        backgroundColor: Colors.Background
      })

      Stack() {
      }
      .width(0)
      .height(0)
      .bindSheet($$this.store.weekPickerOpen, this.weekPickerSheetContent(), {
        height: SheetSize.LARGE,
        dragBar: false,
        showClose: false,
        preferType: SheetType.BOTTOM,
        maskColor: Colors.Scrim,
        onDisappear: () => {
          this.store.weekPickerOpen = false;
        },
        onWillDismiss: (action: DismissSheetAction) => {
          action.dismiss();
        },
        backgroundColor: Colors.Background
      })

      Stack() {
      }
      .width(0)
      .height(0)
      .bindSheet($$this.freeCourseSheetShown, this.freeCourseSheetContent(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: false,
        preferType: SheetType.BOTTOM,
        maskColor: Colors.Scrim,
        onDisappear: () => {
          this.freeCourseSheetShown = false;
        },
        onWillDismiss: (action: DismissSheetAction) => {
          action.dismiss();
        },
        backgroundColor: Colors.Background
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.Background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
