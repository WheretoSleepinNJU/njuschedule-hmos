/**
 * 桌面小组件共享数据结构与调色板。
 *
 * 卡片渲染进程读不到主应用的 AppStorage，深浅色通过 payload.mode / 资源限定词处理；
 * 强调色使用 resources/base、dark 中的 widget_accent 资源，随系统深浅色自动切换。
 * 避免 2x2/2x4/4x4 三张卡片各写一份（原先 3 份实现已出现色值与 resources/dark 漂移）。
 */

/** 2x2 切换图标翻转时长；Form 推送需等动画完成，避免视图切换打断动画。 */
export const WIDGET_TOGGLE_FLIP_MS: number = 180;

/** 2x2 / 2x4 卡片里的单门课程（4x4 用 week 结构，单独定义）。 */
export interface WidgetDayCourse {
  name: string;
  place: string;
  teacher: string;
  time: string;
  startTime: string;
  endTime: string;
  period: string;
  color: string;
  state: string;
}

/** 2x2 / 2x4 卡片 payload（2x4 会带 teacher 字段，可选）。 */
export interface WidgetDayPayload {
  date: string;
  weekday: string;
  weekLabel: string;
  courses: WidgetDayCourse[];
  todayHasCourses: boolean;
  todayDone: boolean;
  todayTotal: number;
  nextDate: string;
  nextWeekday: string;
  nextWeekLabel: string;
  nextCourses: WidgetDayCourse[];
  nextFound: boolean;
  /** 2x2 视图：list / focus（focus 为课程进度页）。 */
  view?: string;
  /** 跟随系统时 2x2/2x4 使用资源色，系统深浅色切换无需打开应用。 */
  followSystem?: boolean;
  /** 2x2 focus 视图状态文案：上课中 / 下一节 / 今日课程已结束 等。 */
  focusStatus?: string;
  /** 2x2 focus 视图当前课程进度（0–100）。 */
  focusProgress?: number;
  /** 2x2 focus 视图当前/下一门课程。 */
  focusCourse?: WidgetDayCourse;
  /** 2x2 focus 视图课程所属日期（M/D）与星期（周一…）。 */
  focusDate?: string;
  focusWeekday?: string;
  mode: string;
}

/** 卡片调色板：mode = 'dark' | 'light' | 'auto'（自动使用 base/dark 资源）。 */
export class WidgetPalette {
  private readonly mode: string;

  constructor(mode: string) {
    this.mode = mode === undefined ? '' : mode;
  }

  isDark(): boolean {
    return this.mode === 'dark';
  }

  isLight(): boolean {
    return this.mode === 'light';
  }

  /** 小组件固定强调色资源，随系统深浅色自动切换，不跟随 App 自定义主题色。 */
  accent(): ResourceColor {
    return $r('app.color.widget_accent');
  }

  /** 小组件固定强调色的 12% 透明底色资源。 */
  accentSoft(): ResourceColor {
    return $r('app.color.widget_accent_soft');
  }

  cardBg(): ResourceColor {
    if (this.isDark()) {
      return '#1F1F23';
    }
    if (this.isLight()) {
      return '#FFFFFF';
    }
    return $r('app.color.app_surface');
  }

  surfaceHigh(): ResourceColor {
    if (this.isDark()) {
      return '#2A2A2E';
    }
    if (this.isLight()) {
      return '#F2F2F4';
    }
    return $r('app.color.app_surface_high');
  }

  textPrimary(): ResourceColor {
    if (this.isDark()) {
      return '#F2F2F2';
    }
    if (this.isLight()) {
      return '#1F1F1F';
    }
    return $r('app.color.app_text_primary');
  }

  textSecondary(): ResourceColor {
    if (this.isDark()) {
      return '#C8C8CC';
    }
    if (this.isLight()) {
      return '#6B6B70';
    }
    return $r('app.color.app_text_secondary');
  }

  textTertiary(): ResourceColor {
    if (this.isDark()) {
      return '#9A9AA0';
    }
    if (this.isLight()) {
      return '#8E8E93';
    }
    return $r('app.color.app_text_tertiary');
  }
}
