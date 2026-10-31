/**
 * 设置 Tab 页（挂在 HdsTabs 的「设置」TabContent 里，标题由外壳 HdsNavigation 提供）。
 *
 * 分区：
 * ① 课表      —— 当前课表名 + 课表管理入口（tables 路由）
 * ② 时间      —— 当前周：加减 / 拖动滑块直接设置
 * ③ 显示      —— 周末、节次时间、自由时间、日期开关 + 课程高度（36-80）
 * ④ 分享与迁移 —— 分享课表（share 路由）
 * ⑤ 危险操作   —— 清空当前课表课程（二次确认）
 * ⑥ 更多      —— 讲座（lectures）、自定义外观（more-settings）、关于（about，最底部）
 *
 * 状态约定（见 docs/porting/architecture.md 与 AGENTS.md）：
 * - 显示类配置以 `AppStore` 为运行时真源（Bootstrap 已用 prefs 初始化），
 *   改动时同步写 preferences 持久化，页面通过 `@Local store` 自动响应。
 * - 当前周改动写 prefs（WeekUtil.setNowWeek）后再写 AppState。
 */
import { TabBarAutoHide } from '../../common/ui/TabBarAutoHide';
import { AppPreferences, PrefKeys } from '../../app/AppPreferences';
import { AppState } from '../../app/AppState';
import { AppStore } from '../../app/AppStore';
import { LegacyConfig } from '../../common/Constants';
import { Colors, FontSize, HdsMetrics, Radius, Spacing, TimetableMetrics } from '../../common/design/Tokens';
import { Feedback } from '../../common/ui/Feedback';
import { AppCard } from '../../common/ui/AppCard';
import { SectionHeader } from '../../common/ui/SectionHeader';
import { CourseTable } from '../../data/models/Models';
import { CourseTableRepository } from '../../data/CourseTableRepository';
import { CourseRepository } from '../../data/CourseRepository';
import { WeekUtil } from '../../data/WeekUtil';
import {
  SettingsRow,
  SettingsRowDivider,
  SettingsStepper,
  SettingsSwitchRow
} from './SettingsCommon';

/** 课表管理路由名（与 pages/Index.ets 的 destinationBuilder 约定一致）。 */
const ROUTE_TABLES: string = 'tables';
const ROUTE_MORE_SETTINGS: string = 'more-settings';
const ROUTE_ABOUT: string = 'about';
const ROUTE_LECTURES: string = 'lectures';

@ComponentV2
export struct SettingsView {
  /** V2 全局 Store（主题色、周次、显示配置等）。 */
  @Local store: AppStore = AppStore.connect();
  /** 外壳注入的导航栈，用于 push 子页面。 */
  @Param pageStack: NavPathStack = new NavPathStack();
  /** 外壳注入的当前课表 id（Store 未就绪时的兜底）。 */
  @Param tableId: number = 0;
  /** 外壳可传入自己的 Scroller（用于标题栏滚动模糊联动）；不传时用内置的。 */
  @Param scroller: Scroller = new Scroller();

  @Local tableName: string = '';
  /** 当前课表课程数（危险操作说明用）。 */
  @Local courseCount: number = 0;
  /** 「直接设置」行实时显示的周数（不是气泡，保留）。 */
  @Local weekSliderTip: number = 1;
  /** 设置页滚动中：滚动时临时关闭 Slider 点击跳变，避免下滑时误触（官方 FAQ faqs-arkui-1107）。 */
  @Local pageScrolling: boolean = false;

  aboutToAppear(): void {
    TabBarAutoHide.resetAndShow();
    this.weekSliderTip = this.store.weekIndex;
    this.reloadTableName();
    this.reloadCourseCount();
  }

  @Monitor('store.tableId')
  private onStoreTableIdChanged(_monitor: IMonitor): void {
    this.reloadTableName();
    this.reloadCourseCount();
  }

  @Monitor('store.weekIndex')
  private onStoreWeekIndexChanged(_monitor: IMonitor): void {
    this.weekSliderTip = this.store.weekIndex;
  }

  @Monitor('store.dataRevision')
  private onStoreDataRevisionChanged(_monitor: IMonitor): void {
    // 课表重命名/切换/课程增删后同步当前课表名。
    this.reloadTableName();
    this.reloadCourseCount();
  }

  private currentTableId(): number {
    return this.store.tableId > 0 ? this.store.tableId : this.tableId;
  }

  private async reloadTableName(): Promise<void> {
    try {
      const table: CourseTable | null = await CourseTableRepository.getById(this.currentTableId());
      this.tableName = table === null ? '' : table.name;
    } catch (err) {
      console.error(`[Settings] 读取当前课表失败: ${JSON.stringify(err)}`);
    }
  }


