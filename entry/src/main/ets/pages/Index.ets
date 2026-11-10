/**
 * 应用外壳：唯一 @Entry。
 *
 * 结构：HdsNavigation 不显示根标题栏，HdsTabs 提供底部胶囊导航；
 * 三个一级 Tab 各自用 HdsNavDestination 提供标题栏。
 * 设置 Tab 在宽屏进入 Auto/Split，设置详情与普通子页面统一走 NavPathStack。
 *
 * 路由表见 docs/porting/architecture.md。子页面自行提供标题栏，
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
import { deviceInfo } from '@kit.BasicServicesKit';
import { CourseEditParam } from '../common/RouteParams';
import { AppState } from '../app/AppState';
import { AppStore } from '../app/AppStore';
import { HdsTabPage } from '../common/ui/HdsTabPage';
import { DesktopSideBar } from '../common/ui/DesktopSideBar';

import { CourseTableRepository } from '../data/CourseTableRepository';
import { CourseTable } from '../data/models/Models';
import { BreakpointName, breakpointNameOf, isTabletBreakpoint } from '../common/design/Breakpoints';
import { Colors, HdsMetrics } from '../common/design/Tokens';
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
import { SETTINGS_EMPTY_ROUTE } from '../common/RouteParams';
import { TimetableView } from '../features/timetable/TimetableView';

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
  private readonly is2in1: boolean = deviceInfo.deviceType === '2in1';
  /** 「课程」Tab 标题栏 + 菜单是否展开。 */
  @Local coursesMenuOpen: boolean = false;

  /** V2 全局 Store。 */
  @Local store: AppStore = AppStore.connect();
  /** 当前课表名（标题栏副标题显示「课表名 + 第 N 周」）。 */
  @Local tableName: string = '我的课表';
  @Local activeTabIndex: number = 0;
  /** 设置 Tab 在宽屏进入 Auto/Split，其余 Tab 保持 Stack。 */
  @Local navigationMode: NavigationMode = NavigationMode.Stack;
  /** HDS 导航是否停留在根页面（没有子页面）。 */
  @Local navStackAtRoot: boolean = true;
  /** 当前绑定给课表 Tab 的滚动容器（25 个周页面轮换）。 */
  private boundTimetableScroller: Scroller | undefined = undefined;
  /** 课表 Tab 当前周页面滚动容器，供 HdsNavDestination 标题栏模糊联动。 */
  @Local timetableTabScrollables: Scroller[] = [];

  aboutToAppear(): void {
    for (let i = 0; i < 25; i++) {
      this.weekScrollers.push(new Scroller());
    }
    const initialWeek: number = Math.max(0, Math.min(this.store.tmpWeekIndex - 1, this.weekScrollers.length - 1));
    this.timetableTabScrollables = [this.weekScrollers[initialWeek]];
    this.hdsTabsController.bindScroller(1, this.coursesScroller);
    this.hdsTabsController.bindScroller(2, this.settingsScroller);
    // 跟踪子页面进出：只有根页面显示标题栏副标题热区，避免挡住子页面返回键。
    this.pageStack.setInterception({
      didShow: (from: NavDestinationContext | NavBar, to: NavDestinationContext | NavBar) => {
        this.navStackAtRoot = to === 'navBar';
      }
    });
    this.loadTableName();
    this.updateBreakpoint();
  }

  aboutToDisappear(): void {
    this.hdsTabsController.unbindScroller(this.coursesScroller);
    this.hdsTabsController.unbindScroller(this.settingsScroller);
    if (this.boundTimetableScroller !== undefined) {
      this.hdsTabsController.unbindScroller(this.boundTimetableScroller);
      this.boundTimetableScroller = undefined;
    }
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

  /** Settings Split 的栈底空页：模式切换或设置页真正显示时触发一次。 */
  private ensureSettingsBase(): void {
    if (!this.isWideShell() || this.activeTabIndex !== 2) {
      return;
    }
    if (this.pageStack.getAllPathName().length === 0) {
      this.pageStack.pushPathByName(SETTINGS_EMPTY_ROUTE, null, false);
    }
  }

  @Monitor('store.breakpoint')
  private onBreakpointChanged(_monitor: IMonitor): void {
    if (!this.isWideShell()) {
      this.navigationMode = NavigationMode.Stack;
      if (this.activeTabIndex === 2) {
        this.pageStack.clear();
      }
      return;
    }
    if (this.activeTabIndex === 2) {
      this.navigationMode = NavigationMode.Auto;
      this.pageStack.clear();
      this.pageStack.pushPathByName(SETTINGS_EMPTY_ROUTE, null, false);
    } else {
      this.navigationMode = NavigationMode.Stack;
      this.pageStack.clear();
    }
  }

  private contentTopSpace(): number {
    // 沉浸布局下内容从窗口顶部开始，需要额外让出状态栏高度
    return HdsMetrics.TitleBarHeight + HdsMetrics.TitleBarBreathing + px2vp(this.store.windowTopInset);
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
    this.pageStack.pushPathByName('import', null);
  }

  private openCreateCourse(): void {
    this.coursesMenuOpen = false;
    this.pageStack.pushPathByName('course-edit', new CourseEditParam(this.store.tableId, 0));
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
    } else if (name === SETTINGS_EMPTY_ROUTE) {
      HdsNavDestination() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Colors.Background)
      }
      .hideTitleBar(true)
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
    this.coursesMenuOpen = false;
    if (this.isWideShell()) {
      if (index === 2) {
        this.navigationMode = NavigationMode.Auto;
      } else {
        this.navigationMode = NavigationMode.Stack;
      }
      this.pageStack.clear();
    } else {
      this.navigationMode = NavigationMode.Stack;
      if (previous === 2) {
        this.pageStack.clear();
      }
    }
    if (index < 2) {
      this.hdsTabsController.changeIndex(index);
    }
  }

  @Builder
  private tabContents() {
    TabContent() {
      HdsTabPage({
        title: '呢喃课表',
        subtitle: `${this.tableName} · 第 ${this.store.tmpWeekIndex} 周`,
        scrollables: this.timetableTabScrollables
      }) {
        TimetableView({
          pageStack: this.pageStack,
          scroller: this.timetableScroller,
          weekScrollers: this.weekScrollers,
          onActiveScrollerChange: (scroller: Scroller) => {
            this.bindTimetableScroller(scroller);
          }
        })
      }
    }
    .tabBar(this.bottomTabBar($r('sys.symbol.calendar'), this.tabLabels[0]))

    TabContent() {
      HdsTabPage({
        title: '呢喃课表',
        subtitle: this.tabLabels[1],
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
        title: '呢喃课表',
        subtitle: this.tabLabels[2],
        scrollables: [this.settingsScroller]
      }) {
        SettingsView({ pageStack: this.pageStack, scroller: this.settingsScroller })
      }
    }
    .onWillShow(() => {
      this.ensureSettingsBase();
    })
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

  /** 根 Navigation：不显示标题栏；仅设置 Tab 在宽屏进入 Auto/Split。 */
  @Builder
  private contentNavigation() {
    HdsNavigation(this.pageStack) {
      this.narrowTabs()
    }
    .mode(this.navigationMode)
    .navBarWidth(420)
    .hideTitleBar(true)
    .onNavigationModeChange((mode: NavigationMode) => {
      if (mode === NavigationMode.Split) {
        this.ensureSettingsBase();
      }
    })
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
            x: Math.max(0, this.getUIContext().px2vp(this.store.windowWidth) - 32),
            y: this.contentTopSpace() - 2
          })
          .bindMenu(this.coursesMenuOpen, this.courseMenuItems(), {
            placement: Placement.BottomRight,
            onDisappear: () => {
              this.coursesMenuOpen = false;
            }
          })
      }

      // 课表页副标题热区：放在 HDS 标题栏之上，避免标题栏材质/滚动状态影响命中率；
      // 子页面或非课表 Tab 时隐藏，避免遮挡返回键和其他标题栏内容。
      if (this.activeTabIndex === 0 && this.navStackAtRoot) {
        Row()
          .width('100%')
          .height(30)
          .position({ x: 0, y: this.contentTopSpace() - 30 })
          .hitTestBehavior(HitTestMode.Default)
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
