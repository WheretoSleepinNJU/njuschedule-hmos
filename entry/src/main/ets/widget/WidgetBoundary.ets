/**
 * 上下课边界计算与下一次触发刷新预约。
 *
 * 卡片不做分钟级轮询：每次 FormExtension 更新后，只预约最近的课程开始/结束边界，
 * 到点由系统触发 onUpdateForm。
 */
interface BoundaryCourse {
  startTime: string;
  endTime: string;
}

interface BoundaryPayload {
  courses: BoundaryCourse[];
}

export class WidgetBoundary {
  /**
   * 返回距离下一次课程开始/结束的分钟数；无边界返回 0。
   * setFormNextRefreshTime 最小支持 5 分钟。
   */
  static nextRefreshMinutes(json: string): number {
    try {
      const payload: BoundaryPayload = JSON.parse(json) as BoundaryPayload;
      const now: Date = new Date();
      const nowMinutes: number = now.getHours() * 60 + now.getMinutes();
      let best: number = 24 * 60 + 1;
      const courses: BoundaryCourse[] = payload.courses === undefined ? [] : payload.courses;
      for (let i = 0; i < courses.length; i++) {
        const start: number = WidgetBoundary.toMinutes(courses[i].startTime);
        const end: number = WidgetBoundary.toMinutes(courses[i].endTime);
        if (start > nowMinutes && start - nowMinutes < best) {
          best = start - nowMinutes;
        }
        if (end > nowMinutes && end - nowMinutes < best) {
          best = end - nowMinutes;
        }
      }
      if (best > 24 * 60) {
        return 0;
      }
      return Math.max(5, Math.ceil(best));
    } catch (err) {
      console.warn(`[WidgetBoundary] nextRefreshMinutes failed: ${JSON.stringify(err)}`);
      return 0;
    }
  }

  private static toMinutes(text: string): number {
    const parts: string[] = text.split(':');
    if (parts.length < 2) {
      return -1;
    }
    const hour: number = parseInt(parts[0], 10);
    const minute: number = parseInt(parts[1], 10);
    if (isNaN(hour) || isNaN(minute)) {
      return -1;
    }
    return hour * 60 + minute;
  }
}
