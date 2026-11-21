/**
 * 颜色计算工具（纯函数，无状态依赖，可被 app / widget / 卡片页面共用）。
 *
 * 提供：预设主题色、相对亮度（WCAG）、混色、深色模式主题色自动提亮。
 * 自动提亮规则：深色模式下若强调色相对亮度过低（< 0.28），按比例向白色混合，
 * 目标相对亮度 0.32（相对深色背景对比度约 5.5:1），保留原色相与饱和度倾向。
 */
export class ColorMath {
  /** 9 个预设主题色（顺序与旧版一致；下标 9 留给自定义色）。 */
  static readonly PRESETS: string[] = [
    '#0095F9',
    '#4CAF50',
    '#002B82',
    '#4D0099',
    '#C52830',
    '#DDA3B2',
    '#2D7D93',
    '#919FC5',
    '#638190'
  ];

  static readonly CUSTOM_INDEX: number = 9;
  /** 南哪紫在预设数组中的下标（应用默认主题色）。 */
  static readonly NJU_PURPLE_INDEX: number = 3;

  /** 深色模式自动提亮的目标相对亮度。 */
  static readonly DARK_TARGET_LUMINANCE: number = 0.32;
  /** 相对亮度达到该值就不再提亮。 */
  static readonly DARK_ENOUGH_LUMINANCE: number = 0.28;

  static isValidHex(hex: string): boolean {
    return new RegExp('^#[0-9A-Fa-f]{6}$').test(hex);
  }

  static preset(index: number): string {
    if (index >= 0 && index < ColorMath.PRESETS.length) {
      return ColorMath.PRESETS[index];
    }
    return ColorMath.PRESETS[ColorMath.NJU_PURPLE_INDEX];
  }

  /** #RRGGBB → [r,g,b]。 */
  static channels(hex: string): number[] {
    if (!ColorMath.isValidHex(hex)) {
      return [128, 128, 128];
    }
    const value: number = Number.parseInt(hex.substring(1), 16);
    return [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF];
  }

  static toHex(rgb: number[]): string {
    const part = (v: number): string => {
      const clamped: number = Math.max(0, Math.min(255, Math.round(v)));
      const text: string = clamped.toString(16);
      return text.length === 1 ? `0${text}` : text;
    };
    return `#${part(rgb[0])}${part(rgb[1])}${part(rgb[2])}`;
  }

  /** WCAG 相对亮度（0 = 黑，1 = 白）。 */
  static luminance(hex: string): number {
    const rgb: number[] = ColorMath.channels(hex);
    const linear = (channel: number): number => {
      const v: number = channel / 255;
      return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2]);
  }

  /** 按比例把 base 向 target 混色（ratio 0-1）。 */
  static mix(base: string, target: string, ratio: number): string {
    const a: number[] = ColorMath.channels(base);
    const b: number[] = ColorMath.channels(target);
    const r: number = Math.max(0, Math.min(1, ratio));
    return ColorMath.toHex([
      a[0] + (b[0] - a[0]) * r,
      a[1] + (b[1] - a[1]) * r,
      a[2] + (b[2] - a[2]) * r
    ]);
  }

  /**
   * 深色模式下自动提亮过暗的强调色；浅色模式或已经够亮时原样返回。
   *
   * 注意：混色发生在 sRGB 空间，直接按亮度比例一次混色达不到目标亮度，
   * 这里用二分搜索找到满足目标相对亮度的混色比例（最多 12 次迭代，结果确定）。
   */
  static deriveDarkAccent(base: string): string {
    if (!ColorMath.isValidHex(base)) {
      return base;
    }
    if (ColorMath.luminance(base) >= ColorMath.DARK_ENOUGH_LUMINANCE) {
      return base;
    }
    const target: number = ColorMath.DARK_TARGET_LUMINANCE;
    let low: number = 0;
    let high: number = 1;
    let result: string = ColorMath.mix(base, '#FFFFFF', 1);
    for (let i = 0; i < 12; i++) {
      const mid: number = (low + high) / 2;
      const mixed: string = ColorMath.mix(base, '#FFFFFF', mid);
      result = mixed;
      if (ColorMath.luminance(mixed) < target) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return result;
  }

  /**
   * 强调色上的文字/图标颜色：
   * - 自动提亮后的深色变体通常较亮 → 配深色文字；
   * - 基础色沿用旧规则（相对亮度 > 0.55 用深色，否则白色）。
   */
  static onAccent(accent: string, derivedForDark: boolean): string {
    const threshold: number = derivedForDark ? 0.24 : 0.55;
    return ColorMath.luminance(accent) > threshold ? '#1F1F1F' : '#FFFFFF';
  }
}
