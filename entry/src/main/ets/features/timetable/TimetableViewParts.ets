/**
 * 课表周视图（features/timetable）拆出的展示零件与周页面数据源。
 *
 * 从 TimetableView.ets 拆分而来，只做搬家，行为/布局/样式/文案不变：
 * - WeekHeaderRow：星期/日期行，独立 @ComponentV2，主题色（今天高亮）变化时只重绘这一行；
 * - FreeCourseEntryButton：右下角自由时间课程入口，主题色变化只重绘该按钮；
 * - WeekPageDataSource + makeWeekPageDataSource：Swiper + LazyForEach 的 25 周页面数据源。
 *
 * 这些组件带课表周视图语义（星期行/自由时间入口/周页面数据源），只服务 features/timetable，
 * 因此不放进 common/ui（那是跨功能通用组件）。
 */
import { AppStore } from '../../app/AppStore';
import { LegacyConfig } from '../../common/Constants';
import { Colors, FontSize, Radius, Spacing, TimetableMetrics } from '../../common/design/Tokens';

/** 星期/日期行：单独成组件，主题色（今天高亮）变化时只重绘这一行，不重绘 25 页课表。 */
@ComponentV2
export struct WeekHeaderRow {
  @Local store: AppStore = AppStore.connect();
  @Param week: number = 1;
  @Param labels: string[] = [];
  @Param dates: string[] = [];
  @Param todayColumn: number = -1;
  @Param dayWidth: number = 0;
  @Param showDate: boolean = true;

  build() {
    Row() {
      Column() {
        Text('')
      }
      .width(TimetableMetrics.TimeColumnWidth)
      .height(TimetableMetrics.HeaderHeight)

      ForEach(this.labels, (label: string, index: number) => {
        Column({ space: 2 }) {
          Text(label)
            .fontSize(FontSize.Caption)
            .fontColor(index === this.todayColumn ? this.store.accentDisplay : Colors.TextSecondary)
            .fontWeight(index === this.todayColumn ? FontWeight.Bold : FontWeight.Normal)
          if (this.showDate && index < this.dates.length) {
            Text(this.dates[index])
              .fontSize(FontSize.Caption)
              .fontColor(index === this.todayColumn ? this.store.accentDisplay : Colors.TextTertiary)
          }
        }
        .width(this.dayWidth)
        .height(TimetableMetrics.HeaderHeight)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Color.Transparent)
      }, (label: string, index: number) => `hdr-${this.week}-${label}-${index}`)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

/** 右下角自由时间课程入口：主题色变化只重绘该按钮。 */
@ComponentV2
export struct FreeCourseEntryButton {
  @Local store: AppStore = AppStore.connect();
  @Param count: number = 0;
  @Event onTap: () => void = () => {
  };

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(24)
          .fontColor([this.store.accentOn])
      }
      .width(52)
      .height(52)
      .backgroundColor(this.store.accentDisplay)
      .shadow({ radius: 8, color: '#33000000', offsetY: 2 })
      .onClick(() => {
        this.onTap();
      })

      Text(`${this.count}`)
        .fontSize(FontSize.Caption)
        .fontColor(Colors.TextPrimary)
        .textAlign(TextAlign.Center)
        .width(20)
        .height(20)
        .borderRadius(Radius.Round)
        .backgroundColor(Colors.Surface)
        .border({ width: 1, color: Colors.OutlineLight })
        .position({ x: 44, y: 0 })
    }
    .width(64)
    .height(64)
  }
}

/** 划离本周时出现的「回到本周」按钮：浮动底板 + 强调色 Home 图标（深浅色自适应）。 */
@ComponentV2
export struct BackToCurrentWeekButton {
  @Local store: AppStore = AppStore.connect();
  @Event onTap: () => void = () => {
  };

  build() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.house'))
        .fontSize(24)
        .fontColor([this.store.accentDisplay])
    }
    .width(52)
    .height(52)
    .backgroundColor(Colors.Floating)
    .shadow({ radius: 8, color: '#33000000', offsetY: 2 })
    .accessibilityText('回到本周')
    .onClick(() => {
      this.onTap();
    })
  }
}

/** 周页面数据源：Swiper + LazyForEach 只构建可视/缓存页，避免 25 个课表页全量构建。 */
export class WeekPageDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private weeks: number[] = [];

  constructor(weeks: number[]) {
    this.weeks = weeks;
  }

  totalCount(): number {
    return this.weeks.length;
  }

  getData(index: number): number {
    return this.weeks[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos: number = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }
}

/** 构造 1..MAX_WEEKS 的周页面数据源（供 TimetableView 的 Swiper 使用）。 */
export function makeWeekPageDataSource(): WeekPageDataSource {
  const weeks: number[] = [];
  for (let i = 1; i <= LegacyConfig.MAX_WEEKS; i++) {
    weeks.push(i);
  }
  return new WeekPageDataSource(weeks);
}