  private clampWeek(week: number): number {
    if (week < 1) {
      return 1;
    }
    if (week > LegacyConfig.MAX_WEEKS) {
      return LegacyConfig.MAX_WEEKS;
    }
    return week;
  }

  private stepWeek(delta: number): void {
    const next: number = this.clampWeek(this.store.weekIndex + delta);
    if (next === this.store.weekIndex) {
      return;
    }
    this.commitWeek(next);
  }

  /** 当前周落库：WeekUtil 负责重算学期起始周一，AppState 负责运行时状态。 */
  private async commitWeek(week: number): Promise<void> {
    const target: number = this.clampWeek(week);
    const changed: boolean = target !== this.store.weekIndex;
    try {
      await WeekUtil.setNowWeek(target);
      await AppState.setCurrentWeek(target);
      if (changed) {
        Feedback.toast(this.getUIContext(), `当前周已设为第 ${target} 周`);
      }
    } catch (err) {
      console.error(`[Settings] 保存当前周失败: ${JSON.stringify(err)}`);
    }
  }

  /** 显示开关统一写 preferences（运行时状态已由 AppState setter 写入 AppStore）。 */
  private async putBoolPref(key: string, value: boolean): Promise<void> {
    try {
      await AppPreferences.put(key, value);
    } catch (err) {
      console.error(`[Settings] 保存显示配置失败: ${JSON.stringify(err)}`);
    }
  }

  private async setShowWeekend(value: boolean): Promise<void> {
    AppState.setShowWeekend(value);
    await this.putBoolPref(PrefKeys.ShowWeekend, value);
    await AppState.bumpDataRevision();
  }

  private async setShowClassTime(value: boolean): Promise<void> {
    AppState.setShowClassTime(value);
    await this.putBoolPref(PrefKeys.ShowClassTime, value);
  }

  private async setShowFreeClass(value: boolean): Promise<void> {
    AppState.setShowFreeClass(value);
    await this.putBoolPref(PrefKeys.ShowFreeClass, value);
  }

  private async setShowDate(value: boolean): Promise<void> {
    AppState.setShowDate(value);
    await this.putBoolPref(PrefKeys.ShowDate, value);
  }

  @Builder
  private tableSection(): void {
    SectionHeader({ title: '课表' })
    AppCard({ contentPadding: 0 }) {
      SettingsRow({
        icon: $r('sys.symbol.calendar'),
        title: this.tableName === '' ? '当前课表' : this.tableName,
        trailingText: '课表管理',
        onTap: () => {
          this.pageStack.pushPathByName(ROUTE_TABLES, null);
        }
      })
    }
  }

  @Builder
  private weekSection(): void {
    SectionHeader({ title: '时间' })
    AppCard({ contentPadding: 0 }) {
      Column() {
        Row({ space: Spacing.Md }) {
          SymbolGlyph($r('sys.symbol.calendar_badge_clock'))
            .fontSize(20)
            .fontColor([Colors.TextSecondary])
          Column({ space: 2 }) {
            Text('当前周')
              .fontSize(FontSize.Body)
              .fontColor(Colors.TextPrimary)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          SettingsStepper({
            value: this.store.weekIndex,
            minValue: 1,
            maxValue: LegacyConfig.MAX_WEEKS,
            displayText: `第 ${this.store.weekIndex} 周`,
            onStep: (delta: number) => {
              this.stepWeek(delta);
            }
          })
        }
        .width('100%')
        .padding({ left: Spacing.Lg, right: Spacing.Lg, top: Spacing.Md, bottom: Spacing.Md })
        .alignItems(VerticalAlign.Center)

        SettingsRowDivider()

        Column({ space: Spacing.Xs }) {
          Row() {
            Text('滑动设置')
              .fontSize(FontSize.BodySm)
              .fontColor(Colors.TextSecondary)
            Blank()
            Text(`第 ${this.weekSliderTip} 周`)
              .fontSize(FontSize.Caption)
              .fontColor(this.store.accentDisplay)
          }
          .width('100%')

          Slider({
            value: this.store.weekIndex,
            min: 1,
            max: LegacyConfig.MAX_WEEKS,
            step: 1,
            style: SliderStyle.OutSet
          })
            .selectedColor(this.store.accentDisplay)
            .width('100%')
            .trackColor(Colors.SurfaceHigh)
            .blockColor(Colors.Surface)
            .showTips(false)
            // 滚动中只允许滑动、不允许点击跳变，避免上下滑页面时误触
            .sliderInteractionMode(this.pageScrolling ? SliderInteraction.SLIDE_ONLY :
              SliderInteraction.SLIDE_AND_CLICK_UP)
            .onChange((value: number, mode: SliderChangeMode) => {
              const week: number = Math.round(value);
              this.weekSliderTip = week;
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.commitWeek(week);
              }
            })
        }
        .width('100%')
        .padding({ left: Spacing.Lg, right: Spacing.Lg, top: Spacing.Md, bottom: Spacing.Lg })
      }
      .width('100%')
    }
  }

