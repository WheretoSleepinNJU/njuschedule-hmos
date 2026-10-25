/**
 * 设计令牌。
 *
 * 颜色全部走资源引用（`app.color.*` + `resources/dark` 限定词），跟随系统深浅色切换；
 * 数值令牌是纯常量，供布局代码使用。页面不得硬编码色值。
 *
 * 取值来源：旧版 Flutter 项目 `lib/Resources/Themes.dart` 的视觉基线
 * （背景 #F8F8FA / #0F0F11、卡片面 #E9E9ED / #1F1F23、圆角 14vp）。
 */
export class Spacing {
  static readonly Xs: number = 4;
  static readonly Sm: number = 8;
  static readonly Md: number = 12;
  static readonly Lg: number = 16;
  static readonly Xl: number = 20;
  static readonly Xxl: number = 24;
  static readonly Xxxl: number = 32;
}

export class Radius {
  static readonly Xs: number = 6;
  static readonly Sm: number = 8;
  static readonly Md: number = 12;
  static readonly Lg: number = 14;
  static readonly Xl: number = 20;
  static readonly Round: number = 999;
}

export class FontSize {
  static readonly Caption: number = 11;
  static readonly BodySm: number = 13;
  static readonly Body: number = 15;
  static readonly Title: number = 17;
  static readonly Headline: number = 20;
  static readonly Display: number = 24;
  static readonly Hero: number = 34;
}

/** HDS 标题栏度量：页面滚动内容铺到标题栏下方，滚动内容顶部预留该高度。 */
export class HdsMetrics {
  static readonly TitleBarHeight: number = 56;
  static readonly TitleBarBreathing: number = 8;
  /** HDS IconStyleMode.NORMAL 的标题栏图标默认尺寸（24vp）。 */
  static readonly TitleBarIconSize: number = 24;

  static contentTopInset(insetVp: number): number {
    return insetVp + HdsMetrics.TitleBarHeight + HdsMetrics.TitleBarBreathing;
  }
}

export class Durations {
  static readonly Fast: number = 150;
  static readonly Standard: number = 250;
  static readonly Slow: number = 350;
}

/** 亮色 / 暗色两套资源都定义了同名颜色，组件只引用这里的令牌。 */
export class Colors {
  static readonly Background: Resource = $r('app.color.app_bg');
  static readonly AppBar: Resource = $r('app.color.app_appbar');
  static readonly Surface: Resource = $r('app.color.app_surface');
  /** 浮动按钮底板（跟随系统深浅色）。 */
  static readonly Floating: Resource = $r('app.color.app_floating');
  static readonly SurfaceHigh: Resource = $r('app.color.app_surface_high');
  static readonly SurfacePressed: Resource = $r('app.color.app_surface_pressed');
  /** 半透明表面（用于浮在内容上的条/卡片，配合背景模糊）。 */
  static readonly SurfaceTranslucent: Resource = $r('app.color.app_surface_translucent');
  static readonly Outline: Resource = $r('app.color.app_outline');
  static readonly OutlineLight: Resource = $r('app.color.app_outline_light');

  static readonly TextPrimary: Resource = $r('app.color.app_text_primary');
  static readonly TextSecondary: Resource = $r('app.color.app_text_secondary');
  static readonly TextTertiary: Resource = $r('app.color.app_text_tertiary');
  static readonly TextOnPrimary: Resource = $r('app.color.app_text_on_primary');

  static readonly Primary: Resource = $r('app.color.app_primary');
  static readonly PrimaryLight: Resource = $r('app.color.app_primary_light');
  static readonly PrimaryDark: Resource = $r('app.color.app_primary_dark');

  static readonly Error: Resource = $r('app.color.app_error');
  static readonly ErrorLight: Resource = $r('app.color.app_error_light');
  static readonly Warning: Resource = $r('app.color.app_warning');
  static readonly WarningLight: Resource = $r('app.color.app_warning_light');
  static readonly Success: Resource = $r('app.color.app_success');
  static readonly SuccessLight: Resource = $r('app.color.app_success_light');

  static readonly GridLine: Resource = $r('app.color.app_grid_line');
  static readonly GridWeekend: Resource = $r('app.color.app_grid_weekend');
  static readonly TodayBg: Resource = $r('app.color.app_today_bg');
  static readonly NowLine: Resource = $r('app.color.app_now_line');
  static readonly Scrim: Resource = $r('app.color.app_overlay_scrim');
  static readonly Dialog: Resource = $r('app.color.app_dialog_bg');
}

/** 课表网格的几何常量（旧版 `classHeight` 默认 50，可在设置里调整）。 */
export class TimetableMetrics {
  static readonly HeaderHeight: number = 56;
  static readonly TimeColumnWidth: number = 40;
  static readonly DefaultClassHeight: number = 50;
  static readonly MinClassHeight: number = 36;
  static readonly MaxClassHeight: number = 80;
  static readonly CourseBlockGap: number = 2;
  static readonly CourseBlockRadius: number = 6;
}

/**
 * 课程块上的文字颜色：课程色是固定色池里的浅色（不随深色模式变化），
 * 因此块内文字必须用固定的深色，不能用 Colors.TextPrimary。
 */
export class CourseBlockColors {
  static readonly Text: string = '#1F1F1F';
  static readonly TextSecondary: string = '#4A4A4A';
  /** 深色模式：课程块底叠了深色表面，地点/教师等次要文字必须改用浅色。 */
  static readonly TextSecondaryDark: string = '#E0E0E0';
  static readonly Border: string = '#33000000';
}
