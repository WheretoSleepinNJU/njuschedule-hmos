/**
 * 课程仓储：1:1 移植旧版 `CourseProvider`（lib/Models/CourseModel.dart）。
 *
 * 语义保持：
 * - 插入前若 `courseId == -1`，按「同表同名复用已有 course_id，否则取 MAX+1」分配。
 * - `weeks` 以 JSON 数组字符串存进 TEXT 列。
 * - 删除按 id；按表删除用于删除课表时级联清理。
 * - 同一门课的多行（meetings）按课程组整组读写：`getMeetings` 查询、
 *   `saveMeetingGroup` 在单个事务里 insert/update/delete 并复用同一个 course_id，
 *   事务内用 originals 做一致性校验，避免覆盖编辑期间被并发修改的数据。
 */
import { relationalStore } from '@kit.ArkData';
import { Course } from './models/Models';
import { CourseGroups } from './CourseGroups';
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
   * 注意：course_id 必须在事务外预分配——事务内插入的行对后续 SELECT 不可见。
   * 同一批里的同名课程也要复用同一个 id（否则多时段课程会被拆成不同颜色/分组），
   * 因此除查库外还要记录本批已分配的名字。
   */
  static async insertMany(courses: Course[]): Promise<number[]> {
    const store: relationalStore.RdbStore = await CourseRepository.store();
    let nextCourseId: number = await CourseRepository.maxCourseId();
    const assignedNames: Map<string, number> = new Map();
    for (let i = 0; i < courses.length; i++) {
      const course: Course = courses[i];
      const key: string = `${course.tableId}:${course.name}`;
      if (course.courseId >= 0) {
        assignedNames.set(key, course.courseId);
        continue;
      }
      const batchAssigned: number | undefined = assignedNames.get(key);
      if (batchAssigned !== undefined) {
        course.courseId = batchAssigned;
        continue;
      }
      const existing: number = await CourseRepository.findCourseIdByName(course.name, course.tableId);
      if (existing >= 0) {
        course.courseId = existing;
      } else {
        nextCourseId += 1;
        course.courseId = nextCourseId;
      }
      assignedNames.set(key, course.courseId);
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

  /**
   * 整组保存同一门课的全部时段（上游 `CourseProvider.saveMeetingGroup`）。
   *
   * - `originals`：编辑页打开时加载的原始组（数据库快照，行 id 均 > 0）；
   * - `meetings`：当前草稿，已有行保留 id（> 0），新增行 id = 0；
   * - 所有行的 `tableId` 必须一致且有效（> 0）；meetings 不得为空；
   * - 事务内先逐字段校验 originals 仍与数据库一致，不一致返回 false；
   * - 全部 meetings 写同一个 courseId：originals 已有 courseId 则复用，
   *   否则按全表 `MAX(course_id) + 1` 分配（事务内只查一次，避免逐条 MAX）；
   * - 新增行 insert、已有行 update、originals 中缺失的行 delete，同一事务提交；
   * - 任一步失败 rollback 并返回 false。
   *
   * 注意：失败时不会把新 id 回写到 `meetings`，草稿对象保持原样，
   * 编辑页可直接重试（与上游一致）。
   */
  static async saveMeetingGroup(originals: Course[], meetings: Course[]): Promise<boolean> {
    const tableId: number = CourseRepository.validGroupTableId(originals, meetings);
    if (tableId <= 0) {
      return false;
    }
    const removedIds: number[] = [];
    for (let i = 0; i < originals.length; i++) {
      const originalId: number = originals[i].id;
      let kept: boolean = false;
      for (let j = 0; j < meetings.length; j++) {
        if (meetings[j].id === originalId) {
          kept = true;
          break;
        }
      }
      if (!kept) {
        removedIds.push(originalId);
      }
    }
    const store: relationalStore.RdbStore = await CourseRepository.store();
    const tx: relationalStore.Transaction = await store.createTransaction();
    try {
      if (originals.length > 0 && !await CourseRepository.groupUnchanged(tx, originals)) {
        await tx.rollback();
        return false;
      }
      let courseId: number = -1;
      if (originals.length > 0 && originals[0].courseId >= 0) {
        courseId = originals[0].courseId;
      } else {
        courseId = (await CourseRepository.maxCourseIdInTx(tx)) + 1;
      }
      for (let i = 0; i < meetings.length; i++) {
        const meeting: Course = meetings[i];
        const bucket: relationalStore.ValuesBucket =
          CourseRepository.toValuesBucketWithCourseId(meeting, courseId);
        if (meeting.id > 0) {
          const affected: number =
            await tx.update(bucket, CourseRepository.rowPredicates(meeting.id, tableId));
          if (affected !== 1) {
            throw new Error(`课程时段不存在（保存）：id=${meeting.id}`);
          }
        } else {
          const rowId: number = await tx.insert(LegacySchema.COURSE_TABLE, bucket);
          if (rowId <= 0) {
            throw new Error('课程时段插入失败');
          }
        }
      }
      for (let i = 0; i < removedIds.length; i++) {
        const affected: number =
          await tx.delete(CourseRepository.rowPredicates(removedIds[i], tableId));
        if (affected !== 1) {
          throw new Error(`课程时段不存在（删除）：id=${removedIds[i]}`);
        }
      }
      await tx.commit();
      return true;
    } catch (err) {
      await tx.rollback().catch((rollbackErr: Error) => {
        console.warn(`[CourseRepository] saveMeetingGroup rollback failed: ${JSON.stringify(rollbackErr)}`);
      });
      console.warn(`[CourseRepository] saveMeetingGroup failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  /**
   * 整组删除同一门课的全部时段（上游 `CourseProvider.deleteMeetingGroup`）。
   *
   * - originals 不能为空，行 id 均 > 0、同表且不重复；
   * - 事务内先校验 originals 仍与数据库一致（不存在/已变化返回 false）；
   * - 逐行按 `id + tableid` 删除，任一步失败 rollback 并返回 false。
   */
  static async deleteMeetingGroup(originals: Course[]): Promise<boolean> {
    const tableId: number = CourseRepository.validOriginalGroup(originals);
    if (tableId <= 0) {
      return false;
    }
    const store: relationalStore.RdbStore = await CourseRepository.store();
    const tx: relationalStore.Transaction = await store.createTransaction();
    try {
      if (!await CourseRepository.groupUnchanged(tx, originals)) {
        await tx.rollback();
        return false;
      }
      for (let i = 0; i < originals.length; i++) {
        const affected: number =
          await tx.delete(CourseRepository.rowPredicates(originals[i].id, tableId));
        if (affected !== 1) {
          throw new Error(`课程时段不存在（整组删除）：id=${originals[i].id}`);
        }
      }
      await tx.commit();
      return true;
    } catch (err) {
      await tx.rollback().catch((rollbackErr: Error) => {
        console.warn(`[CourseRepository] deleteMeetingGroup rollback failed: ${JSON.stringify(rollbackErr)}`);
      });
      console.warn(`[CourseRepository] deleteMeetingGroup failed: ${JSON.stringify(err)}`);
      return false;
    }
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

  /**
   * 查询同一门课的全部时段（上游 `CourseProvider.getMeetings`）。
   *
   * 读该表全部行后按 `CourseGroups.sameCourse` 过滤：`course` 通常是用行 id
   * 从库里读出的原始行，返回值包含它自身；找不到时返回空数组。
   */
  static async getMeetings(course: Course): Promise<Course[]> {
    const all: Course[] = await CourseRepository.getAll(course.tableId);
    const meetings: Course[] = [];
    for (let i = 0; i < all.length; i++) {
      if (CourseGroups.sameCourse(course, all[i])) {
        meetings.push(all[i]);
      }
    }
    return meetings;
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
   * 编辑期间的一致性校验：originals 必须仍能在库中按同组找齐，且每个字段都未变化。
   * 上游 `_groupUnchanged` 的等价实现；防止覆盖其他入口对同一门课的并发修改。
   */
  private static async groupUnchanged(tx: relationalStore.Transaction,
    originals: Course[]): Promise<boolean> {
    const tableId: number = originals[0].tableId;
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates(LegacySchema.COURSE_TABLE);
    predicates.equalTo(LegacySchema.COURSE_TABLE_ID, tableId);
    const resultSet: relationalStore.ResultSet = await tx.query(predicates);
    const group: Course[] = [];
    try {
      while (resultSet.goToNextRow()) {
        const row: Course = CourseRepository.fromResultSet(resultSet);
        if (CourseGroups.sameCourse(originals[0], row)) {
          group.push(row);
        }
      }
    } finally {
      resultSet.close();
    }
    if (group.length !== originals.length) {
      return false;
    }
    for (let i = 0; i < originals.length; i++) {
      const original: Course = originals[i];
      let matched: Course | null = null;
      for (let j = 0; j < group.length; j++) {
        if (group[j].id === original.id) {
          matched = group[j];
          break;
        }
      }
      if (matched === null || !CourseRepository.samePersistedFields(original, matched)) {
        return false;
      }
    }
    return true;
  }

  /** 两个 Course 的落库字段是否完全一致（不含仅在内存中的语义，如 id 已包含）。 */
  private static samePersistedFields(a: Course, b: Course): boolean {
    if (a.id !== b.id || a.tableId !== b.tableId || a.name !== b.name ||
      a.classroom !== b.classroom || a.classNumber !== b.classNumber ||
      a.teacher !== b.teacher || a.testTime !== b.testTime ||
      a.testLocation !== b.testLocation || a.link !== b.link || a.info !== b.info ||
      a.weekTime !== b.weekTime || a.startTime !== b.startTime ||
      a.timeCount !== b.timeCount || a.importType !== b.importType ||
      a.color !== b.color || a.courseId !== b.courseId) {
      return false;
    }
    return CourseRepository.sameWeeks(a.weeks, b.weeks);
  }

  private static sameWeeks(a: number[], b: number[]): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }

  /** 事务内全表 MAX(course_id)；必须在使用事务写入前调用（事务内插入行对 SELECT 不可见）。 */
  private static async maxCourseIdInTx(tx: relationalStore.Transaction): Promise<number> {
    const resultSet: relationalStore.ResultSet = await tx.querySql(
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

  /** 按 `id + tableid` 定位一行（update / delete 共用）。 */
  private static rowPredicates(id: number, tableId: number): relationalStore.RdbPredicates {
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates(LegacySchema.COURSE_TABLE);
    predicates.equalTo(LegacySchema.COURSE_ID, id);
    predicates.and();
    predicates.equalTo(LegacySchema.COURSE_TABLE_ID, tableId);
    return predicates;
  }

  /**
   * 校验整组保存入参，返回组所属 tableId；<= 0 表示非法。
   *
   * - meetings 不能为空，首个 tableId 必须有效（> 0）；
   * - originals / meetings 的 tableId 必须都与组 tableId 一致；
   * - originals 行 id 必须 > 0 且不重复；
   * - meetings 中已有行 id 必须 > 0、来自 originals 且不重复；id = 0 表示新增。
   */
  private static validGroupTableId(originals: Course[], meetings: Course[]): number {
    if (meetings.length === 0) {
      return -1;
    }
    const tableId: number = meetings[0].tableId;
    if (tableId <= 0) {
      return -1;
    }
    if (originals.length > 0 && CourseRepository.validOriginalGroup(originals) !== tableId) {
      return -1;
    }
    const updatedIds: number[] = [];
    for (let i = 0; i < meetings.length; i++) {
      const meeting: Course = meetings[i];
      if (meeting.tableId !== tableId) {
        return -1;
      }
      if (meeting.id > 0) {
        if (updatedIds.indexOf(meeting.id) >= 0) {
          return -1;
        }
        let belongsToOriginal: boolean = false;
        for (let j = 0; j < originals.length; j++) {
          if (originals[j].id === meeting.id) {
            belongsToOriginal = true;
            break;
          }
        }
        if (!belongsToOriginal) {
          return -1;
        }
        updatedIds.push(meeting.id);
      }
    }
    return tableId;
  }

  /** 校验整组删除入参，返回组所属 tableId；<= 0 表示非法。 */
  private static validOriginalGroup(originals: Course[]): number {
    if (originals.length === 0) {
      return -1;
    }
    const tableId: number = originals[0].tableId;
    if (tableId <= 0) {
      return -1;
    }
    const ids: number[] = [];
    for (let i = 0; i < originals.length; i++) {
      const original: Course = originals[i];
      if (original.tableId !== tableId || original.id <= 0 || ids.indexOf(original.id) >= 0) {
        return -1;
      }
      ids.push(original.id);
    }
    return tableId;
  }

  /**
   * 列名必须与 LegacySchema 常量一致（ArkTS 不允许对象字面量用计算属性名，
   * 因此这里写字面量；LegacySchema 是这些名字的唯一来源，改动需同步）。
   */
  private static toValuesBucket(course: Course): relationalStore.ValuesBucket {
    return CourseRepository.toValuesBucketWithCourseId(course, course.courseId);
  }

  /** 同 `toValuesBucket`，但强制覆盖 course_id（整组保存时全组共用一个）。 */
  private static toValuesBucketWithCourseId(course: Course,
    courseId: number): relationalStore.ValuesBucket {
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
      course_id: courseId
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
