/**
 * 日期工具（替代旧版 `intl` 的 DateFormat 用法）。
 *
 * 只做课表需要的格式化：`yyyy-MM-dd`、`MM/dd`。
 * 一律使用本地时区，避免 `new Date('yyyy-MM-dd')` 被解析成 UTC 造成跨日偏移。
 */
export class DateUtils {
  static today(): Date {
    const now: Date = new Date();
    return new Date(now.getFullYear(), now.getMonth(), now.getDate());
  }

  static pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  static formatIsoDate(date: Date): string {
    return `${date.getFullYear()}-${DateUtils.pad2(date.getMonth() + 1)}-${DateUtils.pad2(date.getDate())}`;
  }

  static parseIsoDate(text: string): Date {
    const parts: string[] = text.split('-');
    if (parts.length !== 3) {
      return DateUtils.today();
    }
    const year: number = parseInt(parts[0], 10);
    const month: number = parseInt(parts[1], 10);
    const day: number = parseInt(parts[2], 10);
    if (isNaN(year) || isNaN(month) || isNaN(day)) {
      return DateUtils.today();
    }
    return new Date(year, month - 1, day);
  }

  static formatMonthDay(date: Date): string {
    return `${DateUtils.pad2(date.getMonth() + 1)}/${DateUtils.pad2(date.getDate())}`;
  }

  /** HH:mm，讲座卡片用。 */
  static formatHm(date: Date): string {
    return `${DateUtils.pad2(date.getHours())}:${DateUtils.pad2(date.getMinutes())}`;
  }

  /** 周一为一周起点（与旧版 WeekUtil 相同）。 */
  static mondayOf(date: Date): Date {
    const day: Date = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    // getDay(): 0=周日 ... 6=周六；换算成 1=周一 ... 7=周日
    const weekday: number = day.getDay() === 0 ? 7 : day.getDay();
    return DateUtils.addDays(day, -(weekday - 1));
  }

  static addDays(date: Date, days: number): Date {
    const result: Date = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    result.setDate(result.getDate() + days);
    return result;
  }

  /** 整日差（b - a），按本地日历日计算。 */
  static daysBetween(a: Date, b: Date): number {
    const msPerDay: number = 24 * 60 * 60 * 1000;
    const utcA: number = Date.UTC(a.getFullYear(), a.getMonth(), a.getDate());
    const utcB: number = Date.UTC(b.getFullYear(), b.getMonth(), b.getDate());
    return Math.round((utcB - utcA) / msPerDay);
  }

  /** 本周周一的 ISO 字符串（旧版 `_getMonday`）。 */
  static currentMondayString(): string {
    return DateUtils.formatIsoDate(DateUtils.mondayOf(DateUtils.today()));
  }

  static weekdayOneBased(date: Date): number {
    const weekday: number = date.getDay();
    return weekday === 0 ? 7 : weekday;
  }
}
