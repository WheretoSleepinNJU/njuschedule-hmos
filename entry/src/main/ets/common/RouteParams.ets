/**
 * NavPathStack 路由参数类型。
 *
 * ArkTS 不允许把对象字面量直接传给 `Object` 形参，路由参数统一用带构造器的类，
 * 页面侧用 `pageStack.getParamByName(name)[0] as XxxParam` 取。
 */
export class CourseEditParam {
  tableId: number = 0;
  /** 0 表示新增课程。 */
  courseId: number = 0;

  constructor(tableId: number, courseId: number) {
    this.tableId = tableId;
    this.courseId = courseId;
  }
}
