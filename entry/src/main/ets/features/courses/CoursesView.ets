/**
 * 「课程」Tab 页：列出当前课表的全部课程。
 *
 * 行为基准：旧版课表里同名课程是多个 Course 行（每个时段一行），这里按课程名
 * 合并成一张卡片，显示教师 / 地点 / 周次摘要；点卡片打开与课表页相同的课程详情半模态。
 *
 * 数据刷新：
 * - `store.dataRevision`：增删改 / 导入后自增，列表重载（编辑页写入）；
 * - `store.tableId`：切换课表后重载；
 * - `tableId` prop 可选：外壳若显式指定课表则优先用它，否则用全局当前课表。
 *
 * 外壳（`pages/Index.ets`，Lead 维护）负责标题栏，本页只输出内容。
 */
import { AppState } from '../../app/AppState';
import { Course } from '../../data/models/Models';
import { TabBarAutoHide } from '../../common/ui/TabBarAutoHide';
import { ArrayDataSource } from '../../common/ui/ArrayDataSource';
import { CourseRepository } from '../../data/CourseRepository';
import { CourseTableRepository } from '../../data/CourseTableRepository';
import { ColorPool } from '../../data/ColorPool';
import { ClassPeriod, LegacyConstant } from '../../common/Constants';
import { CourseEditParam } from '../../common/RouteParams';
import { Colors, FontSize, HdsMetrics, Radius, Spacing } from '../../common/design/Tokens';
import { AppStore } from '../../app/AppStore';
import { EmptyState } from '../../common/ui/EmptyState';
import { Feedback } from '../../common/ui/Feedback';
import { StatusBadge, BadgeTone } from '../../common/ui/StatusBadge';
import { WeeksFormat } from '../timetable/WeeksFormat';
import { CourseSessionsSheetContent, DetailSheetContent } from '../timetable/TimetableSheets';
import { CourseFormat, CourseGroup } from './CourseFormat';

@ComponentV2
export struct CoursesView {
  /** V2 全局 Store（主题色 / 当前课表 / 数据版本 / 就绪状态）。 */
  @Local store: AppStore = AppStore.connect();
  /** 外壳可选传入；为 0 时使用 Store 里的当前课表。 */
  @Param tableId: number = 0;
  /** 外壳传入的导航栈（与 HdsNavigation 共用）；拿不到时用 queryNavigationInfo 兜底。 */
  @Param pageStack: NavPathStack = new NavPathStack();
  /** 外壳可传入自己的 Scroller（用于标题栏滚动模糊联动）；不传时用内置的。 */
  @Param scroller: Scroller = new Scroller();

  @Local groups: CourseGroup[] = [];
  /** List + LazyForEach 数据源（数据量小时与 ForEach 差异不大，但课程多时避免一次性构建所有卡片）。 */
  private groupsSource: ArrayDataSource<CourseGroup> = new ArrayDataSource<CourseGroup>();
  @Local loaded: boolean = false;
  @Local loadError: string = '';
  /** 课程详情半模态（与课表页复用同一个 DetailSheetContent）。 */
  @Local detailShown: boolean = false;
  @Local detailCourse: Course = new Course();
  /** 同一课程多个时段的独立半模态（类似自由时间课程列表）。 */
  @Local sessionsShown: boolean = false;
  @Local sessionCourses: Course[] = [];
  @Local sessionCourseName: string = '';
  @Local periods: ClassPeriod[] = [];
  @Local pool: number[] = [];
  /** 课程 Tab 是否激活：切回时重新读取配色池。 */
  @Param active: boolean = true;

  aboutToAppear(): void {
    TabBarAutoHide.resetAndShow();
    this.reload();
  }

  @Monitor('store.dataRevision')
  onDataRevisionChanged(_monitor: IMonitor): void {
    this.reload();
  }

  @Monitor('active')
  onActiveChanged(_monitor: IMonitor): void {
    if (this.active) {
      this.reload();
    }
  }

  @Monitor('store.tableId')
  onTableIdChanged(_monitor: IMonitor): void {
    // 当前课表切换（导入/课表管理）后必须重载。
    this.reload();
  }

