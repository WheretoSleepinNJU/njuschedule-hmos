/**
 * 学校列表仓储：优先从上游 CDN 拉取 `schoolList.json`，失败时回退到随包 rawfile。
 *
 * - 与上游保持一致：远端新增/调整学校时不需要发版；
 * - 内置 rawfile 作为离线兜底，避免 CDN 不可用时导入页空白；
 * - 排序、搜索逻辑不变。
 */
import { util } from '@kit.ArkTS';
import { AppContext } from '../../app/AppContext';
import { CdnTextFetcher } from '../../common/CdnTextFetcher';
import { LegacyUrl } from '../../common/Constants';
import { SchoolConfig } from './SchoolConfig';

const SCHOOL_LIST_PATH: string = 'import/schoolList.json';
const REMOTE_SCHOOL_LIST_URL: string = `${LegacyUrl.UPDATE_ROOT}/schoolList.json`;

export class SchoolRepository {
  private static cache: SchoolConfig[] = [];
  private static cacheValid: boolean = false;

  /**
   * 读取并解析内置学校列表（带进程内缓存）。
   * @param forceReload 为 true 时忽略缓存重新读取
   */
  static async loadAll(forceReload: boolean = false): Promise<SchoolConfig[]> {
    if (SchoolRepository.cacheValid && !forceReload) {
      return SchoolRepository.cache.slice();
    }

    let list: SchoolConfig[] | null = null;
    try {
      const remote: string = await SchoolRepository.fetchRemote();
      list = SchoolRepository.parse(remote);
    } catch (err) {
      console.warn(`[SchoolRepository] remote list failed, fallback to rawfile: ${errorMessage(err)}`);
    }
    if (list === null || list.length === 0) {
      list = await SchoolRepository.loadBundled();
    }
    SchoolRepository.cache = list;
    SchoolRepository.cacheValid = true;
    return list.slice();
  }

  private static async loadBundled(): Promise<SchoolConfig[]> {
    let text: string = '';
    try {
      const context = AppContext.get();
      const bytes: Uint8Array = await context.resourceManager.getRawFileContent(SCHOOL_LIST_PATH);
      text = util.TextDecoder.create('utf-8').decodeToString(bytes);
    } catch (err) {
      throw new Error(`读取内置学校列表失败：${errorMessage(err)}`);
    }
    return SchoolRepository.parse(text);
  }

  private static async fetchRemote(): Promise<string> {
    return CdnTextFetcher.fetch(REMOTE_SCHOOL_LIST_URL, 10000, 15000);
  }

  /** 按 pinyin 升序排序后的新数组（不修改入参）。 */
  static sortedByPinyin(list: SchoolConfig[]): SchoolConfig[] {
    const copy: SchoolConfig[] = list.slice();
    copy.sort((a: SchoolConfig, b: SchoolConfig): number => {
      if (a.pinyin === b.pinyin) {
        return 0;
      }
      return a.pinyin < b.pinyin ? -1 : 1;
    });
    return copy;
  }

  /** 关键字过滤：空关键字返回原数组；匹配 title / pinyin / description / tagIndex。 */
  static search(list: SchoolConfig[], keyword: string): SchoolConfig[] {
    const query: string = keyword.trim().toLowerCase();
    if (query === '') {
      return list;
    }
    const matched: SchoolConfig[] = [];
    for (let i = 0; i < list.length; i++) {
      const school: SchoolConfig = list[i];
      if (school.title.toLowerCase().indexOf(query) >= 0 ||
        school.pinyin.toLowerCase().indexOf(query) >= 0 ||
        school.description.toLowerCase().indexOf(query) >= 0 ||
        school.tagIndex.toLowerCase().indexOf(query) >= 0) {
        matched.push(school);
      }
    }
    return matched;
  }

  private static parse(text: string): SchoolConfig[] {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(text) as Record<string, Object>;
    } catch (err) {
      throw new Error('学校列表格式错误（JSON 解析失败）');
    }
    if (parsed === null) {
      throw new Error('学校列表为空');
    }
    const data: Object | undefined = parsed['data'];
    if (!Array.isArray(data)) {
      throw new Error('学校列表缺少 data 数组');
    }
    const items: Object[] = data as Object[];
    const list: SchoolConfig[] = [];
    for (let i = 0; i < items.length; i++) {
      const item: Object = items[i];
      if (item === null || typeof item !== 'object' || Array.isArray(item)) {
        continue;
      }
      list.push(SchoolConfig.fromJson(item as Record<string, Object>));
    }
    if (list.length === 0) {
      throw new Error('学校列表为空');
    }
    return list;
  }
}

function errorMessage(err: Object): string {
  if (err instanceof Error) {
    return err.message;
  }
  return err.toString();
}
