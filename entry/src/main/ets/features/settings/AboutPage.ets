/**
 * 关于页（路由名 `about`）。
 *
 * 组织逻辑参考同类应用：顶部产品信息 → 项目链接 → 开源信息 → 本应用信息；
 * 「贡献指南/源代码/项目主页/问题反馈」等链接待开源仓库上线后填写（当前留空显示占位）。
 *
 * 外部链接统一用系统浏览器打开；隐私政策页在应用内展示 AGC 托管声明。
 */
import { HdsNavDestination } from '@kit.UIDesignKit';
import { Colors, FontSize, HdsMetrics, Radius, Spacing } from '../../common/design/Tokens';
import { readVersionName } from '../../common/AppVersion';
import { openUrl } from '../../common/ui/OpenLink';
import { Feedback } from '../../common/ui/Feedback';
import { AppStore } from '../../app/AppStore';
import { hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import { SettingsItemDivider, SettingsItemGroup, SettingsRow } from '../../common/ui/SettingsListItems';

/** 包信息读不到时的兜底版本号（与 AppScope/app.json5 的 versionName 保持一致）。 */
const FALLBACK_VERSION: string = '0.1.6';
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
      trailingText: url === '' ? '待补充' : '',
      showArrow: url !== '',
      externalLink: url !== '',
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
    SettingsItemGroup() {
      Column({ space: Spacing.Sm }) {
        // 使用应用实际图标（与桌面图标一致）
        Image($r('app.media.startIcon'))
          .width(72)
          .height(72)
          .borderRadius(Radius.Xl)
          .objectFit(ImageFit.Cover)

        // 应用名取模块字符串资源（EntryAbility_label 与 AppScope 的 app_name 同为「呢喃课表」）。
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
      .padding({ left: Spacing.Lg, right: Spacing.Lg, top: Spacing.Xl, bottom: Spacing.Xl })
      .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder
  private projectSection(): void {
    ListItem() {
      SettingsItemGroup({ title: '项目' }) {
        this.linkRow('源代码', LINK_SOURCE_CODE, $r('sys.symbol.code'))
        SettingsItemDivider()
        this.linkRow('项目主页', LINK_PROJECT_HOME, $r('sys.symbol.link'))
        SettingsItemDivider()
        this.linkRow('问题反馈', LINK_ISSUES, $r('sys.symbol.exclamationmark_circle'))
      }
    }
  }

  @Builder
  private openSourceSection(): void {
    ListItem() {
      SettingsItemGroup({ title: '开源' }) {
        this.linkRow('贡献指南', LINK_CONTRIBUTING, $r('sys.symbol.pencil_line'))
        SettingsItemDivider()
        SettingsRow({
          icon: $r('sys.symbol.heart'),
          title: '致谢',
          onTap: () => {
            this.pageStack.pushPathByName(ROUTE_ACKNOWLEDGEMENTS, null);
          }
        })
        SettingsItemDivider()
        SettingsRow({
          icon: $r('sys.symbol.doc_text'),
          title: '开源许可证',
          trailingText: 'Apache-2.0',
          externalLink: true,
          onTap: () => {
            openUrl(this.getUIContext(), `${REPO_URL}/blob/main/LICENSE`);
          }
        })
        SettingsItemDivider()
        SettingsRow({
          icon: $r('sys.symbol.book_pages'),
          title: '第三方许可证',
          onTap: () => {
            this.pageStack.pushPathByName(ROUTE_LICENSES, null);
          }
        })
      }
    }
  }

  @Builder
  private appSection(): void {
    ListItem() {
      SettingsItemGroup({ title: '本应用' }) {
        SettingsRow({
          icon: $r('sys.symbol.info_circle'),
          title: '版本',
          trailingText: `v${this.version}`,
          showArrow: false
        })
        SettingsItemDivider()
        SettingsRow({
          icon: $r('sys.symbol.person'),
          title: '原项目开发者',
          subtitle: '上游 Flutter 版',
          trailingText: DEVELOPER_UPSTREAM,
          externalLink: true,
          onTap: () => {
            openUrl(this.getUIContext(), `https://github.com/${DEVELOPER_UPSTREAM}`);
          }
        })
        SettingsItemDivider()
        SettingsRow({
          icon: $r('sys.symbol.pencil_line'),
          title: '本项目开发者',
          subtitle: 'HarmonyOS / ArkUI 版',
          trailingText: DEVELOPER_REWRITE,
          externalLink: true,
          onTap: () => {
            openUrl(this.getUIContext(), `https://github.com/${DEVELOPER_REWRITE}`);
          }
        })
        SettingsItemDivider()
        SettingsRow({
          icon: $r('sys.symbol.lock_shield'),
          title: '隐私政策',
          subtitle: '个人信息处理规则',
          onTap: () => {
            this.pageStack.pushPathByName(ROUTE_PRIVACY, null);
          }
        })
      }
    }
  }

  build() {
    HdsNavDestination() {
      Column() {
        List({ space: Spacing.Md, scroller: this.scroller }) {
          ListItem() {
            this.appHeader()
          }
          this.projectSection()
          this.openSourceSection()
          this.appSection()
        }
        .width('100%')
        .constraintSize({ maxWidth: 800 })
        .layoutWeight(1)
        .padding({
          left: Spacing.Md,
          right: Spacing.Md,
          top: HdsMetrics.contentTopInset(px2vp(this.store.windowTopInset)) + Spacing.Md,
          bottom: Spacing.Xxxl
        })
        .clip(false)
        .cachedCount(3, true)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(Colors.Background)
    }
    .titleBar(hdsSubPageTitleBar('关于'))
    .bindToScrollable([this.scroller])
  }

}
