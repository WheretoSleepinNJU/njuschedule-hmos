/**
 * 教务导入 payload 解码与课程映射。
 *
 * 协议来源：旧版导入规格（仓库外归档）§4 / §5.1。
 * - 远端 `api/tools/*.js` 的最后一个表达式都返回
 *   `encodeURIComponent(JSON.stringify({ name, courses }))`，即**字符串**；
 * - `courses` 可能是数组、JSON 字符串（njuyjsxk / sjtuyjsxk）甚至二次序列化字符串；
 * - 课程字段是 snake_case，少数脚本用驼峰（classNumber / weekTime...），两种都兼容。
 *
 * 与旧版 `CourseImportCodec` 的差异：
 * - 旧版用 `replaceAll('"', '')` 清引号后再 decode；这里只剥最外层引号，
 *   避免未编码 JSON 时破坏内容（规格 §11.3 明确要求）。
 * - `color` 留空、`courseId = -1`（由 `CourseRepository.insertMany` 统一分配）。
 */
import { LegacyConstant } from '../../common/Constants';
import { Course } from '../../data/models/Models';

/** 解码后的 payload：课表名 + 原始课程对象数组（尚未映射成 Course）。 */
export class ImportPayload {
  name: string = '';
  courses: Object[] = [];
}

export class ImportPayloadDecoder {
  /**
   * 把 `runJavaScript` 的返回值解码成 payload。
   * @param jsReturnValue Web 侧脚本返回值（百分号编码的 JSON 字符串）
   * @param fallbackName payload.name 缺失时使用的课表名
   * @throws Error 带有可读中文原因，供页面直接展示
   */
  static decode(jsReturnValue: string, fallbackName: string): ImportPayload {
    const trimmed: string = jsReturnValue.trim();
    if (trimmed === '') {
      throw new Error('解析脚本没有返回值（页面可能还没渲染完成）');
    }
    const unwrapped: string = ImportPayloadDecoder.unwrapJsString(trimmed);
    if (unwrapped === '') {
      throw new Error('解析脚本返回为空');
    }
    const decoded: string = ImportPayloadDecoder.percentDecode(unwrapped);
    let parsedValue: Object;
    try {
      parsedValue = JSON.parse(decoded) as Object;
    } catch (err) {
      throw new Error(`课表数据不是合法 JSON（开头：${preview(decoded)}）`);
    }
    if (parsedValue === null) {
      throw new Error('课表数据为空');
    }
    if (Array.isArray(parsedValue)) {
      throw new Error('课表数据格式不正确：顶层应为对象而非数组');
    }

    const parsed: Record<string, Object> = parsedValue as Record<string, Object>;
    const payload: ImportPayload = new ImportPayload();
    payload.name = valueText(parsed['name']);
    if (payload.name === '') {
      payload.name = fallbackName;
    }
    payload.courses = ImportPayloadDecoder.normalizeCourses(parsed['courses']);
    return payload;
  }

  /**
   * 去掉 runJavaScript 返回结果的 JSON 字符串外壳。
   * Web 侧返回 JS 字符串时，ArkWeb 可能给出 `"..."`（JSON 文本）而不是裸字符串。
   */
  static unwrapJsString(raw: string): string {
    let text: string = raw.trim();
    if (text === 'null' || text === 'undefined') {
      return '';
    }
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      try {
        const parsed: Object = JSON.parse(text) as Object;
        if (typeof parsed === 'string') {
          return parsed as string;
        }
      } catch (err) {
        // 不是合法 JSON 字符串，按裸字符串处理（去掉首尾引号）。
      }
      text = text.substring(1, text.length - 1);
    }
    return text;
  }

  /** 百分号解码；未编码或存在非法百分号序列时原样返回。 */
  static percentDecode(raw: string): string {
    if (raw.indexOf('%') < 0) {
      return raw;
    }
    try {
      return decodeURIComponent(raw);
    } catch (err) {
      return raw;
    }
  }

  /**
   * 把 `courses` 归一化成对象数组：
   * 数组直接使用；字符串则最多解两层 JSON（兼容二次序列化）。
   */
  static normalizeCourses(value: Object | undefined): Object[] {
    let current: Object | undefined = value;
    for (let depth = 0; depth < 3; depth++) {
      if (current === undefined || current === null) {
        return [];
      }
      if (Array.isArray(current)) {
        const items: Object[] = current as Object[];
        const courses: Object[] = [];
        for (let i = 0; i < items.length; i++) {
          const item: Object = items[i];
          if (item !== null && typeof item === 'object' && !Array.isArray(item)) {
            courses.push(item);
          }
        }
        return courses;
      }
      if (typeof current === 'string') {
        const text: string = (current as string).trim();
        if (text === '') {
          return [];
        }
        try {
          current = JSON.parse(text) as Object;
        } catch (err) {
          return [];
        }
      } else {
        return [];
      }
    }
    return [];
  }
}

