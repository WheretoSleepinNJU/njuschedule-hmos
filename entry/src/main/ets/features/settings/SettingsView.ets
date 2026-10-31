/**
 * 设置 Tab 页（挂在 HdsTabs 的「设置」TabContent 里，标题由外壳 HdsNavigation 提供）。
 *
 * 分区：
 * ① 课表      —— 当前课表名 + 课表管理、当前周（每个课表独立保存）
 * ② 显示      —— 周末、节次时间、自由时间、日期开关 + 课程高度（官方滑动选择器）
 * ③ 更多      —— 分享课表（share）、讲座（lectures）、自定义外观（more-settings）、关于（about）
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
import { Colors, HdsMetrics, Spacing, TimetableMetrics } from '../../common/design/Tokens';
import { Feedback } from '../../common/ui/Feedback';
import { CourseTable } from '../../data/models/Models';
import { CourseTableRepository } from '../../data/CourseTableRepository';
import { WeekUtil } from '../../data/WeekUtil';
import {
  SettingsItemDivider,
  SettingsItemGroup,
  SettingsRow,
  SettingsSwitchRow
} from '../../common/ui/SettingsListItems';

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
  aboutToAppear(): void {
    TabBarAutoHide.resetAndShow();
    this.reloadTableName();
  }

  @Monitor('store.tableId')
  private onStoreTableIdChanged(_monitor: IMonitor): void {
    this.reloadTableName();
  }

  @Monitor('store.dataRevision')
  private onStoreDataRevisionChanged(_monitor: IMonitor): void {
    // 课表重命名/切换/课程增删后同步当前课表名。
    this.reloadTableName();
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

  /** 当前周落库：WeekUtil 负责重算学期起始周一，AppState 负责运行时状态。 */
  private async commitWeek(week: number): Promise<void> {
    const target: number = this.clampWeek(week);
    const changed: boolean = target !== this.store.weekIndex;
    try {
      await WeekUtil.setNowWeek(target, this.currentTableId());
      await AppState.setCurrentWeek(target);
      if (changed) {
        Feedback.toast(this.getUIContext(), `当前周已设为第 ${target} 周`);
      }
    } catch (err) {
      console.error(`[Settings] 保存当前周失败: ${JSON.stringify(err)}`);
    }
  }

  private weekChoices(): string[] {
    const choices: string[] = [];
    for (let i = 1; i <= LegacyConfig.MAX_WEEKS; i++) {
      choices.push(`第 ${i} 周`);
    }
    return choices;
  }

  private heightChoices(): string[] {
    const choices: string[] = [];
    for (let h = TimetableMetrics.MinClassHeight; h <= TimetableMetrics.MaxClassHeight; h++) {
      choices.push(`${h}`);
    }
    return choices;
  }

  private openWeekPicker(): void {
    const selected: number = Math.max(0, Math.min(this.store.weekIndex - 1, LegacyConfig.MAX_WEEKS - 1));
    this.getUIContext().showTextPickerDialog({
      range: this.weekChoices(),
      selected: selected,
      canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const index: number = Array.isArray(result.index) ? result.index[0] : result.index as number;
        this.commitWeek(index + 1);
      }
    });
  }

  private openClassHeightPicker(): void {
    const current: number = Math.max(TimetableMetrics.MinClassHeight,
      Math.min(this.store.classHeight, TimetableMetrics.MaxClassHeight));
    this.getUIContext().showTextPickerDialog({
      range: this.heightChoices(),
      selected: current - TimetableMetrics.MinClassHeight,
      canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const index: number = Array.isArray(result.index) ? result.index[0] : result.index as number;
        const height: number = TimetableMetrics.MinClassHeight + index;
        AppState.setClassHeight(height);
        this.persistClassHeight(height);
      }
    });
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
    ListItem() {
      SettingsItemGroup({ title: '课表' }) {
        SettingsRow({
          icon: $r('sys.symbol.calendar'),
          title: this.tableName === '' ? '当前课表' : this.tableName,
          trailingText: '课表管理',
          onTap: () => {
            this.pageStack.pushPathByName(ROUTE_TABLES, null);
          }
        })
        SettingsItemDivider()
        SettingsRow({
          icon: $r('sys.symbol.calendar_badge_clock'),
          title: '当前周',
          trailingText: `第 ${this.store.weekIndex} 周`,
          onTap: () => {
            this.openWeekPicker();
          }
        })
      }
    }
  }

  @Builder
  private displaySection(): void {
    ListItem() {
      SettingsItemGroup({ title: '显示' }) {
        SettingsSwitchRow({
          icon: $r('sys.symbol.calendar_badge_checkmark'),
          title: '显示周末',
          isOn: this.store.showWeekend,
          onToggle: (isOn: boolean) => {
            this.setShowWeekend(isOn);
          }
        })
        SettingsItemDivider()
        SettingsSwitchRow({
          icon: $r('sys.symbol.clock'),
          title: '显示节次时间',
          isOn: this.store.showClassTime,
          onToggle: (isOn: boolean) => {
            this.setShowClassTime(isOn);
          }
        })
        SettingsItemDivider()
        SettingsSwitchRow({
          icon: $r('sys.symbol.timer'),
          title: '显示自由时间课程',
          isOn: this.store.showFreeClass,
          onToggle: (isOn: boolean) => {
            this.setShowFreeClass(isOn);
          }
        })
        SettingsItemDivider()
        SettingsSwitchRow({
          icon: $r('sys.symbol.calendar_1'),
          title: '显示日期',
          isOn: this.store.showDate,
          onToggle: (isOn: boolean) => {
            this.setShowDate(isOn);
          }
        })
        SettingsItemDivider()
        SettingsRow({
          icon: $r('sys.symbol.arrow_up_and_down_square_portrait'),
          title: '课程高度',
          trailingText: `${this.store.classHeight}`,
          onTap: () => {
            this.openClassHeightPicker();
          }
        })
      }
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
  private moreSection(): void {
    ListItem() {
      SettingsItemGroup({ title: '更多' }) {
        SettingsRow({
          icon: $r('sys.symbol.share'),
          title: '分享当前课表',
          onTap: () => {
            this.pageStack.pushPathByName('share', null);
          }
        })
        SettingsItemDivider()
        SettingsRow({
          icon: $r('sys.symbol.graduationcap'),
          title: '讲座',
          onTap: () => {
            this.pageStack.pushPathByName(ROUTE_LECTURES, null);
          }
        })
        SettingsItemDivider()
        SettingsRow({
          icon: $r('sys.symbol.paintbrush'),
          title: '自定义外观',
          onTap: () => {
            this.pageStack.pushPathByName(ROUTE_MORE_SETTINGS, null);
          }
        })
        SettingsItemDivider()
        SettingsRow({
          icon: $r('sys.symbol.info_circle'),
          title: '关于',
          onTap: () => {
            this.pageStack.pushPathByName(ROUTE_ABOUT, null);
          }
        })
      }
    }
  }

  build() {
    Column() {
      List({ space: Spacing.Md, scroller: this.scroller }) {
        this.tableSection()
        this.displaySection()
        this.moreSection()
      }
      .width('100%')
      .constraintSize({ maxWidth: 800 })
      .layoutWeight(1)
      .padding({
        left: Spacing.Md,
        right: Spacing.Md,
        top: HdsMetrics.TitleBarHeight + HdsMetrics.TitleBarBreathing + px2vp(this.store.windowTopInset),
        bottom: 120
      })
      .clip(false)
      .cachedCount(3, true)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .onDidScroll((scrollOffset: number, scrollState: ScrollState) => {
        TabBarAutoHide.onScroll(this.scroller);
      })
      .onReachStart(() => {
        TabBarAutoHide.resetAndShow();
      })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Colors.Background)
  }

}