  @Builder
  private displaySection(): void {
    SectionHeader({ title: '显示' })
    AppCard({ contentPadding: 0 }) {
      Column() {
        SettingsSwitchRow({
          icon: $r('sys.symbol.calendar_badge_checkmark'),
          title: '显示周末',
          isOn: this.store.showWeekend,
          onToggle: (isOn: boolean) => {
            this.setShowWeekend(isOn);
          }
        })
        SettingsRowDivider()
        SettingsSwitchRow({
          icon: $r('sys.symbol.clock'),
          title: '显示节次时间',
          isOn: this.store.showClassTime,
          onToggle: (isOn: boolean) => {
            this.setShowClassTime(isOn);
          }
        })
        SettingsRowDivider()
        SettingsSwitchRow({
          icon: $r('sys.symbol.timer'),
          title: '显示自由时间课程',
          isOn: this.store.showFreeClass,
          onToggle: (isOn: boolean) => {
            this.setShowFreeClass(isOn);
          }
        })
        SettingsRowDivider()
        SettingsSwitchRow({
          icon: $r('sys.symbol.calendar_1'),
          title: '显示日期',
          isOn: this.store.showDate,
          onToggle: (isOn: boolean) => {
            this.setShowDate(isOn);
          }
        })
        SettingsRowDivider()

        ClassHeightControl({
          pageScrolling: this.pageScrolling,
          onCommit: (height: number): void => {
            this.persistClassHeight(height);
          }
        })
      }
      .width('100%')
    }
  }

  private async persistClassHeight(height: number): Promise<void> {
    try {
      await AppPreferences.setClassHeight(height);
    } catch (err) {
      console.error(`[Settings] 保存课程高度失败: ${JSON.stringify(err)}`);
    }
  }

  @Builder
  private shareSection(): void {
    SectionHeader({ title: '分享与迁移' })
    AppCard({ contentPadding: 0 }) {
      SettingsRow({
        icon: $r('sys.symbol.share'),
        title: '分享当前课表',
        showArrow: false,
        subtitle: '生成二维码或分享码，可导入到 Flutter 版 / 其他设备',
        onTap: () => {
          this.pageStack.pushPathByName('share', null);
        }
      })
    }
  }

  @Builder
  private dangerSection(): void {
    SectionHeader({ title: '危险操作' })
    AppCard({ contentPadding: 0 }) {
      SettingsRow({
        icon: $r('sys.symbol.trash'),
        title: '清空当前课表课程',
        showArrow: false,
        subtitle: `删除「${this.tableName === '' ? '当前课表' : this.tableName}」中的全部 ${this.courseCount} 节课程，保留课表本身`,
        danger: true,
        onTap: () => {
          this.confirmClearCourses();
        }
      })
    }
  }

  private async reloadCourseCount(): Promise<void> {
    try {
      this.courseCount = (await CourseRepository.getAll(AppState.effectiveTableId(this.tableId))).length;
    } catch (err) {
      console.error(`[Settings] 读取课程数量失败: ${JSON.stringify(err)}`);
    }
  }

  private async clearCourses(): Promise<void> {
    try {
      await CourseRepository.deleteByTable(AppState.effectiveTableId(this.tableId));
      await AppState.bumpDataRevision();
      this.courseCount = 0;
      Feedback.toast(this.getUIContext(), '已清空当前课表课程');
    } catch (err) {
      console.error(`[Settings] 清空课程失败: ${JSON.stringify(err)}`);
      Feedback.toast(this.getUIContext(), '清空课程失败');
    }
  }

  private confirmClearCourses(): void {
    if (this.courseCount === 0) {
      Feedback.toast(this.getUIContext(), '当前课表没有课程');
      return;
    }
    const tableLabel: string = this.tableName === '' ? '当前课表' : `「${this.tableName}」`;
    Feedback.confirmDanger(this.getUIContext(), '清空课程', `将删除${tableLabel}中的全部 ${this.courseCount} 节课程，此操作无法恢复。`, '清空', () => {
      this.clearCourses();
    });
  }

