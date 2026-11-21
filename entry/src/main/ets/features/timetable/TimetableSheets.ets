/**
 * 课表周视图的半模态内容（TimetableView 的 bindSheet 内容）。
 *
 * 所有半模态统一使用 HdsSheetFrame：HDS 半模态标题栏（HdsNavigation +
 * HdsNavDestination MODAL）+ 统一 Scroll/edge effect；内容只负责卡片与操作。
 * - DetailSheetContent：课程详情（编辑 / 删除操作在标题栏右侧）；
 * - CourseListSheetContent：同一时段多门课程 / 自由时间课程列表（列表与详情同面板切换）；
 * - WeekPickerSheetContent：切换课表 + 课程周数。
 */
import { AppStore } from '../../app/AppStore';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsNavigation,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitleBarOptions,
  IconStyleMode
} from '@kit.UIDesignKit';
import { ClassPeriod, LegacyConfig } from '../../common/Constants';
import { Colors, FontSize, HdsMetrics, Radius, Spacing } from '../../common/design/Tokens';
import { IS_2IN1 } from '../../common/DeviceType';
import { ColorPool } from '../../data/ColorPool';
import { Course, CourseTable } from '../../data/models/Models';
import { WeeksFormat } from './WeeksFormat';
import { SettingsItemGroup } from '../../common/ui/SettingsListItems';

/**
 * 半模态统一外壳：HDS 标题栏（左关闭 / 标题 / 右菜单）+ 统一滚动与 edge effect。
 * 内容通过尾随闭包传入，避免每个半模态各自复制一套导航/标题栏代码。
 */
@ComponentV2
export struct HdsSheetFrame {
  @Local store: AppStore = AppStore.connect();
  @Param title: string = '';
  @Param subtitle: string = '';
  /** true：占满 sheet（切换课表 LARGE）；false：按内容高度（FIT_CONTENT）。 */
  @Param fillHeight: boolean = false;
  /** 可选的 HDS 标题栏右侧菜单。 */
  @Param menu: HdsNavigationMenuContentOptions | undefined = undefined;
  /** true：标题栏左侧显示返回箭头，用于同一半模态内页面切换。 */
  @Param showBack: boolean = false;
  @Event onClose: () => void = () => {
  };
  @Event onBack: () => void = () => {
  };
  @BuilderParam content: () => void = this.emptyContent;

  private sheetNav: NavPathStack = new NavPathStack();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.sheetNav.pushPath({ name: 'sheet-content' });
  }

  @Builder
  private emptyContent() {
    Column()
  }

  /** FIT_CONTENT 下的最大滚动视口：内容短时自适应，超出时内部滚动。 */
  private contentMaxHeight(): number {
    const windowHeight: number = px2vp(this.store.windowHeight);
    return Math.max(240, windowHeight * 0.78);
  }

  private titleBarOptions(): HdsNavigationTitleBarOptions {
    const options: HdsNavigationTitleBarOptions = hdsSubPageTitleBar(this.title, this.subtitle);
    options.enableComponentSafeArea = true;
    options.avoidLayoutSafeArea = false;
    if (this.showBack) {
      // 不覆盖 icon，沿用 HdsNavDestination 与其他子页面一致的默认返回按钮。
      options.content!.backIcon = {
        action: () => {
          this.onBack();
        }
      };
    } else {
      options.content!.backIcon = {
        icon: $r('sys.symbol.xmark'),
        type: IconStyleMode.NORMAL,
        action: () => {
          this.onClose();
        }
      };
    }
    if (this.menu !== undefined) {
      options.content!.menu = this.menu;
    }
    return options;
  }

  @Builder
  private destination(name: string, param: Object) {
    HdsNavDestination() {
      Scroll(this.scroller) {
        this.content()
      }
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .clip(false)
      .height(this.fillHeight ? '100%' : 'auto')
      .constraintSize({ maxHeight: this.fillHeight ? '100%' : this.contentMaxHeight() })
    }
    .titleBar(this.titleBarOptions())
    .titleMode(HdsNavDestinationTitleMode.MODAL)
    .bindToScrollable([this.scroller])
    .backgroundColor(Colors.Background)
    .width('100%')
    .height(this.fillHeight ? '100%' : 'auto')
  }

  build() {
    HdsNavigation(this.sheetNav) {
      Column()
    }
    .navDestination(this.destination)
    .hideNavBar(true)
    .backgroundColor(Colors.Background)
    .width('100%')
    .height(this.fillHeight ? '100%' : 'auto')
  }
}

