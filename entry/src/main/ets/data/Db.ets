/**
 * 旧版 SQLite schema 的 ArkTS 侧镜像（移植自 `lib/Models/Db/DbHelper.dart`，
 * DATABASE_VERSION = 3，库名 `course.db`）。
 *
 * 列名、列类型、表名一律沿用旧版，便于对照与未来迁移。差异只有：
 * 建表语句改用 `IF NOT EXISTS`，避免重复打开时报错。
 */
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from '../app/AppContext';

/** 一条 v2 → v3 的列升级描述。 */
interface SchemaUpgrade {
  table: string;
  column: string;
}

export class LegacySchema {
  static readonly DB_NAME: string = 'course.db';
  static readonly DB_VERSION: number = 3;

  static readonly COURSE_TABLE: string = 'Course';
  static readonly COURSE_ID: string = 'id';
  static readonly COURSE_NAME: string = 'name';
  static readonly COURSE_TABLE_ID: string = 'tableid';
  static readonly COURSE_CLASSROOM: string = 'classroom';
  static readonly COURSE_CLASS_NUMBER: string = 'class_number';
  static readonly COURSE_TEACHER: string = 'teacher';
  static readonly COURSE_TEST_TIME: string = 'test_time';
  static readonly COURSE_TEST_LOCATION: string = 'test_location';
  static readonly COURSE_LINK: string = 'link';
  static readonly COURSE_INFO: string = 'info';
  static readonly COURSE_DATA: string = 'data';
  static readonly COURSE_WEEKS: string = 'weeks';
  static readonly COURSE_WEEK_TIME: string = 'week_time';
  static readonly COURSE_START_TIME: string = 'start_time';
  static readonly COURSE_TIME_COUNT: string = 'time_count';
  static readonly COURSE_IMPORT_TYPE: string = 'import_type';
  static readonly COURSE_COLOR: string = 'color';
  static readonly COURSE_COURSE_ID: string = 'course_id';

  static readonly COURSETABLE_TABLE: string = 'CourseTable';
  static readonly COURSETABLE_ID: string = 'id';
  static readonly COURSETABLE_NAME: string = 'name';
  static readonly COURSETABLE_DATA: string = 'data';

  static readonly SQL_CREATE_COURSES: string =
    'CREATE TABLE IF NOT EXISTS ' + LegacySchema.COURSE_TABLE + ' (' +
      LegacySchema.COURSE_ID + ' INTEGER PRIMARY KEY AUTOINCREMENT,' +
      LegacySchema.COURSE_TABLE_ID + ' INTEGER,' +
      LegacySchema.COURSE_NAME + ' TEXT,' +
      LegacySchema.COURSE_CLASSROOM + ' TEXT,' +
      LegacySchema.COURSE_CLASS_NUMBER + ' TEXT,' +
      LegacySchema.COURSE_TEACHER + ' TEXT,' +
      LegacySchema.COURSE_TEST_TIME + ' TEXT,' +
      LegacySchema.COURSE_TEST_LOCATION + ' TEXT,' +
      LegacySchema.COURSE_LINK + ' TEXT,' +
      LegacySchema.COURSE_INFO + ' TEXT,' +
      LegacySchema.COURSE_DATA + ' TEXT,' +
      LegacySchema.COURSE_WEEKS + ' TEXT,' +
      LegacySchema.COURSE_WEEK_TIME + ' INTEGER,' +
      LegacySchema.COURSE_START_TIME + ' INTEGER,' +
      LegacySchema.COURSE_TIME_COUNT + ' INTEGER,' +
      LegacySchema.COURSE_IMPORT_TYPE + ' INTEGER,' +
      LegacySchema.COURSE_COLOR + ' TEXT,' +
      LegacySchema.COURSE_COURSE_ID + ' INTEGER' +
    ')';

  static readonly SQL_CREATE_COURSETABLE: string =
    'CREATE TABLE IF NOT EXISTS ' + LegacySchema.COURSETABLE_TABLE + ' (' +
      LegacySchema.COURSETABLE_ID + ' INTEGER PRIMARY KEY AUTOINCREMENT,' +
      LegacySchema.COURSETABLE_NAME + ' TEXT,' +
      LegacySchema.COURSETABLE_DATA + ' TEXT' +
    ')';

