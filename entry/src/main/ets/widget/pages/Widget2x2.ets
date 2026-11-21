/**
 * 2x2 桌面小组件。
 *
 * - 列表视图：日期/星期随课程列表滚动；条目只保留课程名和地点；
 *   切换按钮固定在右上角；
 * - focus 视图：顶部状态（上课中 / 下一节 / 今天没有课），中间课程名 + 地点，
 *   底部上方进度条、左下时段、右下日期与星期；
 * - 数据由 FormExtensionAbility 现场计算（widget/WidgetDataProvider.ets）。
 */
import { WidgetDayCourse, WidgetDayPayload, WidgetPalette } from '../WidgetCommon';

const VIEW_TRANSITION: TransitionEffect =
  TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.Smooth });

@Entry
@ComponentV2
struct Widget2x2 {
  @Local data: string = '';

  private payload(): WidgetDayPayload | undefined {
    if (this.data === '') {
      return undefined;
    }
    try {
      return JSON.parse(this.data) as WidgetDayPayload;
    } catch (err) {
      return undefined;
    }
  }

  private todayCourses(): WidgetDayCourse[] {
    const payload: WidgetDayPayload | undefined = this.payload();
    return payload === undefined || payload.courses === undefined ? [] : payload.courses;
  }

  private nextCourses(): WidgetDayCourse[] {
    const payload: WidgetDayPayload | undefined = this.payload();
    return payload === undefined || payload.nextCourses === undefined ? [] : payload.nextCourses;
  }

  private showNext(): boolean {
    const payload: WidgetDayPayload | undefined = this.payload();
    return payload !== undefined && payload.nextFound === true && this.todayCourses().length === 0;
  }

  private isFocusView(): boolean {
    const payload: WidgetDayPayload | undefined = this.payload();
    return payload !== undefined && payload.view === 'focus';
  }

  private focusCourse(): WidgetDayCourse | undefined {
    const payload: WidgetDayPayload | undefined = this.payload();
    return payload === undefined ? undefined : payload.focusCourse;
  }

  private focusStatus(): string {
    const payload: WidgetDayPayload | undefined = this.payload();
    if (payload !== undefined && payload.focusStatus !== undefined && payload.focusStatus !== '') {
      return payload.focusStatus;
    }
    return this.todayEmptyText();
  }

  private focusProgress(): number {
    const payload: WidgetDayPayload | undefined = this.payload();
    if (payload === undefined || payload.focusProgress === undefined) {
      return 0;
    }
    return Math.max(0, Math.min(100, payload.focusProgress));
  }

  private focusTime(course: WidgetDayCourse): string {
    if (course.startTime !== '' && course.endTime !== '') {
      return `${course.startTime}-${course.endTime}`;
    }
    return course.time;
  }

  /** focus 视图右下角：日期 + 星期。 */
  private focusDateText(): string {
    const payload: WidgetDayPayload | undefined = this.payload();
    if (payload === undefined) {
      return '';
    }
    const date: string = payload.focusDate !== undefined && payload.focusDate !== '' ?
      payload.focusDate : payload.date;
    const weekday: string = payload.focusWeekday !== undefined && payload.focusWeekday !== '' ?
      payload.focusWeekday : payload.weekday;
    return `${date} ${weekday}`.trim();
  }

  private todayTitle(): string {
    const payload: WidgetDayPayload | undefined = this.payload();
    if (payload === undefined) {
      return '';
    }
    return `${payload.date} ${payload.weekday}`;
  }

  private nextTitle(): string {
    const payload: WidgetDayPayload | undefined = this.payload();
    if (payload === undefined) {
      return '';
    }
    return `${payload.nextDate} ${payload.nextWeekday}`;
  }

  private todayEmptyText(): string {
    const payload: WidgetDayPayload | undefined = this.payload();
    if (payload !== undefined && payload.todayDone === true) {
      return '今天的课已上完';
    }
    return '今天没有课';
  }

  private palette(): WidgetPalette {
    const payload: WidgetDayPayload | undefined = this.payload();
    // 跟随系统时使用资源限定词，系统深浅色切换由卡片资源自动刷新，无需打开应用。
    let mode: string = '';
    if (payload !== undefined) {
      mode = payload.followSystem === true ? 'auto' : payload.mode;
    }
    return new WidgetPalette(mode);
  }