  @Monitor('store.ready')
  onAppReadyChanged(_monitor: IMonitor): void {
    if (this.store.ready) {
      this.reload();
    }
  }

  private async reload(): Promise<void> {
    const tableId: number = AppState.effectiveTableId(this.tableId);
    try {
      const pool: number[] = await ColorPool.get();
      this.pool = pool;
      this.periods = await CourseTableRepository.getClassTimeList(tableId);
      const courses: Course[] = await CourseRepository.getAll(tableId);
      this.groups = CourseFormat.group(courses, pool);
      this.groupsSource.setData(this.groups);
      this.loadError = '';
    } catch (err) {
      this.groups = [];
      this.groupsSource.setData(this.groups);
      this.loadError = '课程加载失败，请重试';
    }
    this.loaded = true;
  }

  private navStack(): NavPathStack {
    const info: NavigationInfo | undefined = this.queryNavigationInfo();
    if (info !== undefined) {
      return info.pathStack;
    }
    return this.pageStack;
  }

  private openDetail(group: CourseGroup): void {
    if (group.sessions.length === 0) {
      return;
    }
    if (group.sessions.length > 1) {
      this.sessionCourses = group.sessions;
      this.sessionCourseName = group.name;
      this.sessionsShown = true;
      return;
    }
    this.detailCourse = group.sessions[0];
    this.detailShown = true;
  }

  /** 从「该课程有多个时段」里点某个时段，打开原来的课程详情半模态。 */
  private openSessionDetail(course: Course): void {
    this.detailCourse = course;
    this.detailShown = true;
  }

  private openEdit(course: Course): void {
    this.sessionsShown = false;
    this.detailShown = false;
    // CourseEditPage 保存成功后自行 bumpDataRevision，列表由 @Monitor 刷新。
    this.navStack().pushPathByName('course-edit', new CourseEditParam(course.tableId, course.id));
  }

  private confirmDelete(course: Course): void {
    Feedback.confirmDanger(this.getUIContext(), '删除课程', `确定删除「${course.name}」吗？删除后不可恢复。`, '删除', () => {
      this.deleteCourse(course);
    });
  }

  private async deleteCourse(course: Course): Promise<void> {
    try {
      await CourseRepository.delete(course.id);
      this.sessionsShown = false;
      this.detailShown = false;
      AppState.bumpDataRevision();
      await this.reload();
    } catch (err) {
      console.error(`[Courses] delete failed: ${JSON.stringify(err)}`);
    }
  }

  @Builder
  private sessionsSheetContent() {
    CourseSessionsSheetContent({
      courseName: this.sessionCourseName,
      sessions: this.sessionCourses,
      pool: this.pool,
      onOpenSession: (course: Course) => {
        this.openSessionDetail(course);
      },
      onClose: () => {
        this.sessionsShown = false;
      }
    })
  }

  @Builder
  private detailSheetContent() {
    DetailSheetContent({
      course: this.detailCourse,
      periods: this.periods,
      pool: this.pool,
      onClose: () => {
        this.detailShown = false;
      },
      onEdit: (course: Course) => {
        this.openEdit(course);
      },
      onDelete: (course: Course) => {
        this.confirmDelete(course);
      }
    })
  }

