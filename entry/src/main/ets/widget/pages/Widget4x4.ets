/**
 * 4x4 桌面小组件：本周课程表速览（周一~周五）。
 *
 * 视觉与主课表页对齐系统日历课程表：
 * - 顶部显示当前周次与日期；
 * - 左侧时间轴显示节次与起止时间；
 * - 5 个工作日按节次对齐课程块，课程色与主课表一致；
 * - 内容超出卡片高度时可上下滑动，而不再用「+N」截断。
 * 数据由 FormExtensionAbility 现场计算（widget/WidgetDataProvider.ets）。
 */
import { ColorMath } from '../../common/design/ColorMath';
import { WidgetPalette } from '../WidgetCommon';

interface W4x4Course {
  name: string;
  place: string;
  teacher: string;
  day: number;
  start: number;
  count: number;
  period: string;
  color: string;
  done: boolean;
}

interface W4x4Period {
  start: string;
  end: string;
}

interface W4x4Payload {
  date: string;
  weekday: string;
  weekLabel: string;
  tableName: string;
  courses: W4x4Course[];
  week: W4x4Course[];
  weekTotals: number[];
  weekDates: string[];
  periods: W4x4Period[];
  mode: string;
  accent: string;
}

const ROW_HEIGHT: number = 48;
const TIME_WIDTH: number = 42;
const DAYS: number[] = [1, 2, 3, 4, 5];

@Entry
@ComponentV2
struct Widget4x4 {
  @Local data: string = '';

  private payload(): W4x4Payload | undefined {
    if (this.data === '') {
      return undefined;
    }
    try {
      return JSON.parse(this.data) as W4x4Payload;
    } catch (err) {
      return undefined;
    }
  }

  private weekCourses(): W4x4Course[] {
    const payload: W4x4Payload | undefined = this.payload();
    if (payload === undefined || payload.week === undefined) {
      return [];
    }
    return payload.week;
  }

  private periods(): W4x4Period[] {
    const payload: W4x4Payload | undefined = this.payload();
    if (payload === undefined || payload.periods === undefined) {
      return [];
    }
    return payload.periods;
  }

  private weekDates(): string[] {
    const payload: W4x4Payload | undefined = this.payload();
    if (payload === undefined || payload.weekDates === undefined) {
      return [];
    }
    return payload.weekDates;
  }

  private coursesOfDay(day: number): W4x4Course[] {
    const result: W4x4Course[] = [];
    const all: W4x4Course[] = this.weekCourses();
    for (let i = 0; i < all.length; i++) {
      if (all[i].day === day) {
        result.push(all[i]);
      }
    }
    result.sort((a: W4x4Course, b: W4x4Course): number => a.start - b.start);
    return result;
  }

  private weekText(): string {
    const payload: W4x4Payload | undefined = this.payload();
    return payload === undefined || payload.weekLabel === undefined ? '本周' : payload.weekLabel;
  }

  private tableName(): string {
    const payload: W4x4Payload | undefined = this.payload();
    if (payload === undefined || payload.tableName === undefined) {
      return '我的课表';
    }
    return payload.tableName === '' ? '我的课表' : payload.tableName;
  }

  private dayDate(day: number): string {
    const dates: string[] = this.weekDates();
    const index: number = day - 1;
    return index >= 0 && index < dates.length ? dates[index] : '';
  }

  private dayLabel(day: number): string {
    if (day === 1) {
      return '一';
    }
    if (day === 2) {
      return '二';
    }
    if (day === 3) {
      return '三';
    }
    if (day === 4) {
      return '四';
    }
    return '五';
  }

  private gridLine(): string {
    return this.palette().isDark() ? '#2BFFFFFF' : '#12000000';
  }

  private blockHeight(course: W4x4Course): number {
    return Math.max(course.count * ROW_HEIGHT - 2, 16);
  }

  private blockTop(course: W4x4Course): number {
    return (course.start - 1) * ROW_HEIGHT + 1;
  }

  private blockTitleLines(course: W4x4Course): number {
    if (course.count >= 2) {
      return 3;
    }
    return 2;
  }

  /** 与课表页 CourseBlock 一致的课程标题色：浅色下压暗、深色下提亮。 */
  private courseTitleColor(course: W4x4Course): string {
    const target: string = this.palette().isDark() ? '#FFFFFF' : '#1A1A1A';
    const ratio: number = this.palette().isDark() ? 0.62 : 0.55;
    return ColorMath.mix(course.color, target, ratio);
  }

