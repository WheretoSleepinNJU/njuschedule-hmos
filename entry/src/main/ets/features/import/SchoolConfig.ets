/**
 * 在线学校列表配置 DTO。
 *
 * 数据来源：旧版 `~/Projects/njuschedule/api/schoolList.json`（本仓库原样搬运到
 * `entry/src/main/resources/rawfile/import/schoolList.json`）。字段语义见
 * 旧版导入规格（仓库外归档）§3。
 *
 * 说明：
 * - 旧版字段是 snake_case，且含 `isGrey3.1.0` 这种不是合法 ArkTS 标识符的键；
 *   因此在 JSON 边界统一用 `Record<string, Object>` 读取，再收敛到强类型字段。
 * - `class_time_list` 原样保留为 JSON 文本（写 `CourseTable.data` 时直接拼接，
 *   保证与旧版数据格式逐字节兼容）。
 * - 本文件只做「配置 → DTO」，不读文件（读取在 `SchoolRepository`）。
 */

/** 列表接口实际使用的配置子集（其余字段保留但旧版未使用）。 */
export class SchoolConfig {
  title: string = '';
  pinyin: string = '';
  description: string = '';

  /** Web 页标题（旧版 `page_title`）。 */
  pageTitle: string = '';
  initialUrl: string = '';
  /** 登录成功落地页前缀；空串表示不启用该分支。 */
  redirectUrl: string = '';
  /** 课表页前缀；命中后触发导入。 */
  targetUrl: string = '';

  preExtractJS: string = '';
  /** 固定等待秒数（旧版全部为 3）。 */
  delayTime: number = 0;
  /** 内联提取脚本；学校列表里全为空串。 */
  extractJS: string = '';

  extractJsFileOHOS: string = '';
  extractJsFileAndroid: string = '';
  extractJsFileIOS: string = '';

  bannerContent: string = '';
  bannerAction: string = '';
  bannerUrl: string = '';

  /** `class_time_list` 的原始 JSON 文本；空串表示配置未提供。 */
  classTimeListJson: string = '';
  semesterStartMonday: string = '';

  /** 旧字段，当前代码不读取（历史版本置灰开关）。 */
  isGrey: boolean = false;
  /** `isGrey3.1.0`：true 表示当前版本置灰不可点。 */
  disabled: boolean = false;
  /** `pinyin[0].toUpperCase()`；旧版用它做分组索引。 */
  tagIndex: string = '#';
  /** `extractJsFileOHOS` 的文件名（rawfile 内置脚本按这个名字找）。 */
  toolFileName: string = '';

  /** 是否可点击进入（配置完整且未置灰）。 */
  isUsable(): boolean {
    return !this.disabled && this.initialUrl !== '';
  }

  /** 从 schoolList.json 的一个条目构造 DTO。 */
  static fromJson(raw: Record<string, Object>): SchoolConfig {
    const config: SchoolConfig = new SchoolConfig();
    config.title = readText(raw, 'title');
    config.pinyin = readText(raw, 'pinyin');
    config.description = readText(raw, 'description');
    config.pageTitle = readText(raw, 'page_title');
    config.initialUrl = readText(raw, 'initialUrl');
    config.redirectUrl = readText(raw, 'redirectUrl');
    config.targetUrl = readText(raw, 'targetUrl');
    config.preExtractJS = readText(raw, 'preExtractJS');
    config.delayTime = readInt(raw, 'delayTime', 0);
    config.extractJS = readText(raw, 'extractJS');
    config.extractJsFileOHOS = readText(raw, 'extractJSfileOHOS');
    config.extractJsFileAndroid = readText(raw, 'extractJSfileAndroid');
    config.extractJsFileIOS = readText(raw, 'extractJSfileiOS');
    config.bannerContent = readText(raw, 'banner_content');
    config.bannerAction = readText(raw, 'banner_action');
    config.bannerUrl = readText(raw, 'banner_url');
    config.semesterStartMonday = readText(raw, 'semester_start_monday');
    config.isGrey = readBool(raw, 'isGrey', false);
    config.disabled = readBool(raw, 'isGrey3.1.0', false);
    config.tagIndex = config.pinyin.length > 0 ? config.pinyin.substring(0, 1).toUpperCase() : '#';
    config.toolFileName = SchoolConfig.fileNameFromUrl(config.extractJsFileOHOS);

    // class_time_list 结构是 [{start,end}]，不展开，只保存原始 JSON 文本。
    const classTimeRaw: Object | undefined = raw['class_time_list'];
    if (classTimeRaw !== undefined && classTimeRaw !== null) {
      try {
        config.classTimeListJson = JSON.stringify(classTimeRaw);
      } catch (err) {
        config.classTimeListJson = '';
      }
    }
    return config;
  }

  /** 取 URL 的文件名部分（去 query / hash），用于 rawfile 内置脚本路径。 */
  static fileNameFromUrl(url: string): string {
    let text: string = url.trim();
    if (text === '') {
      return '';
    }
    const queryIndex: number = text.indexOf('?');
    if (queryIndex >= 0) {
      text = text.substring(0, queryIndex);
    }
    const hashIndex: number = text.indexOf('#');
    if (hashIndex >= 0) {
      text = text.substring(0, hashIndex);
    }
    const slashIndex: number = text.lastIndexOf('/');
    if (slashIndex >= 0) {
      text = text.substring(slashIndex + 1);
    }
    return text;
  }
}

function readText(raw: Record<string, Object>, key: string): string {
  const value: Object | undefined = raw[key];
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

function readBool(raw: Record<string, Object>, key: string, fallback: boolean): boolean {
  const value: Object | undefined = raw[key];
  if (typeof value === 'boolean') {
    return value as boolean;
  }
  return fallback;
}

function readInt(raw: Record<string, Object>, key: string, fallback: number): number {
  const value: Object | undefined = raw[key];
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
