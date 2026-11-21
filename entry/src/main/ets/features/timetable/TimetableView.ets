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
 * 文件职责（巨石文件拆分后）：本文件只留数据加载/筛选、几何计算、静态网格与主 build
 * （含 bindSheet 开关与数据准备）；单周课程块页面见 TimetableWeekPage.ets，
 * 展示零件与数据源见 TimetableViewParts.ets，四个半模态内容见 TimetableSheets.ets。
 */
import { Feedback } from '../../common/ui/Feedback';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { AppState } from '../../app/AppState';
import { AppStore } from '../../app/AppStore';
import { AppPreferences } from '../../app/AppPreferences';
import { ClassPeriod, LegacyConfig, LegacyConstant } from '../../common/Constants';
import { DateUtils } from '../../common/DateUtils';
import { Colors, HdsMetrics, Spacing, TimetableMetrics } from '../../common/design/Tokens';
import { CourseEditParam } from '../../common/RouteParams';
import { BackgroundImage } from '../../data/BackgroundImage';
import { ColorPool } from '../../data/ColorPool';
import { CourseRepository } from '../../data/CourseRepository';
import { CourseTableRepository } from '../../data/CourseTableRepository';
import { Course, CourseTable } from '../../data/models/Models';
import { ScheduleModel } from '../../data/ScheduleModel';
import { WeekUtil } from '../../data/WeekUtil';
import { CourseGroups } from '../../data/CourseGroups';
import { CourseDeleteFlow } from '../courses/CourseDeleteFlow';
import { ShellRouter } from '../../common/ShellRouter';
import { contentSheetOptions, pickerSheetOptions } from '../../common/ui/SheetOptions';
import {
  BackToCurrentWeekButton,
  FreeCourseEntryButton,
  WeekHeaderRow,
  WeekPageDataSource,
  makeWeekPageDataSource
} from './TimetableViewParts';
import { LayoutBlock, TimetableWeekPage } from './TimetableWeekPage';
import { DetailSheetContent, FreeCourseSheetContent, MultiSheetContent, WeekPickerSheetContent } from './TimetableSheets';

@ComponentV2
export struct TimetableView {
  /** V2 全局 Store（主题色 / 背景图 / 课表与周次 / 显示配置）。 */
  @Local store: AppStore = AppStore.connect();
  @Param pageStack: NavPathStack = new NavPathStack();
  /** 外壳可传入自己的 Scroller（用于标题栏模糊联动）；不传时用内置的。 */
  @Param scroller: Scroller = new Scroller();
  /** 课表 Tab 是否激活：离开课表时轮播背景图。 */
  @Param active: boolean = true;
  /** 所有课程（不按周过滤）；按周布局块由 blocksByDay 构建并缓存。 */
  @Local allCourses: Course[] = [];
  private weekSwiper: SwiperController = new SwiperController();
  /** 周页面数据源：用 LazyForEach 按需构建（25 个复杂课表页全量构建是切换卡顿的主因）。 */
  private weekPages: WeekPageDataSource = makeWeekPageDataSource();
  /** 按周缓存布局块，避免同一次页面 build 里为 5–7 个日期列重复构造 ScheduleModel。 */
  private blocksCache: Map<number, LayoutBlock[]> = new Map();
  private blocksCacheSignature: string = '';
  /** Swiper 当前页（只在 onChange 里更新，不与周次状态绑定，避免滑动中重设页码导致闪动）。 */
  @Local currentIndex: number = 0;
  /** 用户手势滑动中：此时不响应外部跳页，避免打断 / 回弹。 */
  private userSwiping: boolean = false;
  /** 外部跳周时是否使用滑动动画（「回到本周」按钮使用）。 */
  private animateWeekJump: boolean = false;

  @Local backgroundPixel: image.PixelMap | undefined = undefined;

  /** 自由时间课程半模态开关（由右下角时钟按钮打开）。 */
  @Local freeCourseSheetShown: boolean = false;

  @Local loading: boolean = true;
  @Local periods: ClassPeriod[] = [];
  @Local pool: number[] = [];
  @Local freeCourses: Course[] = [];
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
  /** 当前选中课表的「本周」周次；切换课程表时随选中课表更新。 */
  @Local sheetCurrentWeek: number = 1;
  /** 每个课表自己的当前周缓存，不再复用当前激活课表的周次。 */
  private sheetTableWeeks: Map<number, number> = new Map();

  aboutToAppear(): void {
    this.todayWeekday = DateUtils.weekdayOneBased(new Date());
    this.loadBackground();
    this.reload();
  }

  @Monitor('active')
  private onActiveChanged(_monitor: IMonitor): void {
    // 离开课表时先轮播到下一张，返回时代码与图片都已就绪，避免进入瞬间旧图一闪而过。
    if (!this.active) {
      this.rotateBackgroundOnLeave();
    }
  }

