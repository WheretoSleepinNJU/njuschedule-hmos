/**
 * 课程 / 课表实体（移植自旧版 `lib/Models/CourseModel.dart`、
 * `lib/Models/CourseTableModel.dart`、`lib/Models/Db/DbHelper.dart`）。
 *
 * 内存表示与 SQLite 列一一对应，唯一差异：
 * - `weeks` 在内存中是 `number[]`，落库时序列化为 JSON 数组字符串
 *   （旧版同样把 `List<int>.toString()` 写进 `weeks TEXT` 列）。
 * - 旧版的 null 用默认值代替：`id = 0` 表示尚未入库，`courseId = -1` 表示未分配。
 *
 * 语义约定（勿改）：
 * - `weekTime`：星期几，1-7；0 表示自由时间（不占节次）。
 * - `startTime`：起始节次，1 基。
 * - `timeCount`：节次跨度减一，即课程块渲染高度为 `timeCount + 1` 节。
 */

export class Course {
  id: number = 0;
  name: string = '';
  tableId: number = 0;

  classroom: string = '';
  classNumber: string = '';
  teacher: string = '';
  testTime: string = '';
  testLocation: string = '';
  link: string = '';
  info: string = '';

  /** 上课周次，如 [1,2,3,...]；空数组表示未设置。 */
  weeks: number[] = [];
  weekTime: number = 0;
  startTime: number = 0;
  timeCount: number = 0;

  /** LegacyConstant.ADD_MANUALLY / ADD_BY_IMPORT / ADD_BY_LECTURE */
  importType: number = 0;
  /** 自定义颜色（`#RRGGBB`），空串表示走色池。 */
  color: string = '';
  /** 同一门课（同表同名）共享的配色下标；-1 表示未分配。 */
  courseId: number = -1;

  constructor(name: string = '', tableId: number = 0) {
    this.name = name;
    this.tableId = tableId;
  }

  /** 是否为自由时间课程（旧版 weekTime == 0 的约定）。 */
  isFreeCourse(): boolean {
    return this.weekTime === 0;
  }

  /** 该课程在某一周是否上课。 */
  hasWeek(week: number): boolean {
    return this.weeks.indexOf(week) >= 0;
  }

  clone(): Course {
    const c: Course = new Course(this.name, this.tableId);
    c.id = this.id;
    c.classroom = this.classroom;
    c.classNumber = this.classNumber;
    c.teacher = this.teacher;
    c.testTime = this.testTime;
    c.testLocation = this.testLocation;
    c.link = this.link;
    c.info = this.info;
    c.weeks = this.weeks.slice();
    c.weekTime = this.weekTime;
    c.startTime = this.startTime;
    c.timeCount = this.timeCount;
    c.importType = this.importType;
    c.color = this.color;
    c.courseId = this.courseId;
    return c;
  }
}

export class CourseTable {
  id: number = 0;
  name: string = '';
  /** 与旧版一致：JSON 字符串，可含 `class_time_list` 与 `semester_start_monday`。 */
  data: string = '';

  constructor(name: string = '', data: string = '') {
    this.name = name;
    this.data = data;
  }
}