/** 半模态里的课程卡片：同一时段多课程 / 自由时间课程共用，保证样式完全一致。 */
@ComponentV2
export struct CourseInfoCard {
  @Param course: Course = new Course();
  @Param pool: number[] = [];
  @Event onOpen: (course: Course) => void = () => {
  };

  @Builder
  private line(label: string, value: string) {
    Row({ space: 2 }) {
      Text(`${label}：`)
        .fontSize(FontSize.Body)
        .fontColor(Colors.TextTertiary)
      Text(value === '' ? '—' : value)
        .fontSize(FontSize.Body)
        .fontColor(Colors.TextSecondary)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  build() {
    SettingsItemGroup() {
      Column({ space: Spacing.Sm }) {
        Row({ space: Spacing.Sm }) {
          Row()
            .width(10)
            .height(10)
            .borderRadius(Radius.Round)
            .backgroundColor(ColorPool.resolve(this.course, this.pool))
        Text(this.course.name)
          .fontSize(FontSize.Title)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.TextPrimary)
          .maxLines(2)
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      this.line('时间', `${WeeksFormat.weekdayLabel(this.course.weekTime)} ${WeeksFormat.periodLabel(this.course)}`)
      this.line('周次', WeeksFormat.describe(this.course.weeks))
      if (this.course.classroom !== '') {
        this.line('地点', this.course.classroom)
      }
      if (this.course.teacher !== '') {
        this.line('教师', this.course.teacher)
      }

        Text('点击卡片查看课程详情或编辑/删除')
          .fontSize(FontSize.Caption)
          .fontColor(Colors.TextTertiary)
          .margin({ top: Spacing.Sm })
      }
      .width('100%')
      .padding(Spacing.Md)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        this.onOpen(this.course);
      })
    }
  }
}

/** 课程详情正文：详情半模态与两个列表半模态的内页共用。 */
@ComponentV2
export struct CourseDetailBody {
  @Param course: Course = new Course();
  @Param periods: ClassPeriod[] = [];
  @Param pool: number[] = [];

