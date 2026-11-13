/**
 * 课表页主标题：按时辰的问候语。
 *
 * 十二时辰按两小时一段（子时从 23:00 起）；午后（未/申）合并为「下午好」，
 * 入夜（戌/亥）合并为「晚上好」，其余各用一句不超过 3 字的问候。
 */
export class TimeGreeting {
  /** 子、丑、寅……亥各时辰的问候（午后与入夜各重复一次）。 */
  private static readonly GREETINGS: string[] = [
    '夜深了', // 子 23:00–00:59
    '好梦',   // 丑 01:00–02:59
    '天将明', // 寅 03:00–04:59
    '早安',   // 卯 05:00–06:59
    '早上好', // 辰 07:00–08:59
    '上午好', // 巳 09:00–10:59
    '中午好', // 午 11:00–12:59
    '下午好', // 未 13:00–14:59
    '下午好', // 申 15:00–16:59
    '傍晚好', // 酉 17:00–18:59
    '晚上好', // 戌 19:00–20:59
    '晚上好'  // 亥 21:00–22:59
  ];

  /** 当前时刻对应的问候。 */
  static current(): string {
    return TimeGreeting.of(new Date());
  }

  /** 指定时刻对应的问候（便于测试与跨时辰刷新）。 */
  static of(date: Date): string {
    const hour: number = date.getHours();
    // 以 23:00 为子时起点：0 点仍属子时，按 (hour + 1) / 2 取段。
    const index: number = Math.floor(((hour + 1) % 24) / 2);
    return TimeGreeting.GREETINGS[index];
  }
}