  /** 旧版 v2 → v3 需要补齐的列。 */
  static readonly UPGRADE_V2: SchemaUpgrade[] = [
    { table: LegacySchema.COURSE_TABLE, column: LegacySchema.COURSE_INFO },
    { table: LegacySchema.COURSE_TABLE, column: LegacySchema.COURSE_DATA },
    { table: LegacySchema.COURSETABLE_TABLE, column: LegacySchema.COURSETABLE_DATA }
  ];
}

/**
 * 数据库单例。线程安全（relationalStore 本身线程安全），只在主线程使用。
 */
export class Db {
  private static store: relationalStore.RdbStore | null = null;
  private static opening: Promise<relationalStore.RdbStore> | null = null;

  static async open(): Promise<relationalStore.RdbStore> {
    const ready: relationalStore.RdbStore | null = Db.store;
    if (ready !== null) {
      return ready;
    }
    const pending: Promise<relationalStore.RdbStore> | null = Db.opening;
    if (pending !== null) {
      return pending;
    }
    const opening: Promise<relationalStore.RdbStore> = Db.doOpen();
    Db.opening = opening;
    try {
      const store: relationalStore.RdbStore = await opening;
      Db.store = store;
      return store;
    } finally {
      Db.opening = null;
    }
  }

  private static async doOpen(): Promise<relationalStore.RdbStore> {
    const config: relationalStore.StoreConfig = {
      name: LegacySchema.DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store: relationalStore.RdbStore = await relationalStore.getRdbStore(AppContext.get(), config);
    if (store.version === 0) {
      await Db.createInitialSchema(store);
      return store;
    }
    // 旧版 v2 升级 / 修复历史失败留下的不完整 v3 schema。
    await Db.ensureUpgradeSchema(store);
    return store;
  }

  /** 新库：建表与版本号在同一事务内完成。 */
  private static async createInitialSchema(store: relationalStore.RdbStore): Promise<void> {
    await Db.runInTransaction(store, async (tx: relationalStore.Transaction) => {
      await tx.execute(LegacySchema.SQL_CREATE_COURSETABLE);
      await tx.execute(LegacySchema.SQL_CREATE_COURSES);
    });
    store.version = LegacySchema.DB_VERSION;
  }

  /** 已有库：只补齐缺失列，全部成功后提交事务并写版本号。 */
  private static async ensureUpgradeSchema(store: relationalStore.RdbStore): Promise<void> {
    const missing: SchemaUpgrade[] = [];
    for (let i = 0; i < LegacySchema.UPGRADE_V2.length; i++) {
      const upgrade: SchemaUpgrade = LegacySchema.UPGRADE_V2[i];
      if (!await Db.hasColumn(store, upgrade.table, upgrade.column)) {
        missing.push(upgrade);
      }
    }
    if (missing.length === 0) {
      if (store.version < LegacySchema.DB_VERSION) {
        store.version = LegacySchema.DB_VERSION;
      }
      return;
    }
    await Db.runInTransaction(store, async (tx: relationalStore.Transaction) => {
      for (let i = 0; i < missing.length; i++) {
        await tx.execute(`ALTER TABLE ${missing[i].table} ADD COLUMN ${missing[i].column} TEXT`);
      }
    });
    store.version = LegacySchema.DB_VERSION;
  }

  /** 统一事务边界：成功 commit，失败 rollback 并抛出。 */
  private static async runInTransaction(store: relationalStore.RdbStore,
    work: (tx: relationalStore.Transaction) => Promise<void>): Promise<void> {
    const tx: relationalStore.Transaction = await store.createTransaction();
    try {
      await work(tx);
      await tx.commit();
    } catch (err) {
      await tx.rollback().catch((rollbackErr: Error) => {
        hilog.warn(0x0000, 'Db', 'rollback failed: %{public}s', JSON.stringify(rollbackErr));
      });
      hilog.error(0x0000, 'Db', 'schema transaction failed: %{public}s', JSON.stringify(err));
      throw err as Error;
    }
  }

  private static async hasColumn(store: relationalStore.RdbStore, table: string,
    column: string): Promise<boolean> {
    const resultSet: relationalStore.ResultSet = await store.querySql(`PRAGMA table_info(${table})`);
    try {
      const nameIndex: number = resultSet.getColumnIndex('name');
      while (resultSet.goToNextRow()) {
        if (resultSet.getString(nameIndex) === column) {
          return true;
        }
      }
      return false;
    } finally {
      resultSet.close();
    }
  }

  static async close(): Promise<void> {
    const ready: relationalStore.RdbStore | null = Db.store;
    if (ready !== null) {
      await ready.close();
      Db.store = null;
    }
  }
}