  @Builder
  private moreSection(): void {
    SectionHeader({ title: '更多' })
    AppCard({ contentPadding: 0 }) {
      SettingsRow({
        icon: $r('sys.symbol.graduationcap'),
        title: '讲座',
        subtitle: '查看南大近期讲座，一键加入课表',
        onTap: () => {
          this.pageStack.pushPathByName(ROUTE_LECTURES, null);
        }
      })
      SettingsRowDivider()
      SettingsRow({
        icon: $r('sys.symbol.paintbrush'),
        title: '自定义外观',
        subtitle: '课表背景、外观模式与主题色',
        onTap: () => {
          this.pageStack.pushPathByName(ROUTE_MORE_SETTINGS, null);
        }
      })
      SettingsRowDivider()
      SettingsRow({
        icon: $r('sys.symbol.info_circle'),
        title: '关于',
        subtitle: '版本信息、开源地址与开源许可',
        onTap: () => {
          this.pageStack.pushPathByName(ROUTE_ABOUT, null);
        }
      })
    }
  }

  build() {
    Column() {
      Scroll(this.scroller) {
        Column() {
          Column({ space: Spacing.Lg }) {
            this.tableSection()
            this.weekSection()
            this.displaySection()
            this.shareSection()
            this.dangerSection()
            this.moreSection()
          }
          .width('100%')
          .constraintSize({ maxWidth: 800 })
          .padding({
            left: Spacing.Lg,
            right: Spacing.Lg,
            top: HdsMetrics.TitleBarHeight + HdsMetrics.TitleBarBreathing + px2vp(this.store.windowTopInset),
            bottom: 120
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      // 下滑收起悬浮页签、上滑恢复；回到顶部一定恢复
      .onScrollStart(() => {
        this.pageScrolling = true;
      })
      .onScrollStop(() => {
        this.pageScrolling = false;
      })
      .onDidScroll((xOffset: number, yOffset: number) => {
        TabBarAutoHide.onScroll(this.scroller);
      })
      .onReachStart(() => {
        TabBarAutoHide.resetAndShow();
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.Background)
  }
}

/**
 * 课程高度滑杆（独立组件，避免拖动时重建整个设置页）。
 *
 * 拖动过程中只改本地 draft（只重绘这个小组件）；松手/点击才写全局 Store 与落库。
 * 否则每个 tick 都通知课表页（25 个周页面）重排，表现为拖动极其卡顿。
 */
@ComponentV2
struct ClassHeightControl {
  @Local store: AppStore = AppStore.connect();
  @Local draft: number = TimetableMetrics.DefaultClassHeight;
  /** 父页面滚动中：滚动时关闭 Slider 点击跳变，避免误触。 */
  @Param pageScrolling: boolean = false;
  @Event onCommit: (height: number) => void = () => {
  };

  aboutToAppear(): void {
    this.draft = this.store.classHeight;
  }

  @Monitor('store.classHeight')
  private onStoreClassHeightChanged(_monitor: IMonitor): void {
    this.draft = this.store.classHeight;
  }

  build() {
    Column({ space: Spacing.Xs }) {
      Row({ space: Spacing.Md }) {
        SymbolGlyph($r('sys.symbol.arrow_up_and_down_square_portrait'))
          .fontSize(20)
          .fontColor([Colors.TextSecondary])
        Column({ space: 2 }) {
          Text('课程高度')
            .fontSize(FontSize.Body)
            .fontColor(Colors.TextPrimary)
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(`${this.draft}`)
          .fontSize(FontSize.Body)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.store.accentDisplay)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Slider({
        value: this.draft,
        min: TimetableMetrics.MinClassHeight,
        max: TimetableMetrics.MaxClassHeight,
        step: 1,
        style: SliderStyle.OutSet
      })
        .selectedColor(this.store.accentDisplay)
        .width('100%')
        .trackColor(Colors.SurfaceHigh)
        .blockColor(Colors.Surface)
        .showTips(false)
        // 滚动中只允许滑动、不允许点击跳变，避免上下滑页面时误触
        .sliderInteractionMode(this.pageScrolling ? SliderInteraction.SLIDE_ONLY :
          SliderInteraction.SLIDE_AND_CLICK_UP)
        .onChange((value: number, mode: SliderChangeMode) => {
          const height: number = Math.round(value);
          if (height !== this.draft) {
            this.draft = height;
          }
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            AppState.setClassHeight(height);
            this.onCommit(height);
          }
        })
    }
    .width('100%')
    .padding({ left: Spacing.Lg, right: Spacing.Lg, top: Spacing.Md, bottom: Spacing.Lg })
  }
}
