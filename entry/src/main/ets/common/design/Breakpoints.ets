/**
 * 断点模型（沿用 `ref/applications_app_samples` 的 320 / 600 / 840vp 官方阈值，
 * 与 `hydrotoolkit-hmos` 保持一致）。
 */
export enum BreakpointName {
  Xs = 'xs',
  Sm = 'sm',
  Md = 'md',
  Lg = 'lg',
  Xl = 'xl'
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

export function isTabletBreakpoint(breakpoint: BreakpointName): boolean {
  return breakpoint === BreakpointName.Lg || breakpoint === BreakpointName.Xl;
}
