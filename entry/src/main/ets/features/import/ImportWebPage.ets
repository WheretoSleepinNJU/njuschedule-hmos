/**
 * 教务导入 WebView 页（路由名 `import-web`，参数 `ImportWebParam { config }`）。
 *
 * 流程 1:1 对齐旧版 `lib/Pages/Import/ImportFromBEView.dart`：
 *   加载 initialUrl → onPageEnd 判定 redirectUrl（命中则 loadUrl targetUrl）
 *   → 命中 targetUrl → preExtractJS → 等待 delayTime 秒 → 注入解析脚本
 *   → 读取 `encodeURIComponent(JSON.stringify({name, courses}))` 返回值
 *   → 解码 → 建课表 → 批量写课程 → 按学期开始时间设置当前周 → 切换当前课表 → 提示并返回。
 *
 * 与旧版的差异（均为可用性/安全改进，不改变协议）：
 * - 解析脚本与上游保持一致，优先从 CDN 下载；网络失败时回退到随包 rawfile
 *   （`import/tools/<extractJSfileOHOS 文件名>`），离线仍可完成导入。
 * - 解码只 `decodeURIComponent`，不照搬旧版 `replaceAll('"', '')`。
 * - 失败不再把整页 HTML 上传到后端（旧版行为涉及隐私），只在页面内显示可读错误。
 * - URL 判定在 startsWith 之外兼容 targetUrl 里的 `*` 通配符与尾斜杠差异。
 *
 * 根节点是 `HdsNavDestination`：标题栏统一走 common/ui/HdsSubPage 的系统标题栏
 * （`hdsSubPageTitleBar`：动态模糊 + 光感材质 + 系统返回键），不再自绘工具条。
 * 标题 = 学校配置的 `page_title`（缺省「教务导入」），副标题 = 实时状态文字，
 * 标题栏右侧菜单放「刷新」；页面内容（错误条 / 配置提示 / Web）从标题栏下方开始。
 *
 * 本页没有 ArkUI 滚动容器可绑定给 `bindToScrollable`（Web 组件内部滚动不暴露 Scroller），
 * 因此不调用该接口，标题栏保持「静止透明」样式，与其它子页的静止状态一致。
 */