  /** 离开课表前在选中背景图里轮播到下一张，返回时新图已就绪。 */
  private rotateBackgroundOnLeave(): void {
    BackgroundImage.rotateOnLeave().catch((err: Error) => {
      console.warn(`[TimetableView] rotate background failed: ${err.message}`);
    });
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
      this.blocksCache.clear();
      this.blocksCacheSignature = '';
      this.refreshCurrentWeekData();
    } catch (err) {
      console.error(`[Timetable] 加载失败: ${JSON.stringify(err)}`);
      this.allCourses = [];
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
    this.freeCourses = model.freeCourses;
  }

  private weekMondayOf(week: number): Date {
    const thisMonday: Date = DateUtils.mondayOf(DateUtils.today());
    return DateUtils.addDays(thisMonday, (week - this.store.weekIndex) * 7);
  }

  private dayDateFor(week: number, index: number): string {
    return DateUtils.formatMonthDay(DateUtils.addDays(this.weekMondayOf(week), index));
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
    block.y = (course.startTime - 1) * this.store.classHeight + gap;
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
      const rawGroup: Course[] = model.multiCourses[i];
      if (rawGroup.length === 0) {
        continue;
      }
      // 上游做法：多课程组按 CourseGroups 归一化后再展示。
      // 同一门课的多个时段只算一门课，且本周代表放到首位。
      const representatives: Course[] = CourseGroups.representativesForWeek(rawGroup, week);
      if (representatives.length === 0) {
        continue;
      }
      const first: Course = representatives[0];
      if (!this.store.showWeekend && first.weekTime > 5) {
        continue;
      }
      blocks.push(this.makeBlock(first, false, representatives.length, representatives));
    }
    return blocks;
  }

  private blocksSignature(): string {
    return `${this.allCourses.length}|${this.store.classHeight}|${this.store.showWeekend}|${this.pool.length}`;
  }

  /** 按周缓存布局块；课高/周末显示/数据变化时整表失效。 */
  private layoutBlocksForCached(week: number): LayoutBlock[] {
    const signature: string = this.blocksSignature();
    if (signature !== this.blocksCacheSignature) {
      this.blocksCache.clear();
      this.blocksCacheSignature = signature;
    }
    let blocks: LayoutBlock[] | undefined = this.blocksCache.get(week);
    if (blocks === undefined) {
      blocks = this.layoutBlocksFor(week);
      this.blocksCache.set(week, blocks);
    }
    return blocks;
  }

  /** 按天分好组的课程块，供可复用周页面直接消费。 */
  private blocksByDay(week: number): LayoutBlock[][] {
    const blocks: LayoutBlock[] = this.layoutBlocksForCached(week);
    const dayCount: number = this.daysCount();
    const byDay: LayoutBlock[][] = [];
    for (let i = 0; i < dayCount; i++) {
      byDay.push([]);
    }
    for (let i = 0; i < blocks.length; i++) {
      const day: number = blocks[i].course.weekTime;
      if (day >= 1 && day <= dayCount) {
        byDay[day - 1].push(blocks[i]);
      }
    }
    return byDay;
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

  private openEdit(course: Course): void {
    this.detailShown = false;
    this.multiShown = false;
    this.freeCourseSheetShown = false;
    ShellRouter.replaceOrPush(this.pageStack, 'course-edit',
      new CourseEditParam(this.store.tableId, course.id));
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
    CourseDeleteFlow.confirmDelete(this.getUIContext(), course, () => {
      this.detailShown = false;
      this.multiShown = false;
      this.freeCourseSheetShown = false;
      this.reload();
    }, () => {
      Feedback.toast(this.getUIContext(), '删除失败，请重试');
    });
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

  @Monitor('store.weekPickerOpen')
  private onWeekPickerShownChanged(_monitor: IMonitor): void {
    if (!this.store.weekPickerOpen) {
      return;
    }
    this.sheetSelectedWeek = this.store.tmpWeekIndex;
    this.sheetSelectedTableId = this.store.tableId;
    this.sheetCurrentWeek = this.store.weekIndex;
    this.loadSheetData();
  }

  private async loadSheetData(): Promise<void> {
    try {
      this.sheetTables = await CourseTableRepository.getAll();
    } catch (err) {
      console.warn(`[Timetable] 加载课表列表失败: ${JSON.stringify(err)}`);
      this.sheetTables = [];
      return;
    }
    const weeks: Map<number, number> = new Map();
    for (let i = 0; i < this.sheetTables.length; i++) {
      const tableId: number = this.sheetTables[i].id;
      try {
        weeks.set(tableId, (await WeekUtil.peekWeekForTable(tableId)).week);
      } catch (err) {
        console.warn(`[Timetable] 读取课表周次失败: ${JSON.stringify(err)}`);
      }
    }
    this.sheetTableWeeks = weeks;
  }

  /** 异步加载完成后，只有该课表仍是当前选中项才更新半模态周次。 */
  private applySheetTableWeek(tableId: number, week: number): void {
    if (this.sheetSelectedTableId !== tableId) {
      return;
    }
    this.sheetCurrentWeek = week;
    this.sheetSelectedWeek = week;
  }

  /** 半模态里切换选中课表时，周次跟着该课表自己的状态走，而不是沿用当前激活课表。 */
  private selectSheetTable(tableId: number): void {
    this.sheetSelectedTableId = tableId;
    if (tableId === this.store.tableId) {
      this.sheetCurrentWeek = this.store.weekIndex;
      this.sheetSelectedWeek = this.store.tmpWeekIndex;
      return;
    }
    const cachedWeek: number | undefined = this.sheetTableWeeks.get(tableId);
    if (cachedWeek !== undefined) {
      this.applySheetTableWeek(tableId, cachedWeek);
      return;
    }
    WeekUtil.peekWeekForTable(tableId).then((state) => {
      this.sheetTableWeeks.set(tableId, state.week);
      this.applySheetTableWeek(tableId, state.week);
    }).catch((err: Error) => {
      console.warn(`[Timetable] 读取课表周次失败: ${JSON.stringify(err)}`);
    });
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
      courses: this.freeCourses, pool: this.pool,
      onClose: () => { this.freeCourseSheetShown = false; },
      onOpenCourse: (course: Course) => { this.openDetail(course); }
    })
  }

  @Builder
  private weekPickerSheetContent() {
    WeekPickerSheetContent({
      tables: this.sheetTables, selectedTableId: this.sheetSelectedTableId,
      selectedWeek: this.sheetSelectedWeek, currentWeek: this.sheetCurrentWeek,
      onClose: () => { this.store.weekPickerOpen = false; },
      onSelectTable: (tableId: number) => { this.selectSheetTable(tableId); },
      onSelectWeek: (week: number) => { this.sheetSelectedWeek = week; },
      onOpenTables: () => { this.store.weekPickerOpen = false; ShellRouter.push(this.pageStack, 'tables', null); },
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
            .opacity(this.store.backgroundMaskOpacity / 100)
        }
        .width('100%')
        .height('100%')
      }

      Scroll(this.scroller) {
        Column() {
          // 顶部留白 + 星期/日期行都放进滚动内容：
          // 内容向上滚入 HDS 标题栏下方，标题栏才会显示「静止透明、滚动渐变模糊」效果
          Row()
            .width('100%')
            .height(this.pageTopPadding())
          WeekHeaderRow({
            week: this.store.tmpWeekIndex,
            labels: this.weekdayLabels(),
            dates: this.dayDatesFor(this.store.tmpWeekIndex),
            todayColumn: this.todayColumnFor(this.store.tmpWeekIndex),
            showDate: this.store.showDate
          })
          // 一周一页，时间列+节次虚线+课程块都在周页面内，随周一起滚动/滑动
          Swiper(this.weekSwiper) {
            LazyForEach(this.weekPages, (weekValue: number) => {
              TimetableWeekPage({
                week: weekValue,
                periods: this.periods,
                classHeight: this.store.classHeight,
                showClassTime: this.store.showClassTime,
                blocksByDay: this.blocksByDay(weekValue),
                gridHeight: this.gridHeight(),
                onOpenCourse: (course: Course): void => {
                  this.openDetail(course);
                },
                onOpenMulti: (group: Course[]): void => {
                  this.openMulti(group);
                },
                onDeleteCourse: (course: Course): void => {
                  this.confirmDelete(course);
                }
              })
                .reuse({ reuseId: (): string => 'TimetableWeekPage' })
            }, (weekValue: number) => `week-page-${weekValue}`)
          }
          .width('100%')
          .height(this.gridHeight())
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
          Row()
            .width('100%')
            .height(this.gridBottomSpace())
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.TopStart)

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

      // ArkUI 同一组件挂多个 bindSheet 会互相干扰（详情 sheet 只暗屏不弹内容），
      // 每个半模态挂到独立隐形锚点上。
      Stack() {
      }
      .width(0)
      .height(0)
      .bindSheet($$this.detailShown, this.detailSheetContent(), contentSheetOptions(this.store.breakpoint))

      Stack() {
      }
      .width(0)
      .height(0)
      .bindSheet($$this.multiShown, this.multiSheetContent(), contentSheetOptions(this.store.breakpoint))

      Stack() {
      }
      .width(0)
      .height(0)
      .bindSheet($$this.store.weekPickerOpen, this.weekPickerSheetContent(), pickerSheetOptions(this.store.breakpoint))

      Stack() {
      }
      .width(0)
      .height(0)
      .bindSheet($$this.freeCourseSheetShown, this.freeCourseSheetContent(), contentSheetOptions(this.store.breakpoint))
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.Background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
