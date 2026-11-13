/**
 * 应用外壳：唯一 @Entry。
 *
 * 结构：HdsNavigation 不显示根标题栏，HdsTabs 提供底部胶囊导航；
 * 三个一级 Tab 各自用 HdsNavDestination 提供标题栏。
 * 宽屏默认保持单栏全宽；只有打开编辑/详情等子页面时才进入 Split，
 * 左侧保留当前 Tab，右侧显示子页面；关闭后恢复全宽。窄屏始终 Stack。
 *
 * 子页面自行提供标题栏，
 * 这里只负责分发。
 */
import {
  HdsNavigation,
  HdsNavDestination,
  HdsNavigationMenuContentOptions,
  HdsTabs,
  HdsTabsController,
  IconStyleMode,
  hdsMaterial
} from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { IS_2IN1 } from '../common/DeviceType';
import { TimeGreeting } from '../common/TimeGreeting';
import { CourseEditParam } from '../common/RouteParams';
import { AppState } from '../app/AppState';
import { AppStore } from '../app/AppStore';
import { HdsTabPage } from '../common/ui/HdsTabPage';
import { ShellRouter } from '../common/ShellRouter';
import { DesktopSideBar } from '../common/ui/DesktopSideBar';

import { CourseTableRepository } from '../data/CourseTableRepository';
import { CourseTable } from '../data/models/Models';
import { BreakpointName, breakpointNameOf, isTabletBreakpoint } from '../common/design/Breakpoints';
import { Colors, FontSize, HdsMetrics, Spacing } from '../common/design/Tokens';
import { CourseEditPage } from '../features/courses/CourseEditPage';
import { CoursesView } from '../features/courses/CoursesView';
import { ImportView } from '../features/import/ImportView';
import { LecturesPage } from '../features/lectures/LecturesPage';
import { ImportWebPage } from '../features/import/ImportWebPage';
import { AboutPage } from '../features/settings/AboutPage';
import { OpenSourceLicensesPage } from '../features/settings/OpenSourceLicensesPage';
import { AcknowledgementsPage } from '../features/settings/AcknowledgementsPage';
import { PrivacyPage } from '../features/settings/PrivacyPage';
import { ImportCodePage } from '../features/share/ImportCodePage';
import { SharePage } from '../features/share/SharePage';
import { ManageTablesPage } from '../features/settings/ManageTablesPage';
import { MoreSettingsPage } from '../features/settings/MoreSettingsPage';
import { SettingsView } from '../features/settings/SettingsView';
import { TimetableView } from '../features/timetable/TimetableView';

/** 跨时辰检查间隔：每分钟刷新一次问候标题。 */
const GREETING_REFRESH_INTERVAL_MS: number = 60 * 1000;

@Entry
@ComponentV2
struct Index {
  private hdsTabsController: HdsTabsController = new HdsTabsController();
  /** 每个 Tab 独立的 Scroller，只把当前 Tab 的绑定给导航做滚动模糊联动（官方 FAQ 场景二）。 */
  private timetableScroller: Scroller = new Scroller();
  /** 课表 25 个周页面各自的滚动容器（全部绑定给标题栏模糊联动）。 */
  private weekScrollers: Scroller[] = [];
  private coursesScroller: Scroller = new Scroller();
  private settingsScroller: Scroller = new Scroller();
  private pageStack: NavPathStack = new NavPathStack();
  private tabLabels: string[] = ['课表', '课程', '设置'];
  private tabIcons: Resource[] = [
    $r('sys.symbol.calendar'),
    $r('sys.symbol.book'),
    $r('sys.symbol.gearshape')
  ];
  /** 2in1/PC 使用侧边导航；平板和手机保留底部胶囊。 */
  private readonly is2in1: boolean = IS_2IN1;
  /** 宽屏 Split 的左侧主栏宽度，与 HdsNavigation.navBarWidth 保持一致。 */
  private readonly splitNavWidth: number = 420;
  /** 「课程」Tab 标题栏 + 菜单是否展开。 */
  @Local coursesMenuOpen: boolean = false;
  /** 课表 Tab 主标题：按时辰变化的问候。 */
  @Local greeting: string = TimeGreeting.current();

