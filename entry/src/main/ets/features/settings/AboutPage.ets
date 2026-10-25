/**
 * 关于页（路由名 `about`）。
 *
 * 组织逻辑参考同类应用：顶部产品信息 → 项目链接 → 开源信息 → 本应用信息；
 * 「贡献指南/源代码/项目主页/问题反馈」等链接待开源仓库上线后填写（当前留空显示占位）。
 *
 * 本页链接只做复制到剪贴板；隐私政策页始终展示 AGC 托管声明。
 */
import { HdsNavDestination } from '@kit.UIDesignKit';
import { Colors, FontSize, HdsMetrics, Radius, Spacing } from '../../common/design/Tokens';
import { readVersionName } from '../../common/AppVersion';
import { openUrl } from '../../common/ui/OpenLink';
import { Feedback } from '../../common/ui/Feedback';
import { AppStore } from '../../app/AppStore';
import { hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import { AppCard } from '../../common/ui/AppCard';
import { SectionHeader } from '../../common/ui/SectionHeader';
import { SettingsRow, SettingsRowDivider } from './SettingsCommon';

/** 包信息读不到时的兜底版本号（与 AppScope/app.json5 的 versionName 保持一致）。 */
const FALLBACK_VERSION: string = '0.1.5';
const ROUTE_PRIVACY: string = 'privacy';
const ROUTE_LICENSES: string = 'licenses';
const ROUTE_ACKNOWLEDGEMENTS: string = 'acknowledgements';
const DEVELOPER_UPSTREAM: string = 'idealclover';
const DEVELOPER_REWRITE: string = 'JesseLee-CN';

/** GitHub 仓库链接。 */
const REPO_URL: string = 'https://github.com/WheretoSleepinNJU/njuschedule-hmos';
const LINK_SOURCE_CODE: string = REPO_URL;
const LINK_PROJECT_HOME: string = REPO_URL;
const LINK_ISSUES: string = 'https://github.com/WheretoSleepinNJU/njuschedule-hmos/issues';
const LINK_CONTRIBUTING: string = 'https://github.com/WheretoSleepinNJU/njuschedule-hmos/blob/main/CONTRIBUTING.md';

@ComponentV2
export struct AboutPage {
  /** V2 全局 Store（主题色等）。 */
  @Local store: AppStore = AppStore.connect();
  @Param pageStack: NavPathStack = new NavPathStack();

  @Local version: string = FALLBACK_VERSION;

  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadVersion();
  }

  private async loadVersion(): Promise<void> {
    this.version = await readVersionName(FALLBACK_VERSION);
  }

  /** 待补充链接行：留空时只提示，不复制空串。 */
  @Builder
  private linkRow(title: string, url: string, icon: Resource) {
    SettingsRow({
      icon: icon,
      title: title,
      trailingText: url === '' ? '待补充' : '打开链接',
      showArrow: false,
      onTap: () => {
        if (url === '') {
          Feedback.toast(this.getUIContext(), '开源仓库上线后补充链接');
        } else {
          openUrl(this.getUIContext(), url);
        }
      }
    })
  }

  @Builder
  private appHeader(): void {
    AppCard() {
      Column({ space: Spacing.Sm }) {
        // 使用应用实际图标（与桌面图标一致）
        Image($r('app.media.startIcon'))
          .width(72)
          .height(72)
          .borderRadius(Radius.Xl)
          .objectFit(ImageFit.Cover)

        // 应用名取模块字符串资源（EntryAbility_label 与 AppScope 的 app_name 同为「呢喃课表」；
        // AppScope 资源不在 check arkts 的资源校验范围内，这里用模块内可见的等价文案）。
        Text($r('app.string.EntryAbility_label'))
          .fontSize(FontSize.Headline)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.TextPrimary)

        Text(`v${this.version}`)
          .fontSize(FontSize.BodySm)
          .fontColor(Colors.TextTertiary)

        Text('不止南京大学的课程表 · HarmonyOS / ArkUI')
          .fontSize(FontSize.Caption)
          .fontColor(Colors.TextTertiary)
          .textAlign(TextAlign.Center)

        Text(`本项目作者：${DEVELOPER_REWRITE} · 上游 Flutter 项目作者：${DEVELOPER_UPSTREAM}`)
          .fontSize(FontSize.Caption)
          .fontColor(Colors.TextTertiary)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder
  private projectSection(): void {
    SectionHeader({ title: '项目' })
    AppCard({ contentPadding: 0 }) {
      this.linkRow('源代码', LINK_SOURCE_CODE, $r('sys.symbol.code'))
      SettingsRowDivider()
      this.linkRow('项目主页', LINK_PROJECT_HOME, $r('sys.symbol.link'))
      SettingsRowDivider()
      this.linkRow('问题反馈', LINK_ISSUES, $r('sys.symbol.exclamationmark_circle'))
    }
  }

  @Builder
  private openSourceSection(): void {
    SectionHeader({ title: '开源' })
    AppCard({ contentPadding: 0 }) {
      this.linkRow('贡献指南', LINK_CONTRIBUTING, $r('sys.symbol.pencil_line'))
      SettingsRowDivider()
      SettingsRow({
        icon: $r('sys.symbol.heart'),
        title: '致谢',
        onTap: () => {
          this.pageStack.pushPathByName(ROUTE_ACKNOWLEDGEMENTS, null);
        }
      })
      SettingsRowDivider()
      SettingsRow({
        icon: $r('sys.symbol.doc_text'),
        title: '开源许可证',
        trailingText: 'Apache-2.0',
        showArrow: false,
        onTap: () => {
        }
      })
      SettingsRowDivider()
      SettingsRow({
        icon: $r('sys.symbol.book_pages'),
        title: '第三方许可证',
        onTap: () => {
          this.pageStack.pushPathByName(ROUTE_LICENSES, null);
        }
      })
    }
  }

  @Builder
  private appSection(): void {
    SectionHeader({ title: '本应用' })
    AppCard({ contentPadding: 0 }) {
      SettingsRow({
        icon: $r('sys.symbol.info_circle'),
        title: '版本',
        trailingText: `v${this.version}`,
        showArrow: false,
        onTap: () => {
        }
      })
      SettingsRowDivider()
      SettingsRow({
        icon: $r('sys.symbol.person'),
        title: '原项目开发者',
        subtitle: '上游 Flutter 版',
        trailingText: DEVELOPER_UPSTREAM,
        onTap: () => {
          openUrl(this.getUIContext(), `https://github.com/${DEVELOPER_UPSTREAM}`);
        }
      })
      SettingsRowDivider()
      SettingsRow({
        icon: $r('sys.symbol.pencil_line'),
        title: '本项目开发者',
        subtitle: 'HarmonyOS / ArkUI 版',
        trailingText: DEVELOPER_REWRITE,
        onTap: () => {
          openUrl(this.getUIContext(), `https://github.com/${DEVELOPER_REWRITE}`);
        }
      })
      SettingsRowDivider()
      SettingsRow({
        icon: $r('sys.symbol.lock_shield'),
        title: '隐私政策',
        subtitle: '个人信息处理规则',
        onTap: () => {
          this.pageStack.pushPathByName(ROUTE_PRIVACY, null);
        }
      })
      // 备案号：待取得我方备案号后，在此加回 SettingsRow（旧版上游备案号已移除，不再展示）。
    }
  }

  build() {
    HdsNavDestination() {
      Column() {
        Scroll(this.scroller) {
          Column({ space: Spacing.Lg }) {
            this.appHeader()
            this.projectSection()
            this.openSourceSection()
            this.appSection()
          }
          .width('100%')
          .constraintSize({ maxWidth: 800 })
          .padding({
            left: Spacing.Lg,
            right: Spacing.Lg,
            top: HdsMetrics.contentTopInset(px2vp(this.store.windowTopInset)) + Spacing.Md,
            bottom: Spacing.Xxxl
          })
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.Background)
    }
    .titleBar(hdsSubPageTitleBar('关于'))
    .bindToScrollable([this.scroller])
  }
}
