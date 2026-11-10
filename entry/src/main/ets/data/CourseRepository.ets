/**
 * 课程仓储：1:1 移植旧版 `CourseProvider`（lib/Models/CourseModel.dart）。
 *
 * 语义保持：
 * - 插入前若 `courseId == -1`，按「同表同名复用已有 course_id，否则取 MAX+1」分配。
 * - `weeks` 以 JSON 数组字符串存进 TEXT 列。
 * - 删除按 id；按表删除用于删除课表时级联清理。
 */
import { relationalStore } from '@kit.ArkData';
import { Course } from './models/Models';
import { Db } from './Db';
import { LegacySchema } from './Db';
import { RdbUtil } from './RdbUtil';

export class CourseRepository {
  private static async store(): Promise<relationalStore.RdbStore> {
    return Db.open();
  }

  static async insert(course: Course): Promise<Course> {
    const store: relationalStore.RdbStore = await CourseRepository.store();
    if (course.courseId < 0) {
      course.courseId = await CourseRepository.getCourseId(course);
    }
    const rowId: number = await store.insert(LegacySchema.COURSE_TABLE, CourseRepository.toValuesBucket(course));
    course.id = rowId;
    return course;
  }

  /**
   * 批量插入（导入用），单次事务内完成。
   *
   * 注意：course_id 必须在事务外预分配——事务内插入的行对后续 SELECT 不可见，
   * 若逐条查 MAX(course_id) 会让整批课程拿到同一个 id，课程颜色就全一样了。
   */
  static async insertMany(courses: Course[]): Promise<number[]> {
    const store: relationalStore.RdbStore = await CourseRepository.store();
    let nextCourseId: number = await CourseRepository.maxCourseId();
    for (let i = 0; i < courses.length; i++) {
      const course: Course = courses[i];
      if (course.courseId >= 0) {
        continue;
      }
      const existing: number = await CourseRepository.findCourseIdByName(course.name, course.tableId);
      if (existing >= 0) {
        course.courseId = existing;
      } else {
        nextCourseId += 1;
        course.courseId = nextCourseId;
      }
    }
    const ids: number[] = [];
    const tx: relationalStore.Transaction = await store.createTransaction();
    try {
      for (let i = 0; i < courses.length; i++) {
        const course: Course = courses[i];
        const rowId: number = await tx.insert(LegacySchema.COURSE_TABLE, CourseRepository.toValuesBucket(course));
        course.id = rowId;
        ids.push(rowId);
      }
      await tx.commit();
    } catch (err) {
      await tx.rollback().catch((rollbackErr: Error) => {
        console.warn(`[CourseRepository] rollback failed: ${JSON.stringify(rollbackErr)}`);
      });
      throw err as Error;
    }
    return ids;
  }

  /** 全表 MAX(course_id)，无记录时返回 -1（对应旧版「MAX 为 null → 0」的下一个值）。 */
  static async maxCourseId(): Promise<number> {
    const store: relationalStore.RdbStore = await CourseRepository.store();
    const resultSet: relationalStore.ResultSet = await store.querySql(
      `SELECT MAX(${LegacySchema.COURSE_COURSE_ID}) AS max_id FROM ${LegacySchema.COURSE_TABLE}`);
    try {
      if (resultSet.goToNextRow() && !RdbUtil.isNull(resultSet, 'max_id')) {
        return RdbUtil.num(resultSet, 'max_id', -1);
      }
      return -1;
    } finally {
      resultSet.close();
    }
  }

  /** 同表同名课程的已有 course_id，没有则返回 -1。 */
  static async findCourseIdByName(name: string, tableId: number): Promise<number> {
    const store: relationalStore.RdbStore = await CourseRepository.store();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(LegacySchema.COURSE_TABLE);
    predicates.equalTo(LegacySchema.COURSE_NAME, name);
    predicates.and();
    predicates.equalTo(LegacySchema.COURSE_TABLE_ID, tableId);
    const resultSet: relationalStore.ResultSet = await store.query(predicates, [LegacySchema.COURSE_COURSE_ID]);
    try {
      if (resultSet.goToNextRow()) {
        return RdbUtil.num(resultSet, LegacySchema.COURSE_COURSE_ID, -1);
      }
      return -1;
    } finally {
      resultSet.close();
    }
  }

  static async update(course: Course): Promise<number> {
    const store: relationalStore.RdbStore = await CourseRepository.store();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(LegacySchema.COURSE_TABLE);
    predicates.equalTo(LegacySchema.COURSE_ID, course.id);
    return store.update(CourseRepository.toValuesBucket(course), predicates);
  }

  static async delete(courseId: number): Promise<number> {
    const store: relationalStore.RdbStore = await CourseRepository.store();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(LegacySchema.COURSE_TABLE);
    predicates.equalTo(LegacySchema.COURSE_ID, courseId);
    return store.delete(predicates);
  }

  static async deleteByTable(tableId: number): Promise<number> {
    const store: relationalStore.RdbStore = await CourseRepository.store();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(LegacySchema.COURSE_TABLE);
    predicates.equalTo(LegacySchema.COURSE_TABLE_ID, tableId);
    return store.delete(predicates);
  }