  private courseSecondaryColor(): string {
    return this.palette().isDark() ? '#E0E0E0' : '#4A4A4A';
  }

  // ---- 深浅色 / 主题色（payload 下发 mode/accent；调色板实现见 widget/WidgetCommon.ets）----

  private palette(): WidgetPalette {
    const payload: W4x4Payload | undefined = this.payload();
    return new WidgetPalette(payload === undefined ? '' : payload.mode,
      payload === undefined ? '' : payload.accent);
  }

  @Builder
  private courseBlock(course: W4x4Course) {
    Stack({ alignContent: Alignment.TopStart }) {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(course.color)
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().cardBg())
        .opacity(this.palette().isDark() ? 0.56 : 0.72)

      Column({ space: 1 }) {
        Text(course.name)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.courseTitleColor(course))
          .maxLines(this.blockTitleLines(course))
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (course.place !== '' && course.count >= 2) {
          Text(course.place)
            .fontSize(9)
            .fontColor(this.courseSecondaryColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 3, right: 2, top: 2, bottom: 1 })
    }
    .width('100%')
    .height(this.blockHeight(course))
    .borderRadius(3)
    .clip(true)
    .position({ x: 0, y: this.blockTop(course) })
  }

  @Builder
  private timeAxis() {
    Column() {
      ForEach(this.periods(), (period: W4x4Period, index: number) => {
        Column({ space: 0 }) {
          Text(`${index + 1}`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textSecondary())
          Text(period.start)
            .fontSize(10)
            .fontColor(this.palette().textTertiary())
          Text(period.end)
            .fontSize(10)
            .fontColor(this.palette().textTertiary())
        }
        .width(TIME_WIDTH)
        .height(ROW_HEIGHT)
        .justifyContent(FlexAlign.Center)
        .border({ width: { bottom: 0.5 }, color: this.gridLine(), style: BorderStyle.Dashed })
      }, (period: W4x4Period, index: number) => `period-${index}-${period.start}`)
    }
    .width(TIME_WIDTH)
    .height(this.periods().length * ROW_HEIGHT)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private dayColumn(day: number) {
    Stack() {
      Column() {
        ForEach(this.periods(), (_period: W4x4Period, index: number) => {
          Column()
            .width('100%')
            .height(ROW_HEIGHT)
            .border({ width: { bottom: 0.5 }, color: this.gridLine(), style: BorderStyle.Dashed })
        }, (_period: W4x4Period, index: number) => `cell-${day}-${index}`)
      }
      .width('100%')
      .height(this.periods().length * ROW_HEIGHT)

      ForEach(this.coursesOfDay(day), (course: W4x4Course) => {
        this.courseBlock(course)
      }, (course: W4x4Course, index: number) => `week-${day}-${index}-${course.name}`)
    }
    .layoutWeight(1)
    .height(this.periods().length * ROW_HEIGHT)
    .padding({ left: 1, right: 1 })
    .align(Alignment.TopStart)
  }

  build() {
    Column() {
      Row() {
        Text(this.tableName())
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().accent())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Text(this.weekText())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary())
          .maxLines(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: 8, bottom: 8 })

      Row() {
        Column()
          .width(TIME_WIDTH)
        ForEach(DAYS, (day: number) => {
          Column({ space: 1 }) {
            Text(this.dayLabel(day))
              .fontSize(13)
              .fontColor(this.palette().textSecondary())
            Text(this.dayDate(day))
              .fontSize(10)
              .fontColor(this.palette().textTertiary())
          }
          .layoutWeight(1)
          .height(36)
          .padding({ left: 1, right: 1 })
          .alignItems(HorizontalAlign.Center)
        }, (day: number) => `header-${day}`)
      }
      .width('100%')
      .padding({ top: 4, bottom: 2 })

      List() {
        ListItem() {
          Row() {
            this.timeAxis()
            ForEach(DAYS, (day: number) => {
              this.dayColumn(day)
            }, (day: number) => `day-${day}`)
          }
          .width('100%')
          .height(this.periods().length * ROW_HEIGHT)
          .alignItems(VerticalAlign.Top)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 10, right: 10, top: 10, bottom: 8 })
    .backgroundColor(this.palette().cardBg())
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { target: 'timetable' }
      });
    })
  }
}
