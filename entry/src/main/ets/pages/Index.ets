/**
 * 应用外壳：唯一 @Entry。
 *
 * 结构照 `hydrotoolkit-hmos` 的约定：HdsNavigation（系统材质标题栏）+ HdsTabs
 * （底部悬浮胶囊 Tab）+ NavPathStack 路由表。三个主 Tab：课表 / 课程 / 设置。
 *
 * 路由表见 docs/porting/architecture.md。子页面自行提供标题栏
 * （HdsNavDestination / NavDestination 自带 titleBar），这里只负责分发。
 */
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsNavigationTitle,
  HdsNavigationMenuContentOptions,
  HdsTabs,
  HdsTabsController,
  HdsAnimationMode,
  IconStyleMode,
  hdsMaterial,
  ScrollEffectType
} from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { CourseEditParam } from '../common/RouteParams';
import { AppState } from '../app/AppState';
import { AppStore } from '../app/AppStore';
import { TabBarAutoHide } from '../common/ui/TabBarAutoHide';

import { CourseTableRepository } from '../data/CourseTableRepository';
import { CourseTable } from '../data/models/Models';
import { BreakpointName, resolveBreakpoint } from '../common/design/Breakpoints';
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
  /** 「课程」Tab 标题栏 + 菜单是否展开。 */
  @Local coursesMenuOpen: boolean = false;

  /** V2 全局 Store。 */
  @Local store: AppStore = AppStore.connect();
  /** 当前课表名（标题栏副标题显示「课表名 + 第 N 周」）。 */
  @Local tableName: string = '我的课表';
  @Local activeTabIndex: number = 0;
  /** HDS 导航是否停留在根页面（没有子页面）。 */
  @Local navStackAtRoot: boolean = true;
  /** 只把「当前 Tab 正在使用的」Scroller 绑定给 HdsNavigation（官方 FAQ 场景二），避免 25 个周页面互相干扰。 */
  @Local navScrollables: Scroller[] = [];
  /** 当前绑定给课表 Tab 的滚动容器（25 个周页面轮换）。 */
  private boundTimetableScroller: Scroller | undefined = undefined;

  aboutToAppear(): void {
    for (let i = 0; i < 25; i++) {
      this.weekScrollers.push(new Scroller());
    }
    this.hdsTabsController.bindScroller(1, this.coursesScroller);
    this.hdsTabsController.bindScroller(2, this.settingsScroller);
    this.navScrollables = [this.timetableScroller];
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

  /** 滚动方向变化 → HDS 页签栏显隐动画（官方 HdsTabsController.applyHide/ShowAnimation）。 */
  @Monitor('store.tabBarHidden')
  private onTabBarHiddenChanged(_monitor: IMonitor): void {
    try {
      if (this.store.tabBarHidden) {
        this.hdsTabsController.applyHideAnimation(HdsAnimationMode.SCROLL_ANIMATION);
      } else {
        this.hdsTabsController.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION);
      }
    } catch (err) {
      console.warn(`[Index] tab bar animation failed: ${JSON.stringify(err)}`);
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
      if (this.activeTabIndex === 0) {
        this.navScrollables = [scroller];
      }
    } catch (err) {
      console.warn(`[Index] bind timetable scroller failed: ${JSON.stringify(err)}`);
    }
  }

  /** 当前 Tab 对应的滚动容器（HdsNavigation 标题栏模糊只绑当前这一个，官方 FAQ 场景二）。 */
  private currentTabScroller(): Scroller[] {
    if (this.activeTabIndex === 0) {
      const active: Scroller = this.boundTimetableScroller !== undefined ?
        this.boundTimetableScroller : this.timetableScroller;
      return [active];
    }
    if (this.activeTabIndex === 1) {
      return [this.coursesScroller];
    }
    return [this.settingsScroller];
  }

  @Monitor('store.windowWidth')
  onWindowWidthChange(_monitor: IMonitor): void {
    this.updateBreakpoint();
  }

  private contentTopSpace(): number {
    // 沉浸布局下内容从窗口顶部开始，需要额外让出状态栏高度
    return HdsMetrics.TitleBarHeight + HdsMetrics.TitleBarBreathing + px2vp(this.store.windowTopInset);
  }

  private updateBreakpoint(): void {
    const widthVp: number = this.store.windowWidth > 0 ? this.getUIContext().px2vp(this.store.windowWidth) : 360;
    const next: BreakpointName = resolveBreakpoint(widthVp);
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

  /** 标题栏标题内容：课表页不显示副标题（由 bottomBuilder 取代），其他 Tab 仍显示 Tab 名。 */
  private titleContent(): HdsNavigationTitle {
    if (this.activeTabIndex === 0) {
      // 直接替换原来的「课表」副标题：课表名 + 当前周（点击由顶部透明热区打开周次选择器）
      return { mainTitle: '呢喃课表', subTitle: `${this.tableName} · 第 ${this.store.tmpWeekIndex} 周` };
    }
    return { mainTitle: '呢喃课表', subTitle: this.tabLabels[this.activeTabIndex] };
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
      ManageTablesPage({pageStack: this.pageStack})
    } else if (name === 'more-settings') {
      MoreSettingsPage()
    } else if (name === 'privacy') {
      PrivacyPage({})
    } else if (name === 'about') {
      AboutPage({pageStack: this.pageStack})
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

  build() {
    Stack() {
      Column() {
      HdsNavigation(this.pageStack) {
        HdsTabs({ controller: this.hdsTabsController }) {
          TabContent() {
            Column() {
              TimetableView({
                pageStack: this.pageStack,
                active: this.activeTabIndex === 0,
                scroller: this.timetableScroller,
                weekScrollers: this.weekScrollers,
                onActiveScrollerChange: (scroller: Scroller) => {
                  this.bindTimetableScroller(scroller);
                }
              })
            }
            .width('100%')
            .height('100%')
            .padding({ top: 0 })
            .backgroundColor(Colors.Background)
          }
          .tabBar(this.bottomTabBar($r('sys.symbol.calendar'), this.tabLabels[0]))

          TabContent() {
            Column() {
              CoursesView({ pageStack: this.pageStack, active: this.activeTabIndex === 1, tableId: this.store.tableId, scroller: this.coursesScroller })
            }
            .width('100%')
            .height('100%')
            .padding({ top: 0 })
            .backgroundColor(Colors.Background)
          }
          .tabBar(this.bottomTabBar($r('sys.symbol.book'), this.tabLabels[1]))

          TabContent() {
            Column() {
              SettingsView({ pageStack: this.pageStack, scroller: this.settingsScroller })
            }
            .width('100%')
            .height('100%')
            .padding({ top: 0 })
            .backgroundColor(Colors.Background)
          }
          .tabBar(this.bottomTabBar($r('sys.symbol.gearshape'), this.tabLabels[2]))
        }
        .animationDuration(250)
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
          this.activeTabIndex = index;
          this.coursesMenuOpen = false;
          // 切 Tab 时恢复悬浮页签（避免在别的页面保持收起状态）
          TabBarAutoHide.resetAndShow();
          // 标题栏模糊只绑定当前 Tab 的滚动容器
          this.navScrollables = this.currentTabScroller();
        })
        .width('100%')
        .height('100%')
        .backgroundColor(Colors.Background)
      }
      .mode(NavigationMode.Stack)
      .hideBackButton(true)
      .titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({
        avoidLayoutSafeArea: true,
        content: {
          title: this.titleContent(),
          menu: this.activeTabIndex === 1 ? this.courseMenuContent() : undefined
        },
        style: {
          // 与 hydrotoolkit 相同：静止透明，内容滚到标题栏下方时渐变模糊
          scrollEffectOpts: {
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR
          },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
        }
      })
      .bindToScrollable(this.navScrollables)
      .navDestination(this.destinationBuilder)
      .width('100%')
      .height('100%')
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
}
