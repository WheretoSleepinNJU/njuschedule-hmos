/**
 * 2x4 桌面小组件（对齐系统日历课程表卡片）。
 *
 * - 「今天」区块标题使用真实日期 + 星期（如「10月23日 星期五」），今天用主题色高亮；
 * - 今天还有未结束的课 → 只显示今天的课程，不显示后续日期；
 * - 今天的课已上完（或今天没课）→ 今天区块显示空状态，并向下追加「下一个有课日期」区块
 *   （同样是真实日期 + 星期标题，正常色），两段并存、可在 List 内上下滑动。
 * 数据由 FormExtensionAbility 现场计算（widget/WidgetDataProvider.ets）。
 */
import { WidgetDayCourse, WidgetDayPayload, WidgetPalette } from '../WidgetCommon';
@Entry
@ComponentV2
struct Widget2x4 {
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

  private dateText(date: string): string {
    const slash: number = date.indexOf('/');
    if (slash > 0) {
      return `${date.substring(0, slash)}月${date.substring(slash + 1)}日`;
    }
    return date;
  }

  private weekdayText(weekday: string): string {
    if (weekday.length === 2 && weekday.startsWith('周')) {
      return `星期${weekday.substring(1)}`;
    }
    return weekday;
  }

  private todayTitle(): string {
    const payload: WidgetDayPayload | undefined = this.payload();
    if (payload === undefined) {
      return '';
    }
    return `${this.dateText(payload.date)} ${this.weekdayText(payload.weekday)}`;
  }

  private nextTitle(): string {
    const payload: WidgetDayPayload | undefined = this.payload();
    if (payload === undefined) {
      return '';
    }
    return `${this.dateText(payload.nextDate)} ${this.weekdayText(payload.nextWeekday)}`;
  }

  private todayCount(): string {
    const payload: WidgetDayPayload | undefined = this.payload();
    return payload === undefined || payload.todayTotal === undefined ? '0' : `${payload.todayTotal}`;
  }

  private nextCount(): string {
    return `${this.nextCourses().length}`;
  }

  private todayWeek(): string {
    const payload: WidgetDayPayload | undefined = this.payload();
    return payload === undefined ? '' : payload.weekLabel;
  }

  private nextWeek(): string {
    const payload: WidgetDayPayload | undefined = this.payload();
    return payload === undefined ? '' : payload.nextWeekLabel;
  }

  private todayEmptyText(): string {
    const payload: WidgetDayPayload | undefined = this.payload();
    if (payload !== undefined && payload.todayDone === true) {
      return '今天的课已上完';
    }
    return '今天没有课';
  }

  private subtitle(course: WidgetDayCourse): string {
    const parts: string[] = [];
    if (course.place !== '') {
      parts.push(course.place);
    }
    if (course.teacher !== '' && course.state !== 'now' && course.state !== 'next') {
      parts.push(course.teacher);
    }
    return parts.join(' · ');
  }

  private stateText(state: string): string {
    if (state === 'now') {
      return '进行中';
    }
    if (state === 'next') {
      return '下一节';
    }
    return '';
  }

  /** 课程起始时间：进行中主题色，其余跟随卡片深浅色（不能直接用资源色，否则强制深色时会变黑）。 */
  private startTimeColor(state: string): ResourceColor {
    return state === 'now' ? this.palette().accent() : this.palette().textPrimary();
  }

  @Builder
  courseRow(course: WidgetDayCourse) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(course.startTime)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.startTimeColor(course.state))
        Text(course.endTime)
          .fontSize(10)
          .fontColor(this.palette().textTertiary())
      }
      .width(46)
      .alignItems(HorizontalAlign.Start)

      Row()
        .width(3)
        .height(32)
        .borderRadius(2)
        .backgroundColor(course.color)

      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(course.name)
            .fontSize(14)
            .fontWeight(course.state === 'now' ? FontWeight.Medium : FontWeight.Normal)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.palette().textPrimary())
            .layoutWeight(1)
          if (this.stateText(course.state) !== '') {
            Text(this.stateText(course.state))
              .fontSize(10)
              .fontColor(this.palette().accent())
              .backgroundColor(this.palette().accentSoft())
              .borderRadius(4)
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
          }
        }
        .width('100%')

        Text(this.subtitle(course))
          .fontSize(11)
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

  // ---- 深浅色 / 主题色（payload 下发 mode/accent；调色板实现见 widget/WidgetCommon.ets）----

  private palette(): WidgetPalette {
    const payload: WidgetDayPayload | undefined = this.payload();
    return new WidgetPalette(payload === undefined ? '' : payload.mode,
      payload === undefined ? '' : payload.accent);
  }

  build() {
    Column() {
      List({ space: 8 }) {
        // ---- 今天（真实日期标题，主题色高亮）----
        ListItem() {
          Row({ space: 6 }) {
            Text(this.todayTitle())
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().accent())
            Text(this.todayCount())
              .fontSize(11)
              .fontColor(this.palette().accent())
              .backgroundColor(this.palette().accentSoft())
              .borderRadius(6)
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            Blank()
            Text(this.todayWeek())
              .fontSize(11)
              .fontColor(this.palette().accent())
          }
          .width('100%')
        }

        if (this.todayCourses().length > 0) {
          ForEach(this.todayCourses().slice(0, 8), (course: WidgetDayCourse) => {
            ListItem() {
              this.courseRow(course)
            }
          }, (course: WidgetDayCourse, index: number) => `today-${course.name}-${course.place}-${course.teacher}-${course.startTime}-${course.endTime}-${course.period}-${course.state}-${course.color}-${index}`)
        } else {
          ListItem() {
            Column({ space: 2 }) {
              Text(this.todayEmptyText())
                .fontSize(14)
                .fontColor(this.palette().textSecondary())
              Text('点开卡片看看本周课表')
                .fontSize(11)
                .fontColor(this.palette().textTertiary())
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ top: 6, bottom: 6 })
          }
        }

        // ---- 下一个有课日期（仅今天已结束/没课时出现；真实日期标题，正常色）----
        if (this.showNext()) {
          ListItem() {
            Row({ space: 6 }) {
              Text(this.nextTitle())
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().textPrimary())
              Text(this.nextCount())
                .fontSize(11)
                .fontColor(this.palette().textSecondary())
                .backgroundColor(this.palette().surfaceHigh())
                .borderRadius(6)
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              Blank()
              Text(this.nextWeek())
                .fontSize(11)
                .fontColor(this.palette().textTertiary())
            }
            .width('100%')
            .padding({ top: 4 })
          }

          ForEach(this.nextCourses().slice(0, 8), (course: WidgetDayCourse) => {
            ListItem() {
              this.courseRow(course)
            }
          }, (course: WidgetDayCourse, index: number) => `next-${course.name}-${course.place}-${course.teacher}-${course.startTime}-${course.endTime}-${course.period}-${course.state}-${course.color}-${index}`)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
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