  /** 一门课（可能含多个时段）的卡片。 */
  @Builder
  groupCard(group: CourseGroup) {
    Column({ space: Spacing.Xs }) {
      Row({ space: Spacing.Sm }) {
        Column()
          .width(10)
          .height(10)
          .borderRadius(Radius.Round)
          .backgroundColor(group.color)
        Text(group.name)
          .fontSize(FontSize.Title)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.TextPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        StatusBadge({
          text: WeeksFormat.importTypeLabel(group.importType),
          tone: group.importType === LegacyConstant.ADD_MANUALLY ? BadgeTone.Neutral : BadgeTone.Primary
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      this.infoLine('教师', group.teacherText)
      this.infoLine('地点', group.roomText)
      this.infoLine('周次', group.weekText)

      if (group.sessions.length > 1) {
        Divider()
          .color(Colors.OutlineLight)
          .margin({ top: Spacing.Xs, bottom: Spacing.Xs })
        ForEach(group.sessions, (session: Course) => {
          this.sessionLine(session)
        }, (session: Course) => `${session.id}-${session.weekTime}-${session.startTime}`)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(Spacing.Lg)
    .backgroundColor(Colors.Surface)
    .borderRadius(Radius.Lg)
    .border({ width: 1, color: Colors.OutlineLight })
    .onClick(() => {
      this.openDetail(group);
    })
  }

  @Builder
  infoLine(label: string, value: string) {
    Row({ space: Spacing.Sm }) {
      Text(label)
        .fontSize(FontSize.Caption)
        .fontColor(Colors.TextTertiary)
        .width(32)
      Text(value)
        .fontSize(FontSize.BodySm)
        .fontColor(Colors.TextSecondary)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  /** 多时段课程里的一行：周X 第a-b节 · 周次 · 地点。 */
  @Builder
  sessionLine(session: Course) {
    Row({ space: Spacing.Sm }) {
      Text(CourseFormat.sessionTimeText(session))
        .fontSize(FontSize.Caption)
        .fontColor(Colors.TextTertiary)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (session.classroom.trim() !== '') {
        Text(session.classroom)
          .fontSize(FontSize.Caption)
          .fontColor(Colors.TextTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  emptyContent() {
    EmptyState({
      title: '还没有课程',
      description: '点击右上角「+」从教务导入或添加课程'
    })
  }

  @Builder
  errorContent() {
    Column({ space: Spacing.Md }) {
      Text(this.loadError)
        .fontSize(FontSize.Body)
        .fontColor(Colors.Error)
      Button('重试')
        .fontSize(FontSize.BodySm)
        .height(36)
        .backgroundColor(Colors.SurfaceHigh)
        .fontColor(Colors.TextPrimary)
        .onClick(() => {
          this.loaded = false;
          this.reload();
        })
    }
    .width('100%')
    .padding(Spacing.Xxxl)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {

      if (!this.loaded) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(this.store.accentDisplay)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.loadError !== '') {
        Column() {
          this.errorContent()
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.groups.length === 0) {
        // 空态也要有下拉回弹（Scroll + alwaysEnabled，内容不满一屏也能触发边缘动效）
        Scroll(this.scroller) {
          Column() {
            this.emptyContent()
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .onDidScroll((xOffset: number, yOffset: number) => {
          TabBarAutoHide.onScroll(this.scroller);
        })
        .onReachStart(() => {
          TabBarAutoHide.resetAndShow();
        })
      } else {
        List({ space: Spacing.Md, scroller: this.scroller }) {
          LazyForEach(this.groupsSource, (group: CourseGroup) => {
            ListItem() {
              Row() {
                Row() {
                  this.groupCard(group)
                }
                .width('100%')
                .constraintSize({ maxWidth: 720 })
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ left: Spacing.Lg, right: Spacing.Lg })
            }
          }, (group: CourseGroup) => `${group.name}-${group.color}`)
          ListItem() {
            Row()
              .width('100%')
              .height(120)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ top: HdsMetrics.contentTopInset(px2vp(this.store.windowTopInset)) + Spacing.Md })
        .cachedCount(2)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        // 下滑收起悬浮页签、上滑恢复；回到顶部一定恢复
        .onDidScroll((xOffset: number, yOffset: number) => {
          TabBarAutoHide.onScroll(this.scroller);
        })
        .onReachStart(() => {
          TabBarAutoHide.resetAndShow();
        })
      }

      // 独立锚点：多时段列表半模态；详情半模态仍挂在根 Column 上。
      Stack() {
      }
      .width(0)
      .height(0)
      .bindSheet($$this.sessionsShown, this.sessionsSheetContent(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: false,
        preferType: SheetType.BOTTOM,
        maskColor: Colors.Scrim,
        onDisappear: () => {
          this.sessionsShown = false;
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
  }
}