  @Builder
  private line(label: string, value: string) {
    Row({ space: 2 }) {
      Text(`${label}：`)
        .fontSize(FontSize.Body)
        .fontColor(Colors.TextTertiary)
      Text(value === '' ? '—' : value)
        .fontSize(FontSize.Body)
        .fontColor(Colors.TextSecondary)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  private timeText(): string {
    const course: Course = this.course;
    const weekday: string = WeeksFormat.weekdayLabel(course.weekTime);
    const periods: string = WeeksFormat.periodLabel(course);
    const startIndex: number = course.startTime - 1;
    const endIndex: number = Math.min(course.startTime + course.timeCount - 1, this.periods.length - 1);
    if (startIndex >= 0 && endIndex >= startIndex) {
      const start: string = this.periods[startIndex].start;
      const end: string = this.periods[endIndex].end;
      if (start !== '' && end !== '') {
        return `${weekday} ${periods}(${start}-${end})`;
      }
    }
    return `${weekday} ${periods}`;
  }

  build() {
    Column({ space: Spacing.Lg }) {
      SettingsItemGroup() {
        Column({ space: Spacing.Sm }) {
          Row({ space: Spacing.Md }) {
            Row() {
              SymbolGlyph($r('sys.symbol.book'))
                .fontSize(18)
                .fontColor([ColorPool.resolve(this.course, this.pool)])
            }
            .width(36)
            .height(36)
            .borderRadius(Radius.Md)
            .backgroundColor(Colors.SurfaceHigh)
            .justifyContent(FlexAlign.Center)

            Text(this.course.name)
              .fontSize(FontSize.Title)
              .fontWeight(FontWeight.Bold)
              .fontColor(Colors.TextPrimary)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          this.line('时间', this.timeText())
          this.line('周次', WeeksFormat.describe(this.course.weeks))
          if (this.course.classroom !== '') {
            this.line('教室', this.course.classroom)
          }
          if (this.course.teacher !== '') {
            this.line('教师', this.course.teacher)
          }
          if (this.course.testTime !== '' || this.course.testLocation !== '') {
            this.line('考试', `${this.course.testTime} ${this.course.testLocation}`.trim())
          }
          if (this.course.info !== '') {
            this.line('备注', this.course.info)
          }
          this.line('来源', WeeksFormat.importTypeLabel(this.course.importType))
        }
        .width('100%')
        .padding(Spacing.Md)
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .padding({ left: Spacing.Xl, right: Spacing.Xl, top: Spacing.Xl, bottom: Spacing.Xxl })
    .alignItems(HorizontalAlign.Start)
  }
}

/** 详情标题栏菜单：删除 / 编辑。 */
function courseDetailMenu(store: AppStore, course: Course,
  onDelete: (course: Course) => void, onEdit: (course: Course) => void): HdsNavigationMenuContentOptions {
  return {
    value: [
      {
        content: {
          icon: new SymbolGlyphModifier($r('sys.symbol.trash'))
            .fontSize(HdsMetrics.TitleBarIconSize)
            .fontColor([Colors.Error]),
          type: IconStyleMode.NORMAL,
          action: () => {
            onDelete(course);
          }
        }
      },
      {
        content: {
          icon: new SymbolGlyphModifier($r('sys.symbol.pencil_line'))
            .fontSize(HdsMetrics.TitleBarIconSize)
            .fontColor([store.accentDisplay]),
          type: IconStyleMode.NORMAL,
          action: () => {
            onEdit(course);
          }
        }
      }
    ]
  };
}

/** 课程详情半模态内容。 */
@ComponentV2
export struct DetailSheetContent {
  @Local store: AppStore = AppStore.connect();
  @Param course: Course = new Course();
  @Param periods: ClassPeriod[] = [];
  @Param pool: number[] = [];
  @Event onClose: () => void = () => {
  };
  @Event onEdit: (course: Course) => void = () => {
  };
  @Event onDelete: (course: Course) => void = () => {
  };

  build() {
    HdsSheetFrame({
      title: '课程详情',
      menu: courseDetailMenu(this.store, this.course, this.onDelete, this.onEdit),
      onClose: () => {
        this.onClose();
      }
    }) {
      CourseDetailBody({
        course: this.course,
        periods: this.periods,
        pool: this.pool
      })
    }
  }
}

/**
 * 课程列表 + 课程详情同面板半模态。
 * 同一时段多门课程、自由时间课程共用；列表与详情在同一个 HdsSheetFrame 内切换。
 */
@ComponentV2
export struct CourseListSheetContent {
  @Local store: AppStore = AppStore.connect();
  /** 列表页标题。 */
  @Param title: string = '';
  /** 空列表提示；空字符串表示不展示空态。 */
  @Param emptyText: string = '';
  @Param courses: Course[] = [];
  @Param periods: ClassPeriod[] = [];
  @Param pool: number[] = [];
  @Local showDetail: boolean = false;
  @Local detailCourse: Course = new Course();
  @Event onEdit: (course: Course) => void = () => {
  };
  @Event onDelete: (course: Course) => void = () => {
  };
  @Event onClose: () => void = () => {
  };

  private openDetail(course: Course): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.Smooth }, () => {
      this.detailCourse = course;
      this.showDetail = true;
    });
  }

  private closeDetail(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.Smooth }, () => {
      this.showDetail = false;
    });
  }

  @Builder
  private listBody() {
    Column({ space: Spacing.Lg }) {
      if (this.courses.length === 0 && this.emptyText !== '') {
        Text(this.emptyText)
          .fontSize(FontSize.Body)
          .fontColor(Colors.TextTertiary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: Spacing.Xxl, bottom: Spacing.Xxl })
      } else {
        Swiper() {
          ForEach(this.courses, (course: Course) => {
            CourseInfoCard({
              course: course,
              pool: this.pool,
              onOpen: (target: Course) => {
                this.openDetail(target);
              }
            })
          }, (course: Course) => `course-sheet-${course.id}`)
        }
        .width('100%')
        .height(240)
        .loop(false)
        .displayArrow(IS_2IN1)
        .indicator(new DotIndicator()
          .itemWidth(6)
          .itemHeight(6)
          .selectedItemWidth(6)
          .selectedItemHeight(6)
          .color(Colors.Outline)
          .selectedColor(this.store.accentDisplay))
      }
    }
    .width('100%')
    .padding({ left: Spacing.Xl, right: Spacing.Xl, top: Spacing.Xl, bottom: Spacing.Xxl })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsSheetFrame({
      title: this.showDetail ? '课程详情' : this.title,
      subtitle: this.showDetail ? this.detailCourse.name : `共 ${this.courses.length} 门 · 左右滑动查看`,
      menu: this.showDetail ?
        courseDetailMenu(this.store, this.detailCourse, this.onDelete, this.onEdit) : undefined,
      showBack: this.showDetail,
      onBack: () => {
        this.closeDetail();
      },
      onClose: () => {
        this.onClose();
      }
    }) {
      if (this.showDetail) {
        Column() {
          CourseDetailBody({
            course: this.detailCourse,
            periods: this.periods,
            pool: this.pool
          })
        }
        .width('100%')
        .transition(TransitionEffect.OPACITY)
      } else {
        Column() {
          this.listBody()
        }
        .width('100%')
        .transition(TransitionEffect.OPACITY)
      }
    }
  }
}

