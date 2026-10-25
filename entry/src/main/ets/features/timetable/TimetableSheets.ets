/**
 * 课表周视图的四个半模态内容（TimetableView 的 bindSheet 内容）。
 *
 * 四个半模态统一使用 HdsSheetFrame：HDS 半模态标题栏（HdsNavigation +
 * HdsNavDestination MODAL）+ 统一 Scroll/edge effect；内容只负责卡片与操作。
 * - DetailSheetContent：课程详情（编辑 / 删除操作在标题栏右侧）；
 * - MultiSheetContent：同一时段多门课程列表（点选打开详情）；
 * - FreeCourseSheetContent：自由时间课程列表（左右滑动分页，点卡片打开详情）；
 * - WeekPickerSheetContent：切换课表 + 课程周数。
 */
import { AppStore } from '../../app/AppStore';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsNavigation,
  HdsNavigationAttribute,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitleBarOptions,
  IconStyleMode
} from '@kit.UIDesignKit';
import { ClassPeriod, LegacyConfig } from '../../common/Constants';
import { Colors, FontSize, HdsMetrics, Radius, Spacing } from '../../common/design/Tokens';
import { ColorPool } from '../../data/ColorPool';
import { Course, CourseTable } from '../../data/models/Models';
import { WeeksFormat } from './WeeksFormat';

/**
 * 半模态统一外壳：HDS 标题栏（左关闭 / 标题 / 右菜单）+ 统一滚动与 edge effect。
 * 内容通过尾随闭包传入，避免每个半模态各自复制一套导航/标题栏代码。
 */
@ComponentV2
export struct HdsSheetFrame {
  @Param title: string = '';
  @Param subtitle: string = '';
  /** true：占满 sheet（切换课表 LARGE）；false：按内容高度（FIT_CONTENT）。 */
  @Param fillHeight: boolean = false;
  /** 可选的 HDS 标题栏右侧菜单。 */
  @Param menu: HdsNavigationMenuContentOptions | undefined = undefined;
  @Event onClose: () => void = () => {
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

  private titleBarOptions(): HdsNavigationTitleBarOptions {
    const options: HdsNavigationTitleBarOptions = hdsSubPageTitleBar(this.title, this.subtitle);
    options.enableComponentSafeArea = true;
    options.avoidLayoutSafeArea = false;
    options.content!.backIcon = {
      icon: $r('sys.symbol.xmark'),
      type: IconStyleMode.NORMAL,
      action: () => {
        this.onClose();
      }
    };
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
    }
    .titleBar(this.titleBarOptions())
    .titleMode(HdsNavDestinationTitleMode.MODAL)
    .bindToScrollable([this.scroller])
    .width('100%')
    .height(this.fillHeight ? '100%' : 'auto')
  }

  build() {
    HdsNavigation(this.sheetNav) {
      Column()
    }
    .navDestination(this.destination)
    .hideNavBar(true)
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
    .padding(Spacing.Lg)
    .backgroundColor(Colors.Surface)
    .borderRadius(Radius.Lg)
    .border({ width: 1, color: Colors.OutlineLight })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onOpen(this.course);
    })
  }
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

  @Builder
  private detailTextLine(label: string, value: string) {
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

  private detailTimeText(): string {
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

  @Builder
  private detailBody() {
    Column({ space: Spacing.Lg }) {
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

        this.detailTextLine('时间', this.detailTimeText())
        this.detailTextLine('周次', WeeksFormat.describe(this.course.weeks))
        if (this.course.classroom !== '') {
          this.detailTextLine('教室', this.course.classroom)
        }
        if (this.course.teacher !== '') {
          this.detailTextLine('教师', this.course.teacher)
        }
        if (this.course.testTime !== '' || this.course.testLocation !== '') {
          this.detailTextLine('考试', `${this.course.testTime} ${this.course.testLocation}`.trim())
        }
        if (this.course.info !== '') {
          this.detailTextLine('备注', this.course.info)
        }
        this.detailTextLine('来源', WeeksFormat.importTypeLabel(this.course.importType))
      }
      .width('100%')
      .padding(Spacing.Lg)
      .backgroundColor(Colors.Surface)
      .borderRadius(Radius.Lg)
      .border({ width: 1, color: Colors.OutlineLight })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: Spacing.Xl, right: Spacing.Xl, top: Spacing.Xl, bottom: Spacing.Xxl })
    .alignItems(HorizontalAlign.Start)
  }

  private menuOptions(): HdsNavigationMenuContentOptions {
    return {
      value: [
        {
          content: {
            icon: new SymbolGlyphModifier($r('sys.symbol.trash'))
              .fontSize(HdsMetrics.TitleBarIconSize)
              .fontColor([Colors.Error]),
            type: IconStyleMode.NORMAL,
            action: () => {
              this.onDelete(this.course);
            }
          }
        },
        {
          content: {
            icon: new SymbolGlyphModifier($r('sys.symbol.pencil_line'))
              .fontSize(HdsMetrics.TitleBarIconSize)
              .fontColor([this.store.accentDisplay]),
            type: IconStyleMode.NORMAL,
            action: () => {
              this.onEdit(this.course);
            }
          }
        }
      ]
    };
  }

  build() {
    HdsSheetFrame({
      title: '课程详情',
      menu: this.menuOptions(),
      onClose: () => {
        this.onClose();
      }
    }) {
      this.detailBody()
    }
  }
}

