/**
 * 课程配色池：移植旧版 `lib/Utils/ColorUtil.dart` + `Course.getColor`。
 *
 * 旧版把 14 个色板下标洗牌后以字符串形式存进 prefs `colorPool`（`"[3, 1, 0]"`，
 * 同时是合法 JSON）。当前按课表使用 ColorAssignment 做多轮不放回分配：
 * 同一轮内每门课颜色不同，色池用完后才进入下一轮；自定义颜色优先。
 */
import { Course } from '../data/models/Models';
import { CourseColorPalette, CourseColorPalettes } from './CourseColorPalettes';
import { ColorAssignment } from './ColorAssignment';
import { AppPreferences } from '../app/AppPreferences';

export class ColorPool {
  private static cached: number[] = [];
  /** 重置时生成的散列种子；0 也可用，只影响首选色位。 */
  private static seed: number = 0;
  private static seedLoaded: boolean = false;
  /** 当前课表的 courseId → 色位分配；由 prepare() 按实际课程重建。 */
  private static assignments: Map<string, number> = new Map<string, number>();
  /** 当前选中的课程配色池。 */
  private static paletteId: string = CourseColorPalettes.DEFAULT_ID;
  private static paletteLoaded: boolean = false;

  /** 读取配色池；不存在时洗牌生成并持久化（旧版 checkColorPool）。 */
  static async check(): Promise<void> {
    await ColorPool.get();
  }

  static async getPaletteId(): Promise<string> {
    if (!ColorPool.paletteLoaded) {
      ColorPool.paletteId = await AppPreferences.getColorPalette();
      ColorPool.paletteLoaded = true;
    }
    return ColorPool.paletteId;
  }

  static currentPalette(): CourseColorPalette {
    return CourseColorPalettes.get(ColorPool.paletteId);
  }

  /** 切换课程配色池，并按新池立即重新随机分配。 */
  static async setPalette(id: string): Promise<void> {
    await ColorPool.getPaletteId();
    const palette: CourseColorPalette = CourseColorPalettes.get(id);
    ColorPool.paletteId = palette.id;
    ColorPool.paletteLoaded = true;
    ColorPool.cached = [];
    await AppPreferences.setColorPalette(palette.id);
    await ColorPool.shuffle();
  }

  static async get(): Promise<number[]> {
    await ColorPool.getPaletteId();
    if (!ColorPool.seedLoaded) {
      ColorPool.seed = await AppPreferences.getColorPoolSeed();
      ColorPool.seedLoaded = true;
    }
    if (ColorPool.cached.length > 0) {
      return ColorPool.cached;
    }
    const raw: string = await AppPreferences.getColorPoolRaw();
    const parsed: number[] = ColorPool.parsePool(raw);
    if (parsed.length > 0) {
      ColorPool.cached = parsed;
      return parsed;
    }
    return ColorPool.shuffle();
  }

  /** 按当前课表课程重建「多轮不放回」分配；渲染前调用。 */
  static prepare(courses: Course[], pool: number[]): void {
    ColorPool.assignments = ColorAssignment.build(courses, pool, ColorPool.seed);
  }

  /** 重新洗牌（设置页「重置课程颜色」用）。 */
  static async shuffle(): Promise<number[]> {
    await ColorPool.getPaletteId();
    const colors: string[] = ColorPool.currentPalette().colors;
    const pool: number[] = [];
    for (let i = 0; i < colors.length; i++) {
      pool.push(i);
    }
    // Fisher-Yates
    for (let i = pool.length - 1; i > 0; i--) {
      const j: number = Math.floor(Math.random() * (i + 1));
      const tmp: number = pool[i];
      pool[i] = pool[j];
      pool[j] = tmp;
    }
    ColorPool.cached = pool;
    ColorPool.assignments.clear();
    ColorPool.seed = Math.floor(Math.random() * 0x7FFFFFFE) + 1;
    ColorPool.seedLoaded = true;
    await AppPreferences.setColorPoolRaw(JSON.stringify(pool));
    await AppPreferences.setColorPoolSeed(ColorPool.seed);
    return pool;
  }

  /**
   * 解析课程颜色：`course.color` 是合法 `#RRGGBB`（或纯 `RRGGBB`）时优先用它，
   * 否则按当前课表的多轮不放回分配取色。返回可直接用于 ArkUI 的颜色字符串。
   */
  static resolve(course: Course, pool: number[]): string {
    const raw: string = course.color.trim();
    if (raw !== '') {
      const normalized: string = raw.startsWith('#') ? raw.substring(1) : raw;
      if (ColorPool.isValidHex(normalized)) {
        return raw.startsWith('#') ? raw : `#${raw}`;
      }
    }
    const colors: string[] = ColorPool.currentPalette().colors;
    if (course.courseId < 0 || pool.length === 0 || colors.length === 0) {
      return colors.length > 0 ? colors[0] : '#8AD297';
    }
    const assigned: number = ColorAssignment.colorOf(ColorPool.assignments, course);
    if (assigned >= 0 && assigned < colors.length) {
      return colors[assigned];
    }
    // 未 prepare 的兜底路径（例如旧页面尚未迁移时）沿用原散列规则。
    const poolIndex: number = ColorAssignment.fallbackColor(course, pool, ColorPool.seed);
    return colors[poolIndex >= 0 && poolIndex < colors.length ? poolIndex : 0];
  }


  private static isValidHex(normalized: string): boolean {
    return new RegExp('^[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$').test(normalized);
  }

  private static parsePool(raw: string): number[] {
    if (raw === '') {
      return [];
    }
    try {
      const parsed: number[] = JSON.parse(raw) as number[];
      if (!Array.isArray(parsed) || parsed.length === 0) {
        return [];
      }
      const result: number[] = [];
      for (let i = 0; i < parsed.length; i++) {
        const value: number = parsed[i];
        if (typeof value === 'number' && !isNaN(value)) {
          result.push(Math.trunc(value));
        }
      }
      return result;
    } catch (err) {
      return [];
    }
  }
}