/** 底部半模态：切换课表 + 课程周数（HDS 半模态标题栏）。 */
@ComponentV2
export struct WeekPickerSheetContent {
  @Local store: AppStore = AppStore.connect();
  @Param tables: CourseTable[] = [];
  @Param selectedTableId: number = 0;
  @Param selectedWeek: number = 1;
  /** 当前选中课表自己的「本周」周次。 */
  @Param currentWeek: number = 1;
  @Event onClose: () => void = () => {
  };
  @Event onSelectTable: (tableId: number) => void = () => {
  };
  @Event onSelectWeek: (week: number) => void = () => {
  };
  @Event onOpenTables: () => void = () => {
  };
  @Event onConfirm: () => void = () => {
  };

  private weekOptions(): number[] {
    const options: number[] = [];
    for (let i = 1; i <= LegacyConfig.MAX_WEEKS; i++) {
      options.push(i);
    }
    return options;
  }

  private menuOptions(): HdsNavigationMenuContentOptions {
    return {
      value: [
        {
          content: {
            icon: $r('sys.symbol.plus'),
            type: IconStyleMode.NORMAL,
            action: () => {
              this.onOpenTables();
            }
          }
        },
        {
          content: {
            icon: $r('sys.symbol.checkmark'),
            type: IconStyleMode.NORMAL,
            action: () => {
              this.onConfirm();
            }
          }
        }
      ]
    };
  }

  @Builder
  private pickerBody() {
    Column({ space: Spacing.Lg }) {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.tables, (table: CourseTable) => {
          Text(table.name)
            .fontSize(FontSize.BodySm)
            .fontColor(table.id === this.selectedTableId ?
              this.store.accentOn : Colors.TextSecondary)
            .padding({ left: Spacing.Lg, right: Spacing.Lg, top: Spacing.Sm, bottom: Spacing.Sm })
            .backgroundColor(table.id === this.selectedTableId ?
              this.store.accentDisplay : Colors.SurfaceHigh)
            .borderRadius(Radius.Round)
            .margin({ right: Spacing.Sm, bottom: Spacing.Sm })
            .onClick(() => {
              this.onSelectTable(table.id);
            })
        }, (table: CourseTable) => `sheet-table-${table.id}`)
      }
      .width('100%')

      Text('课程周数')
        .fontSize(FontSize.Title)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.TextPrimary)
        .width('100%')

      Grid() {
        ForEach(this.weekOptions(), (value: number) => {
          GridItem() {
            Text(value === this.currentWeek ? '本周' : `${value}`)
              .fontSize(FontSize.Body)
              .fontColor(value === this.selectedWeek ?
                this.store.accentOn : Colors.TextPrimary)
              .width('100%')
              .height(44)
              .textAlign(TextAlign.Center)
              .backgroundColor(value === this.selectedWeek ?
                this.store.accentDisplay : Colors.SurfaceHigh)
              .borderRadius(Radius.Md)
              .onClick(() => {
                this.onSelectWeek(value);
              })
          }
        }, (value: number) => `sheet-week-${value}`)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
      .columnsGap(Spacing.Md)
      .rowsGap(Spacing.Md)
      .width('100%')
      .height(5 * 44 + 4 * Spacing.Md)
    }
    .width('100%')
    .padding({ left: Spacing.Xl, right: Spacing.Xl, top: Spacing.Md, bottom: Spacing.Xxl })
  }

  build() {
    HdsSheetFrame({
      title: '切换课表',
      fillHeight: true,
      menu: this.menuOptions(),
      onClose: () => {
        this.onClose();
      }
    }) {
      this.pickerBody()
    }
  }
}