  /** V2 全局 Store。 */
  @Local store: AppStore = AppStore.connect();
  /** 当前课表名（标题栏副标题显示「课表名 + 第 N 周」）。 */
  @Local tableName: string = '我的课表';
  @Local activeTabIndex: number = 0;
  /** 宽屏无子页面时 Stack，打开子页面时 Auto/Split；窄屏始终 Stack。 */
  @Local navigationMode: NavigationMode = NavigationMode.Stack;
  /** HDS 导航是否停留在根页面（没有子页面）。 */
  @Local navStackAtRoot: boolean = true;
  /** 当前绑定给课表 Tab 的滚动容器（25 个周页面轮换）。 */
  private boundTimetableScroller: Scroller | undefined = undefined;
  /** 课表 Tab 当前周页面滚动容器，供 HdsNavDestination 标题栏模糊联动。 */
  @Local timetableTabScrollables: Scroller[] = [];
  /** 跨时辰刷新问候的定时器（-1 表示未启动）。 */
  private greetingTimer: number = -1;

  aboutToAppear(): void {
    for (let i = 0; i < 25; i++) {
      this.weekScrollers.push(new Scroller());
    }
    const initialWeek: number = Math.max(0, Math.min(this.store.tmpWeekIndex - 1, this.weekScrollers.length - 1));
    this.timetableTabScrollables = [this.weekScrollers[initialWeek]];
    this.hdsTabsController.bindScroller(1, this.coursesScroller);
    this.hdsTabsController.bindScroller(2, this.settingsScroller);
    // 跟踪子页面进出：只有根页面显示标题栏副标题热区，避免挡住子页面返回键。
    ShellRouter.setBridge({
      enterChild: (): boolean => {
        if (!this.isWideShell() || this.pageStack.getAllPathName().length > 0) {
          return false;
        }
        this.navigationMode = NavigationMode.Split;
        return true;
      },
      exitChild: (): void => {
        const depth: number = this.pageStack.getAllPathName().length;
        if (!this.isWideShell() || depth !== 1) {
          this.pageStack.pop();
          return;
        }
        // 官方做法：宽屏从子页面回首页，关闭过场动画，延迟恢复全宽与路由动画。
        this.pageStack.disableAnimation(true);
        this.pageStack.pop();
        setTimeout(() => {
          this.navigationMode = NavigationMode.Stack;
          this.pageStack.disableAnimation(false);
        }, 20);
      }
    });
    this.pageStack.setInterception({
      didShow: (from: NavDestinationContext | NavBar, to: NavDestinationContext | NavBar) => {
        this.navStackAtRoot = to === 'navBar';
        if (this.isWideShell() && to === 'navBar') {
          this.navigationMode = NavigationMode.Stack;
        }
      }
    });
    this.loadTableName();
    this.updateBreakpoint();
    this.startGreetingTicker();
  }

  /** 页面重新显示（含从后台回前台）时立即刷新问候。 */
  onPageShow(): void {
    this.refreshGreeting();
  }

  aboutToDisappear(): void {
    this.stopGreetingTicker();
    this.hdsTabsController.unbindScroller(this.coursesScroller);
    this.hdsTabsController.unbindScroller(this.settingsScroller);
    if (this.boundTimetableScroller !== undefined) {
      this.hdsTabsController.unbindScroller(this.boundTimetableScroller);
      this.boundTimetableScroller = undefined;
    }
  }

  private startGreetingTicker(): void {
    this.refreshGreeting();
    this.greetingTimer = setInterval(() => {
      this.refreshGreeting();
    }, GREETING_REFRESH_INTERVAL_MS);
  }

  private stopGreetingTicker(): void {
    if (this.greetingTimer < 0) {
      return;
    }
    clearInterval(this.greetingTimer);
    this.greetingTimer = -1;
  }

