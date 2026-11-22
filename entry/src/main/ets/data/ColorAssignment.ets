/**
 * 课程配色分配：同一课表内按「多轮不放回」取色。
 *
 * 每门课（courseId）先按哈希落到一个首选色位；若该色位本轮已被占用，
 * 线性探测下一个空位。本轮色池全部用完后清空占用表，开始下一轮。
 * 因此同一课表内，前 N 门课（N = 色池大小）颜色一定不重复；超过 N 门
 * 才允许跨轮复用。主应用和卡片进程共用本实现，避免两套取色逻辑漂移。
 */
import { Course } from './models/Models';

export class ColorAssignment {
  /** 课表内课程键：courseId 只在同一张课表内唯一。 */
  static key(course: Course): string {
    return ColorAssignment.keyOf(course.tableId, course.courseId);
  }

  private static keyOf(tableId: number, courseId: number): string {
    return `${tableId}:${courseId}`;
  }

  /**
   * 为一批课程生成 courseId → 色池下标 的映射。
   * 课程按 courseId 升序处理，新增课程通常追加在末尾，不会打乱已有课程。
   */
  static build(courses: Course[], pool: number[], seed: number): Map<string, number> {
    const assignments: Map<string, number> = new Map<string, number>();
    if (pool.length === 0) {
      return assignments;
    }
    const idsByTable: Map<number, Set<number>> = new Map<number, Set<number>>();
    for (let i = 0; i < courses.length; i++) {
      const course: Course = courses[i];
      if (course.courseId < 0) {
        continue;
      }
      let ids: Set<number> | undefined = idsByTable.get(course.tableId);
      if (ids === undefined) {
        ids = new Set<number>();
        idsByTable.set(course.tableId, ids);
      }
      ids.add(course.courseId);
    }
    idsByTable.forEach((ids: Set<number>, tableId: number) => {
      const sorted: number[] = [];
      ids.forEach((id: number): void => {
        sorted.push(id);
      });
      sorted.sort((a: number, b: number): number => a - b);
      const used: Set<number> = new Set<number>();
      for (let i = 0; i < sorted.length; i++) {
        if (used.size >= pool.length) {
          used.clear();
        }
        let slot: number = ColorAssignment.preferredSlot(sorted[i], seed, pool.length);
        while (used.has(slot)) {
          slot = (slot + 1) % pool.length;
        }
        used.add(slot);
        assignments.set(ColorAssignment.keyOf(tableId, sorted[i]), pool[slot]);
      }
    });
    return assignments;
  }

  /** 取已分配色位；没有分配时返回 -1（由调用方回退旧逻辑）。 */
  static colorOf(assignments: Map<string, number>, course: Course): number {
    const value: number | undefined = assignments.get(ColorAssignment.key(course));
    return value === undefined ? -1 : value;
  }

  /** 未 prepare 时的兜底取色；与主应用/卡片共用，避免两套散列实现漂移。 */
  static fallbackColor(course: Course, pool: number[], seed: number): number {
    if (course.courseId < 0 || pool.length === 0) {
      return -1;
    }
    return pool[ColorAssignment.preferredSlot(course.courseId, seed, pool.length)];
  }

  private static preferredSlot(courseId: number, seed: number, size: number): number {
    let mixed: number = Math.imul(courseId + 1, 2654435761) + seed;
    mixed = mixed ^ (mixed >>> 15);
    return (mixed >>> 0) % size;
  }
}
