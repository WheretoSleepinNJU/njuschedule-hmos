/**
 * 分享课表：把当前课表编码成旧版分享码（`ncs://qr/v2/...`）并生成二维码。
 *
 * 编解码格式见 `data/ShareCodec.ets`，与旧 Flutter 项目
 * `lib/Pages/Share/qr_payload_codec.dart` 完全一致，保证跨端可扫。
 */
import {
  HdsNavDestination,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitleBarOptions,
  IconStyleMode
} from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import { generateBarcode, scanBarcode, scanCore } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Colors, FontSize, HdsMetrics, Radius, Spacing } from '../../common/design/Tokens';
import { Feedback } from '../../common/ui/Feedback';
import { AppStore } from '../../app/AppStore';
import { AppState } from '../../app/AppState';
import { hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import { DecodedSharePayload, ShareCodeError, ShareCodec, ShareCodeStats, ShareFrame } from '../../data/ShareCodec';
import { CourseRepository } from '../../data/CourseRepository';
import { CourseTableRepository } from '../../data/CourseTableRepository';
import { ImportCourseCodec } from '../import/ImportPayloadCodec';
import { CourseTable, Course } from '../../data/models/Models';

@ComponentV2
export struct SharePage {
  /** V2 全局 Store（主题色 / 避让区 / 当前课表）。 */
  @Local store: AppStore = AppStore.connect();
  /** 滚动控制器（与 HdsNavDestination 绑定，获得标题栏动态模糊）。 */
  private subScroller: Scroller = new Scroller();


  @Local tableName: string = '';
  @Local courseCount: number = 0;
  @Local code: string = '';
  @Local stats: ShareCodeStats = new ShareCodeStats();
  @Local pixelMap: image.PixelMap | undefined = undefined;
  /** 二维码帧（Scan Kit 单张上限 512 字符，超长分享码需多张）。 */
  @Local qrFrames: string[] = [];
  @Local qrIndex: number = 0;
  @Local busy: boolean = true;
  /** 正在生成下一张二维码，避免快速切换导致旧结果覆盖新帧。 */
  @Local rendering: boolean = false;
  /** 已有二维码时原地重新生成，不隐藏旧图。
   */
  @Local regenerating: boolean = false;
  /** 标题栏四点菜单是否展开。 */
  @Local actionsMenuOpen: boolean = false;
  @Local errorText: string = '';
  /** 是否正在系统扫码界面。 */
  @Local scanning: boolean = false;
  /** 扫码导入的多帧缓存（key = group:index）。 */
  private scannedFrames: Map<string, string> = new Map();

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    // 重新生成时保留现有二维码，仅在新图生成成功后替换，避免整页闪屏。
    const hasExistingQr: boolean = this.pixelMap !== undefined;
    this.busy = !hasExistingQr;
    this.regenerating = hasExistingQr;
    this.errorText = '';
    try {
      const table: CourseTable | null = await CourseTableRepository.getById(this.store.tableId);
      if (table === null) {
        this.errorText = '当前课表不存在';
        return;
      }
      this.tableName = table.name;
      const courses: Course[] = await CourseRepository.getAll(this.store.tableId);
      this.courseCount = courses.length;
      const stats: ShareCodeStats = await ShareCodec.encode(table.name, table.data, courses);
      this.stats = stats;
      this.code = stats.code;
      this.qrFrames = ShareCodec.splitQrFrames(stats.code);
      this.qrIndex = 0;
      await this.renderQr(this.qrFrames.length > 0 ? this.qrFrames[0] : stats.code);
    } catch (err) {
      const message: string = err instanceof Error ? err.message : '未知错误';
      this.errorText = `生成分享码失败：${message}`;
    } finally {
      this.busy = false;
      this.regenerating = false;
    }
  }

  private async createQr(content: string): Promise<image.PixelMap | undefined> {
    const options: generateBarcode.CreateOptions = {
      scanType: scanCore.ScanType.QR_CODE,
      width: 720,
      height: 720
    };
    try {
      return await generateBarcode.createBarcode(content, options);
    } catch (err) {
      // 模拟器不支持 Scan Kit 码图生成，真机可用；分享码本身仍可复制使用。
      const error: BusinessError = err as BusinessError;
      console.warn(`[Share] barcode generation unavailable: ${error.code} ${error.message}`);
      return undefined;
    }
  }

  private async renderQr(content: string): Promise<void> {
    const pixelMap: image.PixelMap | undefined = await this.createQr(content);
    if (pixelMap !== undefined) {
      this.pixelMap = pixelMap;
    }
  }

  /** 切换二维码帧（多帧分享码）；保留旧码图直到新码图生成完成，避免闪烁。 */
  private async gotoFrame(next: boolean): Promise<void> {
    const total: number = this.qrFrames.length;
    if (total <= 1 || this.rendering) {
      return;
    }
    const index: number = (this.qrIndex + (next ? 1 : total - 1)) % total;
    this.qrIndex = index;
    this.rendering = true;
    try {
      const pixelMap: image.PixelMap | undefined = await this.createQr(this.qrFrames[index]);
      if (pixelMap !== undefined && this.qrIndex === index) {
        this.pixelMap = pixelMap;
      }
    } finally {
      this.rendering = false;
    }
  }

  private async copyCode(): Promise<void> {
    if (this.code === '') {
      return;
    }
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.code);
      await pasteboard.getSystemPasteboard().setData(data);
      Feedback.toast(this.getUIContext(), '分享码已复制到剪贴板');
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error(`[Share] copy failed: code=${error.code} message=${error.message}`);
      Feedback.toast(this.getUIContext(), '复制失败');
    }
  }


  /** 分享页标题栏「扫码导入」：调起系统扫码界面并完成导入。 */
  private async startScan(): Promise<void> {
    if (this.scanning) {
      return;
    }
    this.scanning = true;
    try {
      let done: boolean = false;
      while (!done) {
        const context: common.Context = this.getUIContext().getHostContext() as common.Context;
        const options: scanBarcode.ScanOptions = {
          scanTypes: [scanCore.ScanType.QR_CODE],
          enableMultiMode: false
        };
        const result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(context, options);
        done = await this.handleScanValue(result.originalValue);
      }
    } catch (err) {
      // 用户取消扫码：静默返回。
    } finally {
      this.scanning = false;
    }
  }

  /** 返回 true 表示扫码流程结束（成功/非本应用码）；false 表示多帧未集齐，继续扫码。 */
  private async handleScanValue(value: string): Promise<boolean> {
    const text: string = value.trim();
    if (text === '') {
      Feedback.toast(this.getUIContext(), '没有识别到内容，请重试');
      return true;
    }
    const frame: ShareFrame | null = ShareCodec.frameOf(text);
    if (frame === null) {
      Feedback.toast(this.getUIContext(), '这不是呢喃课表的分享码');
      return true;
    }
    if (!frame.isMulti) {
      await this.importScannedCode(text);
      return true;
    }
    this.scannedFrames.set(`${frame.group}:${frame.index}`, text);
    const merged: string | null = ShareCodec.mergeFrames(this.scannedFrames);
    if (merged === null) {
      Feedback.toast(this.getUIContext(),
        `已扫描 ${this.scannedFrames.size}/${frame.total} 帧，请继续扫描`);
      return false;
    }
    this.scannedFrames.clear();
    await this.importScannedCode(merged);
    return true;
  }

  private async importScannedCode(raw: string): Promise<void> {
    try {
      const decoded: DecodedSharePayload = await ShareCodec.decode(raw);
      const table: CourseTable = await CourseTableRepository.insert(
        new CourseTable(decoded.tableName, decoded.tableData));
      const courses: Course[] = ImportCourseCodec.toCourses(decoded.courses, table.id);
      if (courses.length > 0) {
        await CourseRepository.insertMany(courses);
      }
      await AppState.switchTable(table.id);
      Feedback.toast(this.getUIContext(), `已导入「${decoded.tableName}」，共 ${courses.length} 门课程`);
      await this.load();
    } catch (err) {
      const message: string = err instanceof Error ? err.message : '未知错误';
      Feedback.toast(this.getUIContext(), `扫码导入失败：${this.describeError(message)}`);
    }
  }

  private describeError(code: string): string {
    if (code === ShareCodeError.ChecksumMismatch) {
      return '分享码校验失败，可能复制不完整';
    }
    if (code === ShareCodeError.Base64Failed || code === ShareCodeError.GzipFailed) {
      return '分享码内容损坏，请重新复制完整内容';
    }
    if (code === ShareCodeError.UnsupportedVersion) {
      return '分享码版本过新，请升级应用';
    }
    return '分享码解析失败';
  }

  private titleBarOptions(): HdsNavigationTitleBarOptions {
    const menu: HdsNavigationMenuContentOptions = {
      value: [{
        content: {
          icon: $r('sys.symbol.dot_grid_2x2'),
          type: IconStyleMode.NORMAL,
          action: () => {
            this.actionsMenuOpen = !this.actionsMenuOpen;
          }
        }
      }]
    };
    return hdsSubPageTitleBar('分享课表', '二维码 / 分享码与旧版南哪课表互通', menu);
  }

  private actionMenuItems(): MenuElement[] {
    return [
      {
        value: '扫一扫',
        icon: $r('sys.symbol.line_viewfinder'),
        action: () => {
          this.actionsMenuOpen = false;
          this.startScan();
        }
      },
      {
        value: '复制分享码',
        icon: $r('sys.symbol.text_clipboard'),
        enabled: !this.busy && !this.regenerating && this.code !== '',
        action: () => {
          this.actionsMenuOpen = false;
          this.copyCode();
        }
      },
      {
        value: '重新生成',
        icon: $r('sys.symbol.arrow_clockwise'),
        enabled: !this.busy && !this.regenerating,
        action: () => {
          this.actionsMenuOpen = false;
          this.load();
        }
      }
    ];
  }

  @Builder
  private qrCard() {
    Column({ space: Spacing.Md }) {
      // 固定二维码占位，加载/失败/成功都保持同一尺寸，避免切换帧时布局跳动。
      Stack() {
        if (this.busy) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(this.store.accentDisplay)
        } else if (this.pixelMap !== undefined) {
          Image(this.pixelMap)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .onClick(() => {
              this.gotoFrame(true);
            })
        } else {
          Column({ space: Spacing.Sm }) {
            SymbolGlyph($r('sys.symbol.qrcode'))
              .fontSize(48)
              .fontColor([Colors.TextTertiary])
            Text('二维码生成失败')
              .fontSize(FontSize.BodySm)
              .fontColor(Colors.TextTertiary)
            Text('可以复制分享码，发给使用呢喃课表或旧版南哪课表的同学导入')
              .fontSize(FontSize.Caption)
              .fontColor(Colors.TextTertiary)
              .textAlign(TextAlign.Center)
          }
          .padding(Spacing.Md)
          .justifyContent(FlexAlign.Center)
        }
        if (this.regenerating) {
          Row({ space: Spacing.Sm }) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(this.store.accentDisplay)
            Text('重新生成中…')
              .fontSize(FontSize.Caption)
              .fontColor(Colors.TextSecondary)
          }
          .padding({ left: Spacing.Md, right: Spacing.Md, top: Spacing.Sm, bottom: Spacing.Sm })
          .backgroundColor(Colors.SurfaceTranslucent)
          .borderRadius(Radius.Round)
        }
      }
      .width(260)
      .height(260)
      .backgroundColor('#FFFFFF')
      .borderRadius(Radius.Md)
      .clip(true)

      if (this.pixelMap !== undefined && this.qrFrames.length > 1) {
          Row({ space: Spacing.Md }) {
            Button('上一张')
              .height(32)
              .fontSize(FontSize.Caption)
              .backgroundColor(Colors.SurfaceHigh)
              .fontColor(Colors.TextPrimary)
              .enabled(!this.rendering)
              .onClick(() => {
                this.gotoFrame(false);
              })
            Text(`第 ${this.qrIndex + 1} / ${this.qrFrames.length} 张 · 点击二维码可切换`)
              .fontSize(FontSize.Caption)
              .fontColor(Colors.TextSecondary)
            Button('下一张')
              .height(32)
              .fontSize(FontSize.Caption)
              .backgroundColor(Colors.SurfaceHigh)
              .fontColor(Colors.TextPrimary)
              .enabled(!this.rendering)
              .onClick(() => {
                this.gotoFrame(true);
              })
          }
          Text('分享码较长，已拆成多张二维码：请用对方「扫码导入」依次扫描全部二维码，收齐后会自动导入。')
            .fontSize(FontSize.Caption)
            .fontColor(Colors.TextTertiary)
            .textAlign(TextAlign.Center)
            .lineHeight(18)
      }

      Text(this.tableName)
        .fontSize(FontSize.Title)
        .fontWeight(FontWeight.Medium)
        .fontColor(Colors.TextPrimary)
      Text(`${this.courseCount} 门课程 · 分享码 ${this.stats.base64Chars} 字符`)
        .fontSize(FontSize.BodySm)
        .fontColor(Colors.TextTertiary)

      if (this.errorText !== '') {
        Text(this.errorText)
          .fontSize(FontSize.Caption)
          .fontColor(Colors.Error)
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .padding(Spacing.Xl)
    .backgroundColor(Colors.Surface)
    .borderRadius(Radius.Lg)
    .border({ width: 1, color: Colors.OutlineLight })
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Scroll(this.subScroller) {
          Column({ space: Spacing.Lg }) {
            this.qrCard()
          }
          .width('100%')
          .padding({
            left: Spacing.Lg,
            right: Spacing.Lg,
            top: HdsMetrics.contentTopInset(px2vp(this.store.windowTopInset)) + Spacing.Md,
            bottom: Spacing.Xxl
          })
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .align(Alignment.TopStart)
        .width('100%')
        .height('100%')

        // 标题栏四点菜单的锚点：透明零尺寸，菜单从右上角展开。
        Stack() {
        }
        .width(1)
        .height(1)
        .position({
          x: Math.max(0, this.getUIContext().px2vp(this.store.windowWidth) - 32),
          y: HdsMetrics.contentTopInset(px2vp(this.store.windowTopInset)) - 4
        })
        .bindMenu(this.actionsMenuOpen, this.actionMenuItems(), {
          placement: Placement.BottomRight,
          onDisappear: () => {
            this.actionsMenuOpen = false;
          }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.Background)
    }
    .titleBar(this.titleBarOptions())
    .bindToScrollable([this.subScroller])
  }
}
