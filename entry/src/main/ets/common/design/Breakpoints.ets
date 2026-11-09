/**
 * 断点模型（沿用 `ref/applications_app_samples` 的 320 / 600 / 840vp 官方阈值，
 * 与 `hydrotoolkit-hmos` 保持一致），并附带按断点取值的 `BreakpointType<T>`。
 */
export enum BreakpointName {
  Xs = 'xs',
  Sm = 'sm',
  Md = 'md',
  Lg = 'lg',
  Xl = 'xl'
}

/** 与官方 WidthBreakpoint 对齐：<320 / 320–600 / 600–840 / 840–1440 / ≥1440vp。 */
export class BreakpointRange {
  static readonly Sm: number = 320;
  static readonly Md: number = 600;
  static readonly Lg: number = 840;
  static readonly Xl: number = 1440;
}

/** 将官方 UIContext.getWindowWidthBreakpoint() 映射为项目断点。 */
export function breakpointNameOf(value: WidthBreakpoint): BreakpointName {
  if (value === WidthBreakpoint.WIDTH_XL) {
    return BreakpointName.Xl;
  }
  if (value === WidthBreakpoint.WIDTH_LG) {
    return BreakpointName.Lg;
  }
  if (value === WidthBreakpoint.WIDTH_MD) {
    return BreakpointName.Md;
  }
  if (value === WidthBreakpoint.WIDTH_SM) {
    return BreakpointName.Sm;
  }
  return BreakpointName.Xs;
}

export function resolveBreakpoint(widthVp: number): BreakpointName {
  if (widthVp >= BreakpointRange.Xl) {
    return BreakpointName.Xl;
  }
  if (widthVp >= BreakpointRange.Lg) {
    return BreakpointName.Lg;
  }
  if (widthVp >= BreakpointRange.Md) {
    return BreakpointName.Md;
  }
  if (widthVp >= BreakpointRange.Sm) {
    return BreakpointName.Sm;
  }
  return BreakpointName.Xs;
}

export function isExpandedBreakpoint(breakpoint: BreakpointName): boolean {
  return breakpoint === BreakpointName.Md || breakpoint === BreakpointName.Lg;
}

export function isTabletBreakpoint(breakpoint: BreakpointName): boolean {
  return breakpoint === BreakpointName.Lg || breakpoint === BreakpointName.Xl;
}

export class BreakpointType<T> {
  private xsValue: T;
  private smValue: T;
  private mdValue: T;
  private lgValue: T;
  private xlValue: T;

  constructor(xs: T, sm: T, md: T, lg: T, xl?: T) {
    this.xsValue = xs;
    this.smValue = sm;
    this.mdValue = md;
    this.lgValue = lg;
    this.xlValue = xl === undefined ? lg : xl;
  }

  value(breakpoint: BreakpointName): T {
    if (breakpoint === BreakpointName.Xl) {
      return this.xlValue;
    }
    if (breakpoint === BreakpointName.Lg) {
      return this.lgValue;
    }
    if (breakpoint === BreakpointName.Md) {
      return this.mdValue;
    }
    if (breakpoint === BreakpointName.Sm) {
      return this.smValue;
    }
    return this.xsValue;
  }
}
