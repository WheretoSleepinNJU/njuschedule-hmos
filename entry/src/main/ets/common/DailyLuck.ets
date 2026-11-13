/**
 * 彩蛋「今日人品」：按「当天日期 + 设备 ODID」生成。
 * 同一设备同一天稳定不变，不同设备结果不同。
 */
import { deviceInfo } from '@kit.BasicServicesKit';

export class DailyLuck {
  /** 今天的人品值（0–100 的整数）。 */
  static today(): number {
    return DailyLuck.of(new Date());
  }

  static of(date: Date): number {
    const dayKey: string = `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`;
    const key: string = `${dayKey}|${deviceInfo.ODID}`;
    let hash: number = 2166136261;
    for (let i = 0; i < key.length; i++) {
      hash ^= key.charCodeAt(i);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0) % 101;
  }
}
