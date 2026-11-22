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
import { AppStore } from '../../app/AppStore';
import { ClassPeriod } from '../../common/Constants';
import { Colors, FontSize, TimetableMetrics } from '../../common/design/Tokens';
import { Course } from '../../data/models/Models';
import { CourseBlock } from './CourseBlock';

/** Canvas 只接受 string/number 颜色；getColorSync 不支持 dark 目录，故与 resources 保持同值。 */
const GRID_LINE_LIGHT: string = '#E4E4E9';
const GRID_LINE_DARK: string = '#2A2A30';

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
  @Local store: AppStore = AppStore.connect();

  private gridContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));

  @Monitor('store.isDark', 'classHeight', 'periods')
  private onGridStyleChanged(): void {
    this.drawGridLines();
  }

  /** 13 条横向 dashed line，替代每天 13 个带边框 Row；仅在初始化/尺寸/主题变化时绘制。 */
  private drawGridLines(): void {
    const ctx: CanvasRenderingContext2D = this.gridContext;
    const width: number = ctx.width;
    const height: number = ctx.height;
    if (width <= 0 || height <= 0 || this.periods.length === 0) {
      return;
    }
    ctx.clearRect(0, 0, width, height);
    ctx.strokeStyle = this.store.isDark ? GRID_LINE_DARK : GRID_LINE_LIGHT;
    ctx.lineWidth = 1;
    ctx.setLineDash([4, 4]);
    for (let i = 1; i <= this.periods.length; i++) {
      const y: number = Math.min(i * this.classHeight, height - 0.5);
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(width, y);
      ctx.stroke();
    }
    ctx.setLineDash([]);
  }

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
      }, (period: ClassPeriod, index: number) => `t-${this.week}-${this.classHeight}-${index}`)
    }
    .width(TimetableMetrics.TimeColumnWidth)
  }

  /** 日期列的 ForEach key：颜色/位置/高度/冲突变化时必须重建，否则配色池切换不会热更新。 */
  private dayKey(blocks: LayoutBlock[], dayIndex: number): string {
    let key: string = `col-${this.week}-${dayIndex}-${this.classHeight}`;
    for (let i = 0; i < blocks.length; i++) {
      const block: LayoutBlock = blocks[i];
      key += `|${block.key},${block.color},${block.y},${block.h},${block.faded},${block.conflictCount}`;
    }
    return key;
  }

  @Builder
  private grid() {
    Stack({ alignContent: Alignment.TopStart }) {
      Canvas(this.gridContext)
        .width('100%')
        .height(this.gridHeight)
        .onReady(() => {
          // 不要用 onAreaChange：Swiper 拖动时位置变化会触发逐帧重绘。
          this.drawGridLines();
        })
        .onSizeChange((_oldValue: SizeOptions, _newValue: SizeOptions) => {
          this.drawGridLines();
        })
        .hitTestBehavior(HitTestMode.None)
      Row() {
        this.timeColumn()
        ForEach(this.blocksByDay, (blocks: LayoutBlock[], dayIndex: number) => {
          Stack({ alignContent: Alignment.TopStart }) {
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
        }, (blocks: LayoutBlock[], dayIndex: number) => this.dayKey(blocks, dayIndex))
      }
      .width('100%')
      .height(this.gridHeight)
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .height(this.gridHeight)
  }

  build() {
    Column() {
      this.grid()
    }
    .width('100%')
    .height(this.gridHeight)
  }
}
