/**
 * 从分享码导入课表：粘贴旧版/新版分享码（`ncs://qr/v2/...`）→ 解码 → 新建课表并写入课程。
 * 扫码与导入入口统一放在标题栏菜单（左扫码、右勾选），页面本体只保留输入框与提示。
 *
 * 解码逻辑在 `data/ShareCodec.ets`（与旧版 `ncs://qr/v2` 协议完全兼容），
 * 课程字段映射复用教务导入模块的 `ImportCourseCodec`，保证两条导入路径同源。
 */
import { HdsNavDestination, HdsNavigationMenuContentOptions, HdsNavigationTitleBarOptions, IconStyleMode } from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { AppState } from '../../app/AppState';
import {} from '../../app/AppPreferences';
import { Colors, FontSize, HdsMetrics, Radius, Spacing } from '../../common/design/Tokens';
import { Feedback } from '../../common/ui/Feedback';
import { AppStore } from '../../app/AppStore';
import { hdsSubPageBackPressed, hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import { ImportCourseCodec } from '../import/ImportPayloadCodec';
import { CourseRepository } from '../../data/CourseRepository';
import { CourseTableRepository } from '../../data/CourseTableRepository';
import { CourseTable, Course } from '../../data/models/Models';
import { DecodedSharePayload, ShareCodec, ShareCodeError, ShareFrame } from '../../data/ShareCodec';

@ComponentV2
export struct ImportCodePage {
  /** V2 全局 Store（主题色 / 避让区 / 当前课表）。 */
  @Local store: AppStore = AppStore.connect();
  /** 滚动控制器（与 HdsNavDestination 绑定，获得标题栏动态模糊）。 */
  private subScroller: Scroller = new Scroller();

  @Param pageStack: NavPathStack = new NavPathStack();

  @Local codeInput: string = '';
  @Local busy: boolean = false;
  @Local errorText: string = '';
  @Local previewText: string = '';
  @Local scanning: boolean = false;
  @Local scanHint: string = '';

  /** 多帧分享码扫描缓存（key = group:index）。 */
  private scannedFrames: Map<string, string> = new Map();

  /** 拉起系统扫码界面（默认界面扫码，相机权限由系统预授权，无需应用申请）。 */
  private async startScan(): Promise<void> {
    if (this.scanning) {
      return;
    }
    this.scanning = true;
    this.errorText = '';
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false
      };
      const result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(context, options);
      await this.handleScanValue(result.originalValue);
    } catch (err) {
      // 用户取消或扫码失败：静默返回，不打断当前页面。
      this.scanHint = '';
    } finally {
      this.scanning = false;
    }
  }

  /** 处理扫码结果：单帧直接导入，多帧收集齐后自动导入。 */
  private async handleScanValue(value: string): Promise<void> {
    const text: string = value.trim();
    if (text === '') {
      this.errorText = '没有识别到内容，请重试';
      return;
    }
    const frame: ShareFrame | null = ShareCodec.frameOf(text);
    if (frame === null) {
      this.errorText = '这不是呢喃课表的分享码';
      return;
    }
    if (!frame.isMulti) {
      this.codeInput = text;
      await this.importCode();
      return;
    }
    this.scannedFrames.set(`${frame.group}:${frame.index}`, text);
    this.scanHint = `已扫描 ${this.scannedFrames.size}/${frame.total} 帧`;
    const merged: string | null = ShareCodec.mergeFrames(this.scannedFrames);
    if (merged === null) {
      Feedback.toast(this.getUIContext(), `已扫描 ${this.scannedFrames.size}/${frame.total} 帧，请继续扫描`);
      await this.startScan();
      return;
    }
    this.scannedFrames.clear();
    this.scanHint = '';
    this.codeInput = merged;
    await this.importCode();
  }

  private async importCode(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.errorText = '';
    this.previewText = '';
    try {
      const raw: string = this.normalizeInput(this.codeInput);
      if (raw === '') {
        this.errorText = this.codeInput.trim().startsWith('ncs://qr/v2/m/') ?
          '多帧分享码不完整，请粘贴/扫描全部分帧' : '请先粘贴分享码';
        return;
      }
      if (!ShareCodec.isShareCode(raw) && !raw.startsWith('ncs://qr/')) {
        this.errorText = '这不是呢喃课表的分享码（应以 ncs://qr/ 开头）';
        return;
      }
      const decoded: DecodedSharePayload = await ShareCodec.decode(raw);
      const table: CourseTable = await CourseTableRepository.insert(
        new CourseTable(decoded.tableName, decoded.tableData));
      const courses: Course[] = ImportCourseCodec.toCourses(decoded.courses, table.id);
      if (courses.length > 0) {
        await CourseRepository.insertMany(courses);
      }
      await AppState.switchTable(table.id);
      this.previewText = `已导入「${decoded.tableName}」，共 ${courses.length} 门课程`;
      Feedback.toast(this.getUIContext(), this.previewText);
      this.pageStack.pop();
    } catch (err) {
      const message: string = err instanceof Error ? err.message : '未知错误';
      this.errorText = `导入失败：${this.describeError(message)}`;
    } finally {
      this.busy = false;
    }
  }

  /**
   * 归一化输入：单帧分享码直接返回；多帧（扫码复制或按行/空格粘贴）收集后合并。
   * 返回空串表示内容不合法或不完整，由调用方给出提示。
   */
  private normalizeInput(input: string): string {
    const text: string = input.trim();
    if (text === '') {
      return '';
    }
    const tokens: string[] = text.split(/\s+/);
    const frames: Map<string, string> = new Map();
    let lastFrame: ShareFrame | null = null;
    let frameCount: number = 0;
    for (let i = 0; i < tokens.length; i++) {
      const token: string = tokens[i];
      if (!token.startsWith('ncs://qr/')) {
        continue;
      }
      const frame: ShareFrame | null = ShareCodec.frameOf(token);
      if (frame === null) {
        continue;
      }
      frames.set(`${frame.group}:${frame.index}`, token);
      lastFrame = frame;
      frameCount++;
    }
    if (frameCount === 0) {
      return '';
    }
    if (frameCount === 1 && lastFrame !== null && !lastFrame.isMulti) {
      return text;
    }
    const merged: string | null = ShareCodec.mergeFrames(frames);
    return merged === null ? '' : merged;
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
    if (code === ShareCodeError.MissingTableName) {
      return '分享码缺少课表名称';
    }
    if (code === ShareCodeError.PayloadTooLarge) {
      return '分享码过长';
    }
    return code;
  }

  /** 标题栏菜单：左扫码、右勾选导入；页面本体不提供任何按钮。 */
  private titleBarOptions(): HdsNavigationTitleBarOptions {
    const menu: HdsNavigationMenuContentOptions = {
      value: [{
        content: {
          icon: $r('sys.symbol.line_viewfinder'),
          type: IconStyleMode.NORMAL,
          isEnabled: !this.busy && !this.scanning,
          action: () => {
            this.startScan();
          }
        }
      }, {
        content: {
          icon: $r('sys.symbol.checkmark'),
          type: IconStyleMode.NORMAL,
          isEnabled: !this.busy && !this.scanning,
          action: () => {
            this.importCode();
          }
        }
      }]
    };
    return hdsSubPageTitleBar('从分享码导入', '粘贴其他设备分享的课表编码', menu);
  }

  build() {
    HdsNavDestination() {
      Column() {
      Scroll(this.subScroller) {
        Column({ space: Spacing.Lg }) {
          Column({ space: Spacing.Sm }) {
            Text('分享码')
              .fontSize(FontSize.BodySm)
              .fontColor(Colors.TextSecondary)
              .width('100%')
            TextArea({ text: this.codeInput, placeholder: '粘贴 ncs://qr/v2/... 分享码' })
              .width('100%')
              .height(160)
              .fontSize(FontSize.BodySm)
              .backgroundColor(Colors.Surface)
              .borderRadius(Radius.Md)
              .border({ width: 1, color: Colors.Outline })
              .onChange((value: string) => {
                this.codeInput = value;
              })
            Text('提示：右上角可扫码导入。')
              .fontSize(FontSize.Caption)
              .fontColor(Colors.TextTertiary)
              .width('100%')
          }

          if (this.errorText !== '') {
            Text(this.errorText)
              .fontSize(FontSize.BodySm)
              .fontColor(Colors.Error)
              .width('100%')
          }
          if (this.previewText !== '') {
            Text(this.previewText)
              .fontSize(FontSize.BodySm)
              .fontColor(Colors.Success)
              .width('100%')
          }

          if (this.scanHint !== '') {
            Text(this.scanHint)
              .fontSize(FontSize.BodySm)
              .fontColor(Colors.TextSecondary)
              .width('100%')
          }
        }
        .width('100%')
        .padding({
          left: Spacing.Lg,
          right: Spacing.Lg,
          top: HdsMetrics.contentTopInset(px2vp(this.store.windowTopInset)) + Spacing.Md,
          bottom: Spacing.Xxl
        })
        .alignItems(HorizontalAlign.Start)
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
      .layoutWeight(1)
      .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.Background)
    }
    .titleBar(this.titleBarOptions())
    .onBackPressed(hdsSubPageBackPressed)
    .bindToScrollable([this.subScroller])
  }
}