/** 同一时段多门课程的半模态内容（卡片样式与自由时间课程一致）。 */
@ComponentV2
export struct MultiSheetContent {
  @Param group: Course[] = [];
  @Param pool: number[] = [];
  @Event onSelect: (course: Course) => void = () => {
  };
  @Event onClose: () => void = () => {
  };
  @Local multiIndex: number = 0;

  @Builder
  private multiBody() {
    Column({ space: Spacing.Lg }) {
      Swiper() {
        ForEach(this.group, (course: Course) => {
          CourseInfoCard({
            course: course,
            pool: this.pool,
            onOpen: (target: Course) => {
              this.onSelect(target);
            }
          })
        }, (course: Course) => `multi-${course.id}`)
      }
      .width('100%')
      .height(240)
      .indicator(false)
      .loop(false)
      .onChange((index: number) => {
        this.multiIndex = index;
      })

      Text(`${this.multiIndex + 1} / ${this.group.length}`)
        .fontSize(FontSize.Caption)
        .fontColor(Colors.TextTertiary)
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: Spacing.Xl, right: Spacing.Xl, top: Spacing.Xl, bottom: Spacing.Xxl })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsSheetFrame({
      title: '同一时段有多个课程',
      subtitle: `共 ${this.group.length} 门 · 左右滑动查看`,
      onClose: () => {
        this.onClose();
      }
    }) {
      this.multiBody()
    }
  }
}

/** 自由时间课程列表半模态内容（左右滑动分页，点卡片打开详情）。 */
@ComponentV2
export struct FreeCourseSheetContent {
  @Param courses: Course[] = [];
  @Param sheetIndex: number = 0;
  @Param pool: number[] = [];
  @Event onClose: () => void = () => {
  };
  @Event onIndexChange: (index: number) => void = () => {
  };
  @Event onOpenCourse: (course: Course) => void = () => {
  };

  @Builder
  private freeBody() {
    Column({ space: Spacing.Lg }) {
      if (this.courses.length === 0) {
        Text('本周没有自由时间课程')
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
                this.onOpenCourse(target);
              }
            })
          }, (course: Course) => `free-sheet-${course.id}`)
        }
        .width('100%')
        .height(240)
        .indicator(false)
        .loop(false)
        .onChange((index: number) => {
          this.onIndexChange(index);
        })

        Text(`${this.sheetIndex + 1} / ${this.courses.length}`)
          .fontSize(FontSize.Caption)
          .fontColor(Colors.TextTertiary)
          .width('100%')
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .padding({ left: Spacing.Xl, right: Spacing.Xl, top: Spacing.Xl, bottom: Spacing.Xxl })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsSheetFrame({
      title: '自由时间课程',
      subtitle: `共 ${this.courses.length} 门 · 左右滑动查看`,
      onClose: () => {
        this.onClose();
      }
    }) {
      this.freeBody()
    }
  }
}

/** 同一课程多个时段的半模态内容（复刻自由时间课程的左右滑动卡片）。 */
@ComponentV2
export struct CourseSessionsSheetContent {
  @Param courseName: string = '';
  @Param sessions: Course[] = [];
  @Param pool: number[] = [];
  @Event onClose: () => void = () => {
  };
  @Event onOpenSession: (course: Course) => void = () => {
  };
  @Local sessionIndex: number = 0;

  @Builder
  private sessionsBody() {
    Column({ space: Spacing.Lg }) {
      Swiper() {
        ForEach(this.sessions, (course: Course) => {
          CourseInfoCard({
            course: course,
            pool: this.pool,
            onOpen: (target: Course) => {
              this.onOpenSession(target);
            }
          })
        }, (course: Course) => `sessions-sheet-${course.id}`)
      }
      .width('100%')
      .height(240)
      .indicator(false)
      .loop(false)
      .onChange((index: number) => {
        this.sessionIndex = index;
      })

      Text(`${this.sessionIndex + 1} / ${this.sessions.length}`)
        .fontSize(FontSize.Caption)
        .fontColor(Colors.TextTertiary)
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: Spacing.Xl, right: Spacing.Xl, top: Spacing.Xl, bottom: Spacing.Xxl })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsSheetFrame({
      title: '该课程有多个时段',
      subtitle: `共 ${this.sessions.length} 个时段 · 左右滑动查看`,
      onClose: () => {
        this.onClose();
      }
    }) {
      this.sessionsBody()
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
            Text(`${value}`)
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