  private refreshGreeting(): void {
    this.greeting = TimeGreeting.current();
  }

  /** 课表页切换周页面时，把当前页的 Scroller 重新绑定给 HdsTabs，并同步给 HdsNavigation 标题栏模糊。 */
  private bindTimetableScroller(scroller: Scroller): void {
    if (this.boundTimetableScroller === scroller) {
      return;
    }
    try {
      if (this.boundTimetableScroller !== undefined) {
        this.hdsTabsController.unbindScroller(this.boundTimetableScroller);
      }
      this.hdsTabsController.bindScroller(0, scroller);
      this.boundTimetableScroller = scroller;
      this.timetableTabScrollables = [scroller];
    } catch (err) {
      console.warn(`[Index] bind timetable scroller failed: ${JSON.stringify(err)}`);
    }
  }

  @Monitor('store.windowWidth')
  onWindowWidthChange(_monitor: IMonitor): void {
    this.updateBreakpoint();
  }

  @Monitor('store.breakpoint')
  private onBreakpointChanged(_monitor: IMonitor): void {
    if (!this.isWideShell()) {
      this.navigationMode = NavigationMode.Stack;
      return;
    }
    // 无子页面时保持全宽主页面；已有子页面时进入分栏。
    this.navigationMode = this.pageStack.getAllPathName().length > 0 ?
      NavigationMode.Split : NavigationMode.Stack;
  }

  private contentTopSpace(): number {
    // 沉浸布局下内容从窗口顶部开始，需要额外让出状态栏高度
    return HdsMetrics.TitleBarHeight + HdsMetrics.TitleBarBreathing + px2vp(this.store.windowTopInset);
  }

  /** 课表 Tab 副标题（与标题栏配置共用，避免两处字符串不一致）。 */
  private timetableSubtitle(): string {
    return `${this.tableName} · 第 ${this.store.tmpWeekIndex} 周`;
  }

  /**
   * 课表页标题 + 副标题的横向触发区宽度。
   * 起始内间距取 HDS 标题栏官方默认值（<600vp 16、<840vp 24、≥840vp 32），
   * 再按文字实测宽度加余量，并限制在页面宽度内。
   */
  private titleHotZoneWidth(): number {
    const pageWidth: number = px2vp(this.store.windowWidth);
    let startPadding: number = 16;
    if (pageWidth >= 840) {
      startPadding = 32;
    } else if (pageWidth >= 600) {
      startPadding = 24;
    }
    const measure = this.getUIContext().getMeasureUtils();
    const titleWidth: number = px2vp(measure.measureText({
      textContent: this.greeting,
      fontSize: FontSize.Headline,
      fontWeight: FontWeight.Medium
    }));
    const subtitleWidth: number = px2vp(measure.measureText({
      textContent: this.timetableSubtitle(),
      fontSize: FontSize.BodySm
    }));
    return Math.min(pageWidth, startPadding + Math.max(titleWidth, subtitleWidth) + Spacing.Xl);
  }

  private updateBreakpoint(): void {
    // 官方断点 API（API 13+），阈值与 WidthBreakpoint 完全一致，避免维护第二套宽度判断。
    const next: BreakpointName = breakpointNameOf(this.getUIContext().getWindowWidthBreakpoint());
    if (next !== this.store.breakpoint) {
      AppState.setBreakpoint(next);
    }
  }

  /** 「课程」Tab 标题栏右上角 +：打开教务导入 / 添加课程小菜单。 */
  private courseMenuContent(): HdsNavigationMenuContentOptions {
    return {
      value: [{
        content: {
          icon: $r('sys.symbol.plus'),
          type: IconStyleMode.NORMAL,
          action: () => {
            this.coursesMenuOpen = !this.coursesMenuOpen;
          }
        }
      }]
    };
  }

  private openImport(): void {
    this.coursesMenuOpen = false;
    ShellRouter.push(this.pageStack, 'import', null);
  }

