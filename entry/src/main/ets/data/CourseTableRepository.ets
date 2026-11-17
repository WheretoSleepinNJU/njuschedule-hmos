/**
 * 课表仓储：1:1 移植旧版 `CourseTableProvider`（lib/Models/CourseTableModel.dart）。
 *
 * `CourseTable.data` 是 JSON 字符串，旧版约定字段：
 * - `class_time_list`: `[{"start":"08:00","end":"08:50"}, ...]`，缺省用默认作息
 * - `semester_start_monday`: `"2026-09-21"`，缺省为空串
 */
import { relationalStore } from '@kit.ArkData';
import { AppPreferences } from '../app/AppPreferences';
import { ClassPeriod, LegacyConstant, LegacyConfig } from '../common/Constants';
import { CourseTable } from './models/Models';
import { CourseRepository } from './CourseRepository';
import { Db, LegacySchema } from './Db';
import { RdbUtil } from './RdbUtil';

interface PeriodJson {
  start?: string;
  end?: string;
}

interface CourseTableDataJson {
  class_time_list?: PeriodJson[];
  semester_start_monday?: string;
}

export class CourseTableRepository {
  private static async store(): Promise<relationalStore.RdbStore> {
    return Db.open();
  }

  static async insert(table: CourseTable): Promise<CourseTable> {
    const store: relationalStore.RdbStore = await CourseTableRepository.store();
    const bucket: relationalStore.ValuesBucket = {
      'name': table.name,
      'data': table.data
    };
    table.id = await store.insert(LegacySchema.COURSETABLE_TABLE, bucket);
    return table;
  }

  static async update(table: CourseTable): Promise<number> {
    const store: relationalStore.RdbStore = await CourseTableRepository.store();
    const bucket: relationalStore.ValuesBucket = {
      'name': table.name,
      'data': table.data
    };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(LegacySchema.COURSETABLE_TABLE);
    predicates.equalTo(LegacySchema.COURSETABLE_ID, table.id);
    return store.update(bucket, predicates);
  }

  static async getById(tableId: number): Promise<CourseTable | null> {
    const store: relationalStore.RdbStore = await CourseTableRepository.store();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(LegacySchema.COURSETABLE_TABLE);
    predicates.equalTo(LegacySchema.COURSETABLE_ID, tableId);
    const resultSet: relationalStore.ResultSet = await store.query(predicates);
    try {
      if (resultSet.goToNextRow()) {
        const table: CourseTable = new CourseTable();
        table.id = RdbUtil.num(resultSet, LegacySchema.COURSETABLE_ID, 0);
        table.name = RdbUtil.str(resultSet, LegacySchema.COURSETABLE_NAME);
        table.data = RdbUtil.str(resultSet, LegacySchema.COURSETABLE_DATA);
        return table;
      }
      return null;
    } finally {
      resultSet.close();
    }
  }

  /**
   * 只取 id/name，与旧版 `getAllCourseTable` 一致（列表页不需要 data）。
   * 排序：优先课表管理页保存的自定义顺序，未记录的课表按数据库顺序追加。
   */
  static async getAll(): Promise<CourseTable[]> {
    const store: relationalStore.RdbStore = await CourseTableRepository.store();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(LegacySchema.COURSETABLE_TABLE);
    const resultSet: relationalStore.ResultSet = await store.query(predicates,
      [LegacySchema.COURSETABLE_ID, LegacySchema.COURSETABLE_NAME]);
    try {
      const tables: CourseTable[] = [];
      while (resultSet.goToNextRow()) {
        const table: CourseTable = new CourseTable();
        table.id = RdbUtil.num(resultSet, LegacySchema.COURSETABLE_ID, 0);
        table.name = RdbUtil.str(resultSet, LegacySchema.COURSETABLE_NAME);
        tables.push(table);
      }
      return CourseTableRepository.applySavedOrder(tables);
    } finally {
      resultSet.close();
    }
  }

  /** 保存课表管理页的拖拽顺序（只影响列表展示，不写 CourseTable.data）。 */
  static async saveOrder(tables: CourseTable[]): Promise<void> {
    const ids: number[] = [];
    for (let i = 0; i < tables.length; i++) {
      ids.push(tables[i].id);
    }
    await AppPreferences.setTableOrder(ids);
  }

  private static async applySavedOrder(tables: CourseTable[]): Promise<CourseTable[]> {
    if (tables.length <= 1) {
      return tables;
    }
    let order: number[] = [];
    try {
      order = await AppPreferences.getTableOrder();
    } catch (err) {
      // 顺序只是展示偏好，读失败不能影响课表列表本身。
      console.warn(`[CourseTable] 读取课表顺序失败: ${JSON.stringify(err)}`);
      return tables;
    }
    if (order.length === 0) {
      return tables;
    }
    const byId: Map<number, CourseTable> = new Map();
    for (let i = 0; i < tables.length; i++) {
      byId.set(tables[i].id, tables[i]);
    }
    const sorted: CourseTable[] = [];
    for (let i = 0; i < order.length; i++) {
      const table: CourseTable | undefined = byId.get(order[i]);
      if (table !== undefined) {
        sorted.push(table);
        byId.delete(order[i]);
      }
    }
    // 新导入/未记录顺序的课表追加在末尾，保持数据库顺序。
    for (let i = 0; i < tables.length; i++) {
      if (byId.has(tables[i].id)) {
        sorted.push(tables[i]);
      }
    }
    return sorted;
  }

  /** 删除课表并级联删除其课程（旧版 delete 会先调 CourseProvider.deleteByTable）。 */
  static async delete(tableId: number): Promise<number> {
    const store: relationalStore.RdbStore = await CourseTableRepository.store();
    await CourseRepository.deleteByTable(tableId);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(LegacySchema.COURSETABLE_TABLE);
    predicates.equalTo(LegacySchema.COURSETABLE_ID, tableId);
    return store.delete(predicates);
  }

  /** 作息列表：data.class_time_list 缺失或非法时回落默认作息。 */
  static async getClassTimeList(tableId: number): Promise<ClassPeriod[]> {
    const table: CourseTable | null = await CourseTableRepository.getById(tableId);
    if (table === null || table.data === '') {
      return LegacyConstant.CLASS_TIME_LIST;
    }
    try {
      const parsed: CourseTableDataJson = JSON.parse(table.data) as CourseTableDataJson;
      const list: PeriodJson[] | undefined = parsed.class_time_list;
      if (list === undefined || list === null || list.length === 0) {
        return LegacyConstant.CLASS_TIME_LIST;
      }
      const periods: ClassPeriod[] = [];
      for (let i = 0; i < list.length; i++) {
        const item: PeriodJson = list[i];
        const start: string = item.start === undefined ? '' : item.start;
        const end: string = item.end === undefined ? '' : item.end;
        periods.push(new ClassPeriod(start, end));
      }
      return periods.length === 0 ? LegacyConstant.CLASS_TIME_LIST : periods;
    } catch (err) {
      return LegacyConstant.CLASS_TIME_LIST;
    }
  }


  /** 首次启动兜底：没有任何课表时建「默认课表」（旧版 InitUtil.checkDataBase）。 */
  static async ensureDefaultTable(): Promise<void> {
    const tables: CourseTable[] = await CourseTableRepository.getAll();
    if (tables.length === 0) {
      await CourseTableRepository.insert(new CourseTable(LegacyConfig.DEFAULT_CLASS_TABLE, ''));
    }
  }
}
