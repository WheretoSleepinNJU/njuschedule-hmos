/**
 * 学期开始时间解析。
 *
 * 优先级与上游一致：
 * 1. 课表 data 里的 semester_start_monday（导入配置已提供）；
 * 2. 主应用没有该字段时，读取上游 production complete.json。
 *
 * 远端只用于读取学期开始时间，失败不阻塞导入。
 */
import { LegacyUrl } from '../../common/Constants';
import { CdnTextFetcher } from '../../common/CdnTextFetcher';
import { DateUtils } from '../../common/DateUtils';

const COMPLETE_URL: string = `${LegacyUrl.UPDATE_ROOT}/complete.json`;
const REMOTE_TIMEOUT_MS: number = 5000;

export class SemesterStartResolver {
  private static remoteCache: string = '';

  /** 从课表 data JSON 中提取 semester_start_monday。 */
  static fromTableData(tableData: string): string {
    if (tableData.trim() === '') {
      return '';
    }
    try {
      const parsed: Record<string, Object> = JSON.parse(tableData) as Record<string, Object>;
      const value: Object | undefined = parsed['semester_start_monday'];
      const text: string = value === undefined || value === null ? '' : `${value}`.trim();
      return SemesterStartResolver.isValidMonday(text) ? text : '';
    } catch (err) {
      return '';
    }
  }

  /** 本地优先；缺失时请求上游 complete.json。 */
  static async resolve(tableData: string): Promise<string> {
    const local: string = SemesterStartResolver.fromTableData(tableData);
    if (local !== '') {
      return local;
    }
    if (SemesterStartResolver.remoteCache !== '') {
      return SemesterStartResolver.remoteCache;
    }
    const remote: string = await SemesterStartResolver.fetchRemote();
    if (remote !== '') {
      SemesterStartResolver.remoteCache = remote;
    }
    return remote;
  }

  /** 校验 YYYY-MM-DD 且必须是周一，避免用非法日期重置当前周。 */
  static isValidMonday(text: string): boolean {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) {
      return false;
    }
    const date: Date = DateUtils.parseIsoDate(text);
    if (isNaN(date.getTime())) {
      return false;
    }
    // parseIsoDate 对非法日期会回落到今天，这里再做一次格式/星期校验。
    const normalized: string = DateUtils.formatIsoDate(date);
    return normalized === text && date.getDay() === 1;
  }

  private static async fetchRemote(): Promise<string> {
    try {
      const raw: string = await CdnTextFetcher.fetch(COMPLETE_URL, REMOTE_TIMEOUT_MS, REMOTE_TIMEOUT_MS);
      const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      const value: Object | undefined = parsed['semester_start_monday'];
      const text: string = value === undefined || value === null ? '' : `${value}`.trim();
      return SemesterStartResolver.isValidMonday(text) ? text : '';
    } catch (err) {
      console.warn(`[SemesterStart] fetch failed: ${JSON.stringify(err)}`);
      return '';
    }
  }
}