  private openCreateCourse(): void {
    this.coursesMenuOpen = false;
    ShellRouter.replaceOrPush(this.pageStack, 'course-edit', new CourseEditParam(this.store.tableId, 0));
  }

  private courseMenuItems(): MenuElement[] {
    return [
      {
        value: '教务导入',
        icon: $r('sys.symbol.book_pages'),
        action: () => {
          this.openImport();
        }
      },
      {
        value: '添加课程',
        icon: $r('sys.symbol.plus'),
        action: () => {
          this.openCreateCourse();
        }
      }
    ];
  }

  private async loadTableName(): Promise<void> {
    if (this.store.tableId <= 0) {
      return;
    }
    try {
      const table: CourseTable | null = await CourseTableRepository.getById(this.store.tableId);
      if (table !== null) {
        this.tableName = table.name;
      }
    } catch (err) {
      console.warn(`[Index] load table name failed: ${JSON.stringify(err)}`);
    }
  }

  @Monitor('store.tableId')
  private onTitleTableChanged(_monitor: IMonitor): void {
    this.loadTableName();
  }

  @Monitor('store.dataRevision')
  private onDataRevisionChanged(_monitor: IMonitor): void {
    this.loadTableName();
  }

  /** 底部页签样式：选中态跟随主题强调色（图标 + 文字）。 */
  private bottomTabBar(icon: Resource, label: string): BottomTabBarStyle {
    return new BottomTabBarStyle({
      normal: new SymbolGlyphModifier(icon).fontColor([Colors.TextSecondary]),
      selected: new SymbolGlyphModifier(icon).fontColor([this.store.accentDisplay])
    }, label).labelStyle({
      selectedColor: this.store.accentDisplay,
      unselectedColor: Colors.TextSecondary
    });
  }

  @Builder
  private destinationBuilder(name: string) {
    if (name === 'course-edit') {
      CourseEditPage({ pageStack: this.pageStack })
    } else if (name === 'tables') {
      ManageTablesPage()
    } else if (name === 'more-settings') {
      MoreSettingsPage()
    } else if (name === 'privacy') {
      PrivacyPage({})
    } else if (name === 'about') {
      AboutPage()
    } else if (name === 'licenses') {
      OpenSourceLicensesPage()
    } else if (name === 'acknowledgements') {
      AcknowledgementsPage({})
    } else if (name === 'import') {
      ImportView({ pageStack: this.pageStack })
    } else if (name === 'import-web') {
      ImportWebPage({ pageStack: this.pageStack })
    } else if (name === 'lectures') {
      LecturesPage({})
    } else if (name === 'share') {
      SharePage({})
    } else if (name === 'import-code') {
      ImportCodePage({pageStack: this.pageStack})
    }
  }

  private isWideShell(): boolean {
    return isTabletBreakpoint(this.store.breakpoint as BreakpointName);
  }

  private onTabChanged(index: number): void {
    if (index === this.activeTabIndex) {
      return;
    }
    const previous: number = this.activeTabIndex;
    this.activeTabIndex = index;
    // 同步给 Ability：退到后台时据此决定是否轮播背景。
    AppState.setActiveTabIndex(index);
    this.coursesMenuOpen = false;
    this.navigationMode = NavigationMode.Stack;
    if (this.isWideShell()) {
      this.pageStack.clear();
    } else if (previous === 2) {
      this.pageStack.clear();
    }
    if (index === 0) {
      this.refreshGreeting();
    }
    if (index < 2) {
      this.hdsTabsController.changeIndex(index);
    }
  }