  private toggleView(): void {
    postCardAction(this, {
      action: 'message',
      params: { message: 'toggle2x2Focus' }
    });
  }

  @Builder
  private switchButton() {
    // 视觉 24×24，但扩大点击热区到 32×32，避免桌面端小按钮难命中。
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.arrow_left_arrow_right'))
          .fontSize(14)
          .fontColor([this.palette().textSecondary()])
      }
      .width(24)
      .height(24)
      .borderRadius(12)
      .backgroundColor(this.palette().surfaceHigh())
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .width(32)
    .height(32)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .accessibilityText('切换视图')
    .onClick(() => {
      this.toggleView();
    })
  }

  @Builder
  private courseRow(course: WidgetDayCourse) {
    Row({ space: 8 }) {
      Row()
        .width(3)
        .height(30)
        .borderRadius(2)
        .backgroundColor(course.color)

      Column({ space: 2 }) {
        Text(course.name)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(this.palette().textPrimary())
          .width('100%')
        Text(course.place)
          .fontSize(10)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(this.palette().textTertiary())
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private listView() {
    Stack({ alignContent: Alignment.TopEnd }) {
      List({ space: 8 }) {
        // 日期/星期作为列表首项，和课程一起滚动（与 2x4 一致）。
        ListItem() {
          Row() {
            Text(this.todayTitle())
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().accent())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .padding({ right: 40 })
          }
          .width('100%')
          .height(32)
          .alignItems(VerticalAlign.Center)
        }

        if (this.todayCourses().length > 0) {
          ForEach(this.todayCourses().slice(0, 4), (course: WidgetDayCourse) => {
            ListItem() {
              this.courseRow(course)
            }
          }, (course: WidgetDayCourse, index: number) =>
            `today-${course.name}-${course.place}-${course.startTime}-${course.endTime}-${course.color}-${index}`)
        } else {
          ListItem() {
            Text(this.todayEmptyText())
              .fontSize(12)
              .fontColor(this.palette().textSecondary())
              .width('100%')
          }
        }

        if (this.showNext()) {
          ListItem() {
            Text(this.nextTitle())
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().textPrimary())
              .maxLines(1)
              .width('100%')
              .padding({ top: 2 })
          }
          ForEach(this.nextCourses().slice(0, 4), (course: WidgetDayCourse) => {
            ListItem() {
              this.courseRow(course)
            }
          }, (course: WidgetDayCourse, index: number) =>
            `next-${course.name}-${course.place}-${course.startTime}-${course.endTime}-${course.color}-${index}`)
        }
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)

      this.switchButton()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private focusView() {
    Column() {
      Row({ space: 6 }) {
        Text(this.focusStatus())
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().accent())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        this.switchButton()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Column({ space: 4 }) {
        if (this.focusCourse() !== undefined) {
          Text(this.focusCourse()!.name)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().textPrimary())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.focusCourse()!.place)
            .fontSize(11)
            .fontColor(this.palette().textTertiary())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        } else {
          Text('暂无课程')
            .fontSize(14)
            .fontColor(this.palette().textSecondary())
        }
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)

      if (this.focusCourse() !== undefined) {
        Column({ space: 4 }) {
          Progress({ value: this.focusProgress(), total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(4)
            .color(this.palette().accent())
            .backgroundColor(this.palette().surfaceHigh())
          Row() {
            Text(this.focusTime(this.focusCourse()!))
              .fontSize(11)
              .fontColor(this.palette().textSecondary())
              .maxLines(1)
            Blank()
            Text(this.focusDateText())
              .fontSize(11)
              .fontColor(this.palette().textTertiary())
              .maxLines(1)
          }
          .width('100%')
        }
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      if (this.isFocusView()) {
        Column() {
          this.focusView()
        }
        .width('100%')
        .height('100%')
        .transition(VIEW_TRANSITION)
      } else {
        Column() {
          this.listView()
        }
        .width('100%')
        .height('100%')
        .transition(VIEW_TRANSITION)
      }
    }
    .width('100%')
    .height('100%')
    .padding(14)
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