export class ImportCourseCodec {
  /** payload 里的课程对象 → `Course`（week_time/周次语义保持旧版）。 */
  static toCourses(rawCourses: Object[], tableId: number): Course[] {
    const courses: Course[] = [];
    for (let i = 0; i < rawCourses.length; i++) {
      const item: Object = rawCourses[i];
      if (item === null || typeof item !== 'object' || Array.isArray(item)) {
        continue;
      }
      const raw: Record<string, Object> = item as Record<string, Object>;
      const name: string = valueText(raw['name']);
      if (name === '') {
        // 没有课名的行无法展示，与旧版插入空名课程相比更安全。
        continue;
      }
      const course: Course = new Course(name, tableId);
      course.classroom = valueText(raw['classroom']);
      course.classNumber = valueTextEither(raw, 'class_number', 'classNumber');
      course.teacher = valueText(raw['teacher']);
      course.testTime = valueTextEither(raw, 'test_time', 'testTime');
      course.testLocation = valueTextEither(raw, 'test_location', 'testLocation');
      course.link = valueText(raw['link']);
      course.info = valueText(raw['info']);
      course.weeks = ImportCourseCodec.normalizeWeeks(raw['weeks']);
      course.weekTime = valueIntEither(raw, 'week_time', 'weekTime', 0);
      course.startTime = valueIntEither(raw, 'start_time', 'startTime', 0);
      course.timeCount = valueIntEither(raw, 'time_count', 'timeCount', 0);
      course.importType = valueIntEither(raw, 'import_type', 'importType', LegacyConstant.ADD_BY_IMPORT);
      // 规格 §5.1：在线导入不带颜色；course_id 交给仓储按同表同名规则分配。
      course.color = '';
      course.courseId = -1;
      courses.push(course);
    }
    return courses;
  }

  /**
   * weeks 归一化为正整数数组（规格 §5.1 / §5.3）：
   * 数组逐项转 int、丢弃 ≤0；字符串先尝试 JSON 数组，再退化为抽取数字。
   * 保留脚本给出的顺序，不去重不排序（与旧版 codec 一致）。
   */
  static normalizeWeeks(value: Object | undefined): number[] {
    const weeks: number[] = [];
    if (value === undefined || value === null) {
      return weeks;
    }
    if (Array.isArray(value)) {
      appendWeeks(weeks, value as Object[]);
      return weeks;
    }
    if (typeof value === 'string') {
      const text: string = (value as string).trim();
      if (text === '') {
        return weeks;
      }
      if (text.startsWith('[')) {
        try {
          return ImportCourseCodec.normalizeWeeks(JSON.parse(text) as Object);
        } catch (err) {
          // 落到下面的数字抽取。
        }
      }
      const regex: RegExp = new RegExp('\\d+', 'g');
      let match: RegExpExecArray | null = regex.exec(text);
      while (match !== null) {
        const week: number = parseInt(match[0], 10);
        if (!Number.isNaN(week) && week > 0) {
          weeks.push(week);
        }
        match = regex.exec(text);
      }
    }
    return weeks;
  }

  /**
   * 组装 `CourseTable.data`：
   * - 两个字段都没有 → 空串（旧版默认作息）；
   * - 有任一字段 → 只写入存在的字段，`class_time_list` 原样拼接（键名/结构不变）。
   */
  static buildTableData(classTimeListJson: string, semesterStartMonday: string): string {
    const hasClassTime: boolean = classTimeListJson !== '';
    const hasSemesterStart: boolean = semesterStartMonday !== '';
    if (!hasClassTime && !hasSemesterStart) {
      return '';
    }
    const parts: string[] = [];
    if (hasClassTime) {
      parts.push('"class_time_list":' + classTimeListJson);
    }
    if (hasSemesterStart) {
      parts.push('"semester_start_monday":' + JSON.stringify(semesterStartMonday));
    }
    return '{' + parts.join(',') + '}';
  }
}

function appendWeeks(target: number[], items: Object[]): void {
  for (let i = 0; i < items.length; i++) {
    const week: number = valueInt(items[i], -1);
    if (week > 0) {
      target.push(week);
    }
  }
}

function preview(text: string): string {
  if (text.length <= 120) {
    return text;
  }
  return text.substring(0, 120) + '…';
}

function valueText(value: Object | undefined): string {
  if (value === undefined || value === null) {
    return '';
  }
  if (typeof value === 'string') {
    return value as string;
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return value.toString();
  }
  return '';
}

function valueTextEither(raw: Record<string, Object>, snakeKey: string, camelKey: string): string {
  const snake: string = valueText(raw[snakeKey]);
  if (snake !== '') {
    return snake;
  }
  return valueText(raw[camelKey]);
}

function valueInt(value: Object | undefined, fallback: number): number {
  if (value === undefined || value === null) {
    return fallback;
  }
  if (typeof value === 'number') {
    const num: number = value as number;
    return Number.isFinite(num) ? Math.trunc(num) : fallback;
  }
  if (typeof value === 'string') {
    const num: number = parseInt(value as string, 10);
    return Number.isNaN(num) ? fallback : num;
  }
  return fallback;
}

function valueIntEither(raw: Record<string, Object>, snakeKey: string, camelKey: string,
  fallback: number): number {
  const snake: Object | undefined = raw[snakeKey];
  if (snake !== undefined && snake !== null) {
    return valueInt(snake, fallback);
  }
  return valueInt(raw[camelKey], fallback);
}
