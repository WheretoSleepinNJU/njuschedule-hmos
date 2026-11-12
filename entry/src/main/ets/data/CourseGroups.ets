/**
 * 课程组：同一门课（同表同名）的多个时段行判定与归组。
 *
 * 1:1 移植上游 `lib/Models/CourseGroup.dart`（NJU-Class-Shedule-Flutter）。
 * `Course` 表里同一门课可能有多行，每行有自己的周次 / 教室 / 节次，
 * 这些行共享课程级字段（课程名、`importType`、`courseId` 等）。
 *
 * 与上游的唯一差异是 null 的表示：
 * - 上游 `id == null` 表示尚未入库；本工程用 `id = 0`（见 Models.ets 约定），
 *   因此只有 `id > 0` 的已入库行才参与「同一行」短路；
 * - 上游 `courseId == null` 表示未分配；本工程用 `courseId = -1`。
 */
import { Course } from './models/Models';

export class CourseGroups {
  /**
   * 两行是否属于同一门课。
   *
   * 顺序与上游一致：表 → 行 id → 课程名/importType → 班号 → courseId → 教师。
   * - id 相同的已入库行直接认定同一行；
   * - 课程名 trim 后必须非空且相等，且 importType 相同；
   * - classNumber 任一方非空时以班号为准（要求双方非空且相等）；
   * - 否则双方 courseId 都已分配（>= 0）时比较 courseId；
   * - 最后回落到教师名 trim 比较。
   */
  static sameCourse(a: Course, b: Course): boolean {
    if (a.tableId !== b.tableId) {
      return false;
    }
    // id = 0 表示尚未入库（上游为 null），不能把两个新草稿当成同一行。
    if (a.id > 0 && a.id === b.id) {
      return true;
    }
    const nameA: string = a.name.trim();
    const nameB: string = b.name.trim();
    if (nameA.length === 0 || nameA !== nameB || a.importType !== b.importType) {
      return false;
    }
    const classNumberA: string = a.classNumber.trim();
    const classNumberB: string = b.classNumber.trim();
    if (classNumberA.length > 0 || classNumberB.length > 0) {
      return classNumberA.length > 0 && classNumberA === classNumberB;
    }
    if (a.courseId >= 0 && b.courseId >= 0) {
      return a.courseId === b.courseId;
    }
    return a.teacher.trim() === b.teacher.trim();
  }

  /**
   * 把一组时间重叠的课程行按课程组合并，并选出指定周次的代表行。
   *
   * - 同一门课的多个时段只保留一个代表；
   * - 只返回本周实际生效的课程组，已经不上本周的组不参与冲突展示。
   */
  static representativesForWeek(courses: Course[], week: number): Course[] {
    const grouped: Course[][] = CourseGroups.collect(courses);
    const representatives: Course[] = [];
    for (let i = 0; i < grouped.length; i++) {
      const members: Course[] = grouped[i];
      for (let j = 0; j < members.length; j++) {
        if (members[j].weeks.indexOf(week) >= 0) {
          representatives.push(members[j]);
          break;
        }
      }
    }
    return representatives;
  }

  /**
   * 按出现顺序把课程行归组，组内第一行作为后续比较的基准。
   * 上游 `CourseGroup.collect` 的等价实现。
   */
  static collect(courses: Course[]): Course[][] {
    const groups: Course[][] = [];
    for (let i = 0; i < courses.length; i++) {
      const course: Course = courses[i];
      let target: Course[] | null = null;
      for (let j = 0; j < groups.length; j++) {
        if (CourseGroups.sameCourse(groups[j][0], course)) {
          target = groups[j];
          break;
        }
      }
      if (target === null) {
        groups.push([course]);
      } else {
        target.push(course);
      }
    }
    return groups;
  }
}
