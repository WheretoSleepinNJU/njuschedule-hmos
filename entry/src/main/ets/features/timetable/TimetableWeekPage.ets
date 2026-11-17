/**
 * 单周课表网格页面（Swiper 的一个周页面）。
 *
 * 从 TimetableView 拆出并标记 @ReusableV2：Swiper 滑出缓存范围后组件进入复用池，
 * 再次滑入时复用节点而不是重新创建整页（官方 Swiper 丢帧优化推荐做法）。
 *
 * 时间列、节次虚线和课程块都放在本页面内，随当前周页面一起滚动/左右滑动；
 * 垂直滚动容器在 Swiper 外层，复用时不涉及 Scroll/Scroller 的重新绑定。
 * 页面只消费父层缓存的布局块。
 */
import { ClassPeriod } from '../../common/Constants';
import { Colors, FontSize, TimetableMetrics } from '../../common/design/Tokens';
import { Course } from '../../data/models/Models';
import { CourseBlock } from './CourseBlock';

/** 一个待渲染的课程块（几何信息在父层按当前宽度/课高算好）。 */
export class LayoutBlock {
  key: string = '';
  course: Course = new Course();
  color: string = '#8AD297';
  faded: boolean = false;
  conflictCount: number = 0;
  group: Course[] = [];
  y: number = 0;
  h: number = 0;
}

@ReusableV2
@ComponentV2
export struct TimetableWeekPage {
  @Param week: number = 1;
  @Param periods: ClassPeriod[] = [];
  @Param classHeight: number = 50;
  @Param showClassTime: boolean = true;
  /** 按天分组的课程块，父层按周缓存。 */
  @Param blocksByDay: LayoutBlock[][] = [];
  @Param gridHeight: number = 0;

  @Event onOpenCourse: (course: Course) => void = (_course: Course) => {
  };
  @Event onOpenMulti: (group: Course[]) => void = (_group: Course[]) => {
  };
  @Event onDeleteCourse: (course: Course) => void = (_course: Course) => {
  };

  @Builder
  private timeColumn() {
    Column() {
      ForEach(this.periods, (period: ClassPeriod, index: number) => {
        Column({ space: 1 }) {
          Text(`${index + 1}`)
            .fontSize(FontSize.BodySm)
            .fontColor(Colors.TextSecondary)
          if (this.showClassTime) {
            Text(period.start)
              .fontSize(10)
              .fontColor(Colors.TextTertiary)
            Text(period.end)
              .fontSize(10)
              .fontColor(Colors.TextTertiary)
          }
        }
        .width(TimetableMetrics.TimeColumnWidth)
        .height(this.classHeight)
        .justifyContent(FlexAlign.Center)
        .border({ width: { bottom: 1 }, color: Colors.GridLine, style: BorderStyle.Dashed })
      }, (period: ClassPeriod, index: number) => `t-${this.week}-${this.classHeight}-${index}`)
    }
    .width(TimetableMetrics.TimeColumnWidth)
  }

  @Builder
  private dayGridLines() {
    Column() {
      ForEach(this.periods, (period: ClassPeriod, periodIndex: number) => {
        Row()
          .width('100%')
          .height(this.classHeight)
          .border({ width: { bottom: 1 }, color: Colors.GridLine, style: BorderStyle.Dashed })
      }, (period: ClassPeriod, periodIndex: number) => `gl-${this.week}-${this.classHeight}-${periodIndex}`)
    }
    .width('100%')
    .height(this.gridHeight)
  }

  @Builder
  private grid() {
    Row() {
      this.timeColumn()
      ForEach(this.blocksByDay, (blocks: LayoutBlock[], dayIndex: number) => {
        Stack({ alignContent: Alignment.TopStart }) {
          this.dayGridLines()
          ForEach(blocks, (block: LayoutBlock) => {
            Column() {
              CourseBlock({
                course: block.course,
                color: block.color,
                heightPx: block.h,
                faded: block.faded,
                conflictCount: block.conflictCount,
                showPlace: true,
                showTeacher: this.classHeight >= 60,
                onTap: () => {
                  if (block.conflictCount > 1) {
                    this.onOpenMulti(block.group);
                  } else {
                    this.onOpenCourse(block.course);
                  }
                },
                onLongPress: () => {
                  this.onDeleteCourse(block.course);
                }
              })
            }
            .width('100%')
            .padding({ left: TimetableMetrics.CourseBlockGap, right: TimetableMetrics.CourseBlockGap })
            .position({ x: 0, y: block.y })
          }, (block: LayoutBlock) => `w${this.week}-${dayIndex}-${this.classHeight}-${block.key}-${block.color}`)
        }
        .layoutWeight(1)
        .height(this.gridHeight)
      }, (blocks: LayoutBlock[], dayIndex: number) =>
        `col-${this.week}-${blocks.length}-${this.classHeight}-${dayIndex}`)
    }
    .width('100%')
    .height(this.gridHeight)
    .alignItems(VerticalAlign.Top)
  }

  build() {
    Column() {
      this.grid()
    }
    .width('100%')
    .height(this.gridHeight)
  }
}