  static async getAll(tableId: number): Promise<Course[]> {
    const store: relationalStore.RdbStore = await CourseRepository.store();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(LegacySchema.COURSE_TABLE);
    predicates.equalTo(LegacySchema.COURSE_TABLE_ID, tableId);
    const resultSet: relationalStore.ResultSet = await store.query(predicates);
    try {
      const courses: Course[] = [];
      while (resultSet.goToNextRow()) {
        courses.push(CourseRepository.fromResultSet(resultSet));
      }
      return courses;
    } finally {
      resultSet.close();
    }
  }

  static async getById(courseId: number): Promise<Course | null> {
    const store: relationalStore.RdbStore = await CourseRepository.store();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(LegacySchema.COURSE_TABLE);
    predicates.equalTo(LegacySchema.COURSE_ID, courseId);
    const resultSet: relationalStore.ResultSet = await store.query(predicates);
    try {
      if (resultSet.goToNextRow()) {
        return CourseRepository.fromResultSet(resultSet);
      }
      return null;
    } finally {
      resultSet.close();
    }
  }

  static async count(): Promise<number> {
    const store: relationalStore.RdbStore = await CourseRepository.store();
    const resultSet: relationalStore.ResultSet = await store.querySql(
      `SELECT COUNT(*) AS cnt FROM ${LegacySchema.COURSE_TABLE}`);
    try {
      if (resultSet.goToNextRow()) {
        return RdbUtil.num(resultSet, 'cnt', 0);
      }
      return 0;
    } finally {
      resultSet.close();
    }
  }

  static async checkHasCourseByName(tableId: number, name: string): Promise<boolean> {
    const store: relationalStore.RdbStore = await CourseRepository.store();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(LegacySchema.COURSE_TABLE);
    predicates.equalTo(LegacySchema.COURSE_TABLE_ID, tableId);
    predicates.and();
    predicates.equalTo(LegacySchema.COURSE_NAME, name);
    const resultSet: relationalStore.ResultSet = await store.query(predicates, [LegacySchema.COURSE_ID]);
    try {
      return resultSet.rowCount > 0;
    } finally {
      resultSet.close();
    }
  }

  /**
   * 同门课复用 course_id：先在同表内按课程名查找，找不到则取全表 MAX(course_id)+1。
   * 旧版对 `course_id` 列的 MAX 查询没有过滤 tableId，这里保持一致。
   */
  static async getCourseId(course: Course): Promise<number> {
    const existing: number = await CourseRepository.findCourseIdByName(course.name, course.tableId);
    if (existing >= 0) {
      return existing;
    }
    return (await CourseRepository.maxCourseId()) + 1;
  }

  /**
   * 列名必须与 LegacySchema 常量一致（ArkTS 不允许对象字面量用计算属性名，
   * 因此这里写字面量；LegacySchema 是这些名字的唯一来源，改动需同步）。
   */
  private static toValuesBucket(course: Course): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      tableid: course.tableId,
      name: course.name,
      classroom: course.classroom,
      class_number: course.classNumber,
      teacher: course.teacher,
      test_time: course.testTime,
      test_location: course.testLocation,
      link: course.link,
      info: course.info,
      weeks: JSON.stringify(course.weeks),
      week_time: course.weekTime,
      start_time: course.startTime,
      time_count: course.timeCount,
      import_type: course.importType,
      color: course.color,
      course_id: course.courseId
    };
    return bucket;
  }

  private static fromResultSet(resultSet: relationalStore.ResultSet): Course {
    const course: Course = new Course();
    course.id = RdbUtil.num(resultSet, LegacySchema.COURSE_ID, 0);
    course.tableId = RdbUtil.num(resultSet, LegacySchema.COURSE_TABLE_ID, 0);
    course.name = RdbUtil.str(resultSet, LegacySchema.COURSE_NAME);
    course.classroom = RdbUtil.str(resultSet, LegacySchema.COURSE_CLASSROOM);
    course.classNumber = RdbUtil.str(resultSet, LegacySchema.COURSE_CLASS_NUMBER);
    course.teacher = RdbUtil.str(resultSet, LegacySchema.COURSE_TEACHER);
    course.testTime = RdbUtil.str(resultSet, LegacySchema.COURSE_TEST_TIME);
    course.testLocation = RdbUtil.str(resultSet, LegacySchema.COURSE_TEST_LOCATION);
    course.link = RdbUtil.str(resultSet, LegacySchema.COURSE_LINK);
    course.info = RdbUtil.str(resultSet, LegacySchema.COURSE_INFO);
    course.weeks = RdbUtil.parseIntArray(RdbUtil.str(resultSet, LegacySchema.COURSE_WEEKS));
    course.weekTime = RdbUtil.num(resultSet, LegacySchema.COURSE_WEEK_TIME, 0);
    course.startTime = RdbUtil.num(resultSet, LegacySchema.COURSE_START_TIME, 0);
    course.timeCount = RdbUtil.num(resultSet, LegacySchema.COURSE_TIME_COUNT, 0);
    course.importType = RdbUtil.num(resultSet, LegacySchema.COURSE_IMPORT_TYPE, 0);
    course.color = RdbUtil.str(resultSet, LegacySchema.COURSE_COLOR);
    course.courseId = RdbUtil.num(resultSet, LegacySchema.COURSE_COURSE_ID, -1);
    return course;
  }
}
