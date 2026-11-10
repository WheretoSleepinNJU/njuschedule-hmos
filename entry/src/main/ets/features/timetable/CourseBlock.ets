/**
 * 课表网格里的一个课程块。
 *
 * 视觉对齐系统日历的课程表：
 * - 浅色底（课程色叠一层主题表面色，自动适配深浅色）
 * - 标题用课程色自身的深/浅变体（深色模式下自动提亮）
 * - 地点、教师分行显示；冲突课程右上角显示数量角标
 */
import { AppStore } from '../../app/AppStore';
import { Course } from '../../data/models/Models';
import { Colors, CourseBlockColors, FontSize, Radius } from '../../common/design/Tokens';

@ComponentV2
export struct CourseBlock {
  /** V2 全局 Store（深色外观）。 */
  @Local store: AppStore = AppStore.connect();
  @Param course: Course = new Course();
  @Param color: string = '#8AD297';
  @Param widthPx: number = 0;
  @Param heightPx: number = 0;
  /** 放在自适应日期列内时宽度跟随列宽。 */
  @Param fillWidth: boolean = false;
  /** 本周不上、仅淡显的课程。 */
  @Param faded: boolean = false;
  /** 同一时段的课程数量（>1 时显示角标）。 */
  @Param conflictCount: number = 0;
  @Param showPlace: boolean = true;
  @Param showTeacher: boolean = false;
  @Event onTap: () => void = () => {
  };
  @Event onLongPress: () => void = () => {
  };

  private blockColor(): string {
    return this.faded ? '#CCCCCC' : this.color;
  }

  /** 地点/教师等次要文字：浅色底用深灰，深色模式下课程块底变深，改用浅灰保证可读性。 */
  private secondaryTextColor(): string {
    return this.store.isDark ? CourseBlockColors.TextSecondaryDark : CourseBlockColors.TextSecondary;
  }

  private canShowPlace(): boolean {
    return this.showPlace && this.heightPx >= 40 && this.course.classroom !== '';
  }

  private canShowTeacher(): boolean {
    return this.showTeacher && this.heightPx >= 56 && this.course.teacher !== '';
  }

  /** '#RRGGBB' → [r,g,b]；非法返回中性灰。 */
  private rgb(hex: string): number[] {
    if (hex.length !== 7 || hex.charAt(0) !== '#') {
      return [128, 128, 128];
    }
    const value: number = Number.parseInt(hex.substring(1), 16);
    if (Number.isNaN(value)) {
      return [128, 128, 128];
    }
    return [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF];
  }

  private toHex(rgb: number[]): string {
    const part = (v: number): string => {
      const clamped: number = Math.max(0, Math.min(255, Math.round(v)));
      const text: string = clamped.toString(16);
      return text.length === 1 ? `0${text}` : text;
    };
    return `#${part(rgb[0])}${part(rgb[1])}${part(rgb[2])}`;
  }

  /** 课程色 → 标题色：浅色模式压暗，深色模式提亮，保证与浅底/深底都有对比。 */
  private titleColor(): string {
    if (this.faded) {
      return CourseBlockColors.TextSecondary;
    }
    const base: number[] = this.rgb(this.color);
    const target: number[] = this.store.isDark ? [255, 255, 255] : [26, 26, 26];
    const ratio: number = this.store.isDark ? 0.62 : 0.55;
    const mixed: number[] = [
      base[0] + (target[0] - base[0]) * ratio,
      base[1] + (target[1] - base[1]) * ratio,
      base[2] + (target[2] - base[2]) * ratio
    ];
    return this.toHex(mixed);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 浅色底：课程色 + 表面色叠加，深浅色主题自动适配
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(this.blockColor())
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(Colors.Surface)
        .opacity(this.faded ? 0.55 : 0.7)

      Column({ space: 2 }) {
        Text(this.course.name)
          .fontSize(this.heightPx >= 56 ? FontSize.BodySm : FontSize.Caption)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.titleColor())
          .maxLines(this.heightPx >= 72 ? 3 : (this.heightPx >= 56 ? 2 : 1))
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.canShowPlace()) {
          Text(this.course.classroom)
            .fontSize(FontSize.Caption)
            .fontColor(this.secondaryTextColor())
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        if (this.canShowTeacher()) {
          Text(this.course.teacher)
            .fontSize(FontSize.Caption)
            .fontColor(this.secondaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 6, right: 4, top: 5, bottom: 2 })

      if (this.conflictCount > 1) {
        if (this.fillWidth) {
          Row() {
            Blank()
            Text(`${this.conflictCount}`)
              .fontSize(9)
              .fontColor('#FFFFFF')
              .backgroundColor('#99000000')
              .borderRadius(Radius.Round)
              .width(14)
              .height(14)
              .textAlign(TextAlign.Center)
              .margin({ top: 2, right: 2 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.End)
          .alignItems(VerticalAlign.Top)
          .hitTestBehavior(HitTestMode.None)
        } else {
          Text(`${this.conflictCount}`)
            .fontSize(9)
            .fontColor('#FFFFFF')
            .backgroundColor('#99000000')
            .borderRadius(Radius.Round)
            .width(14)
            .height(14)
            .textAlign(TextAlign.Center)
            .position({ x: this.widthPx - 16, y: 2 })
        }
      }
    }
    .width(this.fillWidth ? '100%' : `${this.widthPx}vp`)
    .height(this.heightPx)
    .borderRadius(Radius.Sm)
    .clip(true)
    .onClick(() => {
      this.onTap();
    })
    .gesture(LongPressGesture({ repeat: false }).onAction(() => {
      this.onLongPress();
    }))
  }
}