  @Builder
  private tabContents() {
    TabContent() {
      HdsTabPage({
        title: this.greeting,
        subtitle: this.timetableSubtitle(),
        scrollables: this.timetableTabScrollables
      }) {
        TimetableView({
          pageStack: this.pageStack,
          scroller: this.timetableScroller,
          weekScrollers: this.weekScrollers,
          active: this.activeTabIndex === 0,
          onActiveScrollerChange: (scroller: Scroller) => {
            this.bindTimetableScroller(scroller);
          }
        })
      }
    }
    .tabBar(this.bottomTabBar($r('sys.symbol.calendar'), this.tabLabels[0]))

    TabContent() {
      HdsTabPage({
        title: this.tabLabels[1],
        menu: this.courseMenuContent(),
        scrollables: [this.coursesScroller]
      }) {
        CoursesView({ pageStack: this.pageStack, active: this.activeTabIndex === 1,
          tableId: this.store.tableId, scroller: this.coursesScroller })
      }
    }
    .tabBar(this.bottomTabBar($r('sys.symbol.book'), this.tabLabels[1]))

    TabContent() {
      HdsTabPage({
        title: this.tabLabels[2],
        scrollables: [this.settingsScroller]
      }) {
        SettingsView({ pageStack: this.pageStack, scroller: this.settingsScroller })
      }
    }
    .tabBar(this.bottomTabBar($r('sys.symbol.gearshape'), this.tabLabels[2]))
  }

  @Builder
  private narrowTabs() {
    HdsTabs({ controller: this.hdsTabsController, index: this.activeTabIndex }) {
      this.tabContents()
    }
    .animationDuration(0)
    .barHeight(this.is2in1 ? 0 : 56)
    .vertical(false)
    .scrollable(false)
    .barPosition(BarPosition.End)
    // 悬浮胶囊页签栏：需要 barOverlap(true) 才能浮在内容之上
    .barOverlap(true)
    .barFloatingStyle({
      barWidth: { smallWidth: 220, mediumWidth: 300, largeWidth: 360 },
      barBottomMargin: Math.max(px2vp(this.store.windowBottomInset) + 8, 24),
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    })
    .onChange((index: number) => {
      this.onTabChanged(index);
    })
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.Background)
  }

  /** 根 Navigation：宽屏仅在有子页面时切换 Auto/Split。 */
  @Builder
  private contentNavigation() {
    HdsNavigation(this.pageStack) {
      this.narrowTabs()
    }
    .mode(this.navigationMode)
    .navBarWidth(this.splitNavWidth)
    .hideTitleBar(true)
    .navDestination(this.destinationBuilder)
    .width('100%')
    .height('100%')
  }

  @Builder
  private mainContent() {
    Stack() {
      Column() {
        this.contentNavigation()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.Background)

      // 课程页标题栏 + 的展开菜单：透明锚点定位在标题栏右上角下方。
      if (this.activeTabIndex === 1) {
        Row()
          .width(1)
          .height(1)
          .position({
            x: Math.max(0, (this.isWideShell() && this.pageStack.getAllPathName().length > 0 ? this.splitNavWidth : this.getUIContext().px2vp(this.store.windowWidth)) - 32),
            y: this.contentTopSpace() - 2
          })
          .bindMenu(this.coursesMenuOpen, this.courseMenuItems(), {
            placement: Placement.BottomRight,
            onDisappear: () => {
              this.coursesMenuOpen = false;
            }
          })
      }

      // 课表页标题/副标题热区：只覆盖标题文字与副标题的横向范围，不再占满整条标题栏；
      // 子页面或非课表 Tab 时隐藏，避免遮挡返回键和其他标题栏内容。
      if (this.activeTabIndex === 0 && this.navStackAtRoot) {
        Row()
          .width(this.titleHotZoneWidth())
          .height(HdsMetrics.TitleBarHeight)
          .position({ x: 0, y: px2vp(this.store.windowTopInset) })
          .onClick(() => {
            AppState.setWeekPickerOpen(true);
          })
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    if (this.is2in1) {
      SideBarContainer(SideBarContainerType.Embed) {
        DesktopSideBar({
          labels: this.tabLabels,
          icons: this.tabIcons,
          activeIndex: this.activeTabIndex,
          onSelect: (index: number) => {
            this.onTabChanged(index);
          }
        })
        this.mainContent()
      }
      .showSideBar(true)
      .sideBarWidth(240)
      .showControlButton(false)
      .autoHide(false)
      .width('100%')
      .height('100%')
    } else {
      this.mainContent()
    }
  }

}