import { resolveNavStack } from '../../common/NavStackResolver';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { pasteboard } from '@kit.BasicServicesKit';
import { HdsNavDestination, HdsNavigationMenuContentOptions, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit';
import { AppContext } from '../../app/AppContext';
import { CdnTextFetcher } from '../../common/CdnTextFetcher';
import { AppPreferences } from '../../app/AppPreferences';
import { AppState } from '../../app/AppState';
import { Colors, FontSize, HdsMetrics, Radius, Spacing } from '../../common/design/Tokens';
import { Feedback } from '../../common/ui/Feedback';
import { hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import { AppStore } from '../../app/AppStore';
import { EmptyState } from '../../common/ui/EmptyState';
import { CourseRepository } from '../../data/CourseRepository';
import { CourseTableRepository } from '../../data/CourseTableRepository';
import { Course, CourseTable } from '../../data/models/Models';
import {
  ImportCourseCodec,
  ImportPayload,
  ImportPayloadDecoder
} from './ImportPayloadCodec';
import { ImportWeekApplier } from './ImportWeekApplier';
import { ImportWebParam } from './ImportParams';
import { SchoolConfig } from './SchoolConfig';

const SCRIPT_TIMEOUT_MS: number = 60000;
const LEGACY_UA: string = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

@ComponentV2
export struct ImportWebPage {
  /** V2 全局 Store（主题色 / 避让区 / 当前课表）。 */
  @Local store: AppStore = AppStore.connect();

  /** 外壳注入的导航栈；正常也走 onReady 里的 pathStack。 */
  @Param pageStack: NavPathStack = new NavPathStack();

  @Local private configReady: boolean = false;
  @Local private title: string = '教务导入';
  @Local private statusText: string = '正在加载页面…';
  @Local private errorText: string = '';
  @Local private importing: boolean = false;

  private config: SchoolConfig = new SchoolConfig();
  private controller: webview.WebviewController = new webview.WebviewController();
  private stack: NavPathStack | null = null;

  /** 同一次页面会话只自动触发一次导入 / 一次 redirect 跳转。 */
  private importStarted: boolean = false;
  private redirectStarted: boolean = false;
  /** 成功导入后不再响应页面事件。 */
  private finished: boolean = false;
  private disposed: boolean = false;
  /** 当前错误是否来自导入流程（网络错误会在下次页面加载完成时自动清除）。 */
  private errorFromImport: boolean = false;

  aboutToDisappear(): void {
    this.disposed = true;
  }

  private navStack(): NavPathStack {
    return resolveNavStack(this.stack, this.pageStack);
  }


  /** 复制诊断信息（URL/错误/学校/时间）；不包含账号与页面内容，便于反馈问题。 */
  private copyDiagnostics(): void {
    let url: string = '';
    try {
      url = this.controller.getUrl();
    } catch (err) {
      url = '';
    }
    const lines: string[] = [
      '呢喃课表 导入诊断',
      `时间：${new Date().toISOString()}`,
      `学校：${this.config.title}`,
      `目标页：${this.config.targetUrl}`,
      `当前页：${url}`,
      `错误：${this.errorText}`
    ];
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, lines.join('\n'));
      pasteboard.getSystemPasteboard().setDataSync(data);
      Feedback.toast(this.getUIContext(), '诊断信息已复制');
    } catch (err) {
      console.warn(`[ImportWeb] copy diagnostics failed: ${JSON.stringify(err)}`);
      Feedback.toast(this.getUIContext(), '复制失败');
    }
  }

  // ---- 参数与页面状态 ----

  private initFromParam(ctx: NavDestinationContext): void {
    this.stack = ctx.pathStack;
    const raw: Object | undefined = ctx.pathInfo.param as Object;
    if (!(raw instanceof ImportWebParam)) {
      this.failLoad('缺少学校配置，请返回重新选择学校');
      return;
    }
    this.config = raw.config;
    this.title = this.config.pageTitle !== '' ? this.config.pageTitle : '教务导入';
    if (this.config.initialUrl === '') {
      this.failLoad('该学校配置缺少 initialUrl，无法打开登录页');
      return;
    }
    this.configReady = true;
    this.statusText = '正在加载页面…';
  }

  private failLoad(message: string): void {
    this.errorFromImport = false;
    this.errorText = message;
    this.statusText = '页面加载失败';
  }

  private failImport(message: string): void {
    this.errorFromImport = true;
    this.errorText = message;
    this.statusText = '导入失败，可重试';
  }

  // ---- Web 事件 ----

  private onControllerAttached(): void {
    try {
      // 旧版对所有平台使用固定 Android Chrome UA，避免教务系统拒绝移动端 UA。
      this.controller.setCustomUserAgent(LEGACY_UA);
    } catch (err) {
      console.warn(`[ImportWeb] 设置 UA 失败: ${errorMessage(err)}`);
    }
  }

  private onPageBegin(): void {
    if (this.finished || this.importing) {
      return;
    }
    this.statusText = '正在加载页面…';
  }

  private async onPageEnd(url: string): Promise<void> {
    if (this.finished || this.disposed || !this.configReady) {
      return;
    }
    try {
      if (!this.importing && !this.errorFromImport) {
        this.errorText = '';
      }
      const cfg: SchoolConfig = this.config;

      if (cfg.redirectUrl !== '' && !this.redirectStarted && this.matchesUrl(url, cfg.redirectUrl)) {
        this.redirectStarted = true;
        this.statusText = '登录成功，正在打开课表页面…';
        try {
          this.controller.loadUrl(cfg.targetUrl);
        } catch (err) {
          this.failLoad(`打开课表页面失败：${errorMessage(err)}`);
        }
        return;
      }

      if (this.matchesUrl(url, cfg.targetUrl)) {
        if (!this.importStarted) {
          this.importStarted = true;
          await this.runImport();
        }
        return;
      }

      this.statusText = '请在页面中完成登录，进入课表页后将自动导入';
    } catch (err) {
      this.failImport(errorMessage(err));
    }
  }

  private onErrorReceive(event: OnErrorReceiveEvent): void {
    if (!event.request.isMainFrame() || this.finished) {
      return;
    }
    const code: number = event.error.getErrorCode();
    // -3 = ERR_ABORTED：导航被新的 loadUrl 打断（redirect 场景）属正常，不提示。
    if (code === -3) {
      return;
    }
    const info: string = event.error.getErrorInfo();
    this.failLoad(`网络错误（${code}）${info}。请检查网络或 VPN 后刷新重试`);
  }

  private onHttpErrorReceive(event: OnHttpErrorReceiveEvent): void {
    if (!event.request.isMainFrame() || this.finished) {
      return;
    }
    const code: number = event.response.getResponseCode();
    if (code >= 400) {
      this.statusText = `页面返回 HTTP ${code}，可刷新重试`;
    }
  }

  // ---- 刷新 / 重试 ----

  private refresh(): void {
    if (this.importing || this.config.initialUrl === '') {
      return;
    }
    this.importStarted = false;
    this.redirectStarted = false;
    this.errorText = '';
    this.errorFromImport = false;
    this.statusText = '正在重新加载…';
    try {
      // 旧版刷新会先清 Cookie 再加载 initialUrl，避免残留登录态卡在错误页。
      webview.WebCookieManager.clearAllCookiesSync();
    } catch (err) {
      console.warn(`[ImportWeb] 清除 Cookie 失败: ${errorMessage(err)}`);
    }
    try {
      this.controller.loadUrl(this.config.initialUrl);
    } catch (err) {
      this.failLoad(`重新加载失败：${errorMessage(err)}`);
    }
  }

  private retryImport(): void {
    if (this.importing || this.finished) {
      return;
    }
    this.importStarted = true;
    this.errorText = '';
    this.errorFromImport = false;
    this.runImport();
  }

  private openBannerUrl(): void {
    const url: string = this.config.bannerUrl.trim();
    if (url === '') {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.openLink(url).catch((err: Error) => {
        console.warn(`[ImportWeb] 打开链接失败: ${err.message}`);
        Feedback.toast(this.getUIContext(), '无法打开链接');
      });
    } catch (err) {
      Feedback.toast(this.getUIContext(), '无法打开链接');
    }
  }

  // ---- 导入流程 ----

  /** 当前页面是否命中某个 URL 前缀（兼容 `*` 通配符与尾斜杠差异）。 */
  private matchesUrl(url: string, pattern: string): boolean {
    const target: string = pattern.trim();
    const current: string = url.trim();
    if (target === '' || current === '') {
      return false;
    }
    if (this.matchPrefix(current, target)) {
      return true;
    }
    const trimmed: string = this.trimTrailingSlash(target);
    return trimmed !== target && this.matchPrefix(current, trimmed);
  }

  private matchPrefix(current: string, prefix: string): boolean {
    if (prefix.indexOf('*') < 0) {
      return current.startsWith(prefix);
    }
    // targetUrl 里含字面量 `*default`（ehall 路径），按通配符逐段匹配。
    const segments: string[] = prefix.split('*');
    let position: number = 0;
    for (let i = 0; i < segments.length; i++) {
      const segment: string = segments[i];
      if (segment === '') {
        continue;
      }
      const found: number = current.indexOf(segment, position);
      if (found < 0) {
        return false;
      }
      if (i === 0 && found !== 0) {
        return false;
      }
      position = found + segment.length;
    }
    return true;
  }

  private trimTrailingSlash(text: string): string {
    if (text.endsWith('/')) {
      return text.substring(0, text.length - 1);
    }
    return text;
  }

  private async runImport(): Promise<void> {
    if (this.importing || this.finished) {
      return;
    }
    this.importing = true;
    this.errorText = '';
    this.errorFromImport = false;
    this.statusText = '正在解析课表…';
    const cfg: SchoolConfig = this.config;
    let createdTableId: number = 0;
    try {
      // 1) 页面侧预处理（关弹窗 / 切 tab）；失败不致命，继续提取。
      if (cfg.preExtractJS.trim() !== '') {
        try {
          await this.runScript(cfg.preExtractJS);
        } catch (err) {
          console.warn(`[ImportWeb] preExtractJS 执行失败（继续）: ${errorMessage(err)}`);
        }
      }

      // 2) 固定等待，SPA 页面在 onPageEnd 之后才渲染出课表。
      const delayMs: number = cfg.delayTime > 0 ? cfg.delayTime * 1000 : 0;
      if (delayMs > 0) {
        this.statusText = `等待页面渲染（${cfg.delayTime} 秒）…`;
        await this.delay(delayMs);
      }

      // 3) 取解析脚本：优先 rawfile 内置，其次配置里的内联 extractJS。
      this.statusText = '正在准备解析脚本…';
      const script: string = await this.resolveExtractScript();

      // 4) 注入并拿返回值（encodeURIComponent 后的 JSON 文本）。
      const raw: string = await this.runScript(script);
      if (this.disposed) {
        return;
      }
      // runJavaScript 在脚本无返回值时可能给出 null（文档只承诺 string 类型）。
      if (raw === null || raw === undefined || raw.trim() === '') {
        throw new Error('解析脚本没有返回值，页面可能还没进入课表页');
      }

      // 5) 解码 payload（课程可能是数组 / JSON 字符串 / 二次序列化字符串）。
      const payload: ImportPayload = ImportPayloadDecoder.decode(raw, this.fallbackTableName());
      if (payload.courses.length === 0) {
        throw new Error('没有解析到课程：请确认页面已显示课表后重试');
      }

      // 6) 建表（data 只在配置提供 class_time_list / semester_start_monday 时写入）。
      this.statusText = '正在写入课表…';
      const tableData: string = ImportCourseCodec.buildTableData(
        cfg.classTimeListJson, cfg.semesterStartMonday);
      const table: CourseTable = await CourseTableRepository.insert(new CourseTable(payload.name, tableData));
      createdTableId = table.id;
      const courses: Course[] = ImportCourseCodec.toCourses(payload.courses, createdTableId);
      if (courses.length === 0) {
        throw new Error('课程字段为空，未写入任何课程');
      }
      await CourseRepository.insertMany(courses);

      // 7) 按学期开始时间设置当前周（无数据时走远端 complete.json 兜底）。
      this.statusText = '正在识别学期周次…';
      await ImportWeekApplier.apply(tableData);

      // 8) 切到新表并通知课表页重载（包含一次小组件推送）。
      await AppState.switchTable(createdTableId);

      this.importing = false;
      this.finished = true;
      Feedback.toast(this.getUIContext(), `导入成功：${courses.length} 门课程`);
      this.navStack().pop();
    } catch (err) {
      // 建表后失败：清掉半成品，避免留下一张空表（成功路径已置 finished，不会回滚）。
      if (!this.finished && createdTableId > 0) {
        try {
          await CourseTableRepository.delete(createdTableId);
        } catch (cleanupErr) {
          console.error(`[ImportWeb] 回滚空课表失败: ${errorMessage(cleanupErr)}`);
        }
      }
      if (this.disposed || this.finished) {
        return;
      }
      this.importing = false;
      this.importStarted = false;
      this.failImport(errorMessage(err));
    }
  }

  private async resolveExtractScript(): Promise<string> {
    const cfg: SchoolConfig = this.config;
    // 与上游一致，优先使用远端解析脚本，保证远端学校配置更新后无需发版；
    // 网络失败时再回退到随包 rawfile，最后才使用配置内联脚本。
    if (cfg.extractJsFileOHOS.trim() !== '') {
      try {
        const remote: string = await CdnTextFetcher.fetch(cfg.extractJsFileOHOS, 10000, 15000);
        if (remote.trim() !== '') {
          return remote;
        }
      } catch (err) {
        console.warn(`[ImportWeb] remote script failed: ${errorMessage(err)}`);
      }
    }
    if (cfg.toolFileName !== '') {
      const path: string = `import/tools/${cfg.toolFileName}`;
      try {
        const bytes: Uint8Array = await AppContext.get().resourceManager.getRawFileContent(path);
        const js: string = util.TextDecoder.create('utf-8').decodeToString(bytes);
        if (js.trim() !== '') {
          return js;
        }
      } catch (err) {
        console.warn(`[ImportWeb] bundled script unavailable: ${errorMessage(err)}`);
      }
    }
    if (cfg.extractJS.trim() !== '') {
      return cfg.extractJS;
    }
    throw new Error('解析脚本不可用：远端下载和内置脚本均失败');
  }

  private runScript(script: string): Promise<string> {
    const work: Promise<string> = this.controller.runJavaScript(script);
    const timeout: Promise<string> = new Promise<string>(
      (resolve: (value: string) => void, reject: (reason: Error) => void) => {
        setTimeout(() => {
          reject(new Error('脚本执行超时，页面可能无响应'));
        }, SCRIPT_TIMEOUT_MS);
      });
    return Promise.race([work, timeout]);
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  private fallbackTableName(): string {
    if (this.config.title !== '') {
      return this.config.title;
    }
    return '导入课表';
  }

  // ---- UI ----

  /** 系统标题栏配置：标题 + 实时状态副标题 + 「刷新」菜单（返回键由 HDS 提供）。 */
  private titleBarOptions(): HdsNavigationTitleBarOptions {
    const menu: HdsNavigationMenuContentOptions = {
      value: [{
        content: {
          icon: $r('sys.symbol.arrow_clockwise'),
          label: '刷新',
          action: () => {
            this.refresh();
          }
        }
      }]
    };
    return hdsSubPageTitleBar(this.title, this.statusText, menu);
  }

  @Builder
  private errorBanner() {
    Column({ space: Spacing.Sm }) {
      Row({ space: Spacing.Xs }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(16)
          .fontColor([Colors.Error])
        Text(this.errorFromImport ? '导入失败' : '页面加载失败')
          .fontSize(FontSize.BodySm)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.Error)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.errorText)
        .fontSize(FontSize.Caption)
        .fontColor(Colors.Error)
        .width('100%')

      Row({ space: Spacing.Lg }) {
        if (this.errorFromImport) {
          Text('重试导入')
            .fontSize(FontSize.BodySm)
            .fontColor(this.store.accentDisplay)
            .padding({ top: Spacing.Xs, bottom: Spacing.Xs })
            .onClick(() => {
              this.retryImport();
            })
        }
        Text('刷新页面')
          .fontSize(FontSize.BodySm)
          .fontColor(Colors.TextSecondary)
          .padding({ top: Spacing.Xs, bottom: Spacing.Xs })
          .onClick(() => {
            this.refresh();
          })
        Text('复制诊断信息')
          .fontSize(FontSize.BodySm)
          .fontColor(Colors.TextSecondary)
          .padding({ top: Spacing.Xs, bottom: Spacing.Xs })
          .onClick(() => {
            this.copyDiagnostics();
          })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Spacing.Md)
    .backgroundColor(Colors.ErrorLight)
    .borderRadius(Radius.Md)
    .margin({ left: Spacing.Lg, right: Spacing.Lg, bottom: Spacing.Sm })
  }

  @Builder
  private configBanner() {
    Column({ space: Spacing.Xs }) {
      Text(this.config.bannerContent)
        .fontSize(FontSize.Caption)
        .fontColor(Colors.TextSecondary)
        .width('100%')
      if (this.config.bannerAction !== '') {
        Text(this.config.bannerAction)
          .fontSize(FontSize.BodySm)
          .fontColor(this.store.accentDisplay)
          .padding({ top: Spacing.Xs, bottom: Spacing.Xs })
          .onClick(() => {
            this.openBannerUrl();
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Spacing.Md)
    .backgroundColor(Colors.WarningLight)
    .borderRadius(Radius.Md)
    .margin({ left: Spacing.Lg, right: Spacing.Lg, bottom: Spacing.Sm })
  }

  @Builder
  private webBody() {
    Web({ src: this.config.initialUrl, controller: this.controller })
      .width('100%')
      .layoutWeight(1)
      // 深色模式：教务系统页面自身大多未适配深色，交给系统 Web 引擎的自动算法处理
      // （WebDarkMode.On 启用深色 + forceDarkAccess 对未声明 color-scheme 的页面做 Chromium 标准反色转换）。
      .darkMode(this.store.isDark ? WebDarkMode.On : WebDarkMode.Off)
      .forceDarkAccess(true)
      .backgroundColor(Colors.Background)
      .javaScriptAccess(true)
      .domStorageAccess(true)
      // 安全规范：不允许 MixedMode.All；默认 None。若某校教务必须加载 HTTP 子资源，按域名单列评估后记录。
      .mixedMode(MixedMode.None)
      .onControllerAttached(() => {
        this.onControllerAttached();
      })
      .onPageBegin((event: OnPageBeginEvent) => {
        this.onPageBegin();
      })
      .onPageEnd((event: OnPageEndEvent) => {
        this.onPageEnd(event.url);
      })
      .onErrorReceive((event: OnErrorReceiveEvent) => {
        this.onErrorReceive(event);
      })
      .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
        this.onHttpErrorReceive(event);
      })
  }

  build() {
    HdsNavDestination() {
      Column() {
        if (this.configReady && this.errorText !== '') {
          this.errorBanner()
        }

        if (this.configReady) {
          if (this.config.bannerContent !== '') {
            this.configBanner()
          }
          this.webBody()
        } else if (this.errorText !== '') {
          Column() {
            EmptyState({
              title: '无法打开导入页',
              description: this.errorText,
              icon: $r('sys.symbol.exclamationmark_circle'),
              actionText: '返回',
              onAction: () => {
                this.navStack().pop();
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Column({ space: Spacing.Sm }) {
            LoadingProgress()
              .width(30)
              .height(30)
              .color(this.store.accentDisplay)
            Text('正在准备导入页面…')
              .fontSize(FontSize.BodySm)
              .fontColor(Colors.TextTertiary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
      // HdsNavDestination 的标题栏覆盖在内容上：内容区顶部让出「状态栏 + 标题栏」高度，
      // 让 Web 页从系统标题栏下方开始（Web 内部滚动无法参与标题栏模糊联动）。
      .padding({ top: HdsMetrics.contentTopInset(px2vp(this.store.windowTopInset)) })
      .backgroundColor(Colors.Background)
    }
    .titleBar(this.titleBarOptions())
    .onReady((ctx: NavDestinationContext) => {
      this.initFromParam(ctx);
    })
  }
}

function errorMessage(err: Object): string {
  if (err instanceof Error) {
    return err.message;
  }
  return err.toString();
}
