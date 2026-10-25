/**
 * 致谢页（路由名 `acknowledgements`，从「关于 → 致谢」进入）。
 *
 * 组织逻辑参考同类应用（Kazumi）：
 * - 贡献：贡献者（指向 GitHub contributors 页面，仓库开源后补充链接）
 * - 服务：本应用使用的外部数据服务
 * - 开源项目：使用的开源项目 / UI 组织参考
 * - 平台：系统能力说明
 * 外链均通过系统浏览器打开；图标作者不作为致谢项。
 */
import { HdsNavDestination } from '@kit.UIDesignKit';
import { LegacyUrl } from '../../common/Constants';
import { Colors, FontSize, HdsMetrics, Spacing } from '../../common/design/Tokens';
import { AppStore } from '../../app/AppStore';
import { Feedback } from '../../common/ui/Feedback';
import { openUrl } from '../../common/ui/OpenLink';
import { hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import { AppCard } from '../../common/ui/AppCard';
import { SectionHeader } from '../../common/ui/SectionHeader';
import { SettingsRow, SettingsRowDivider } from './SettingsCommon';

const DEVELOPER_UPSTREAM: string = 'idealclover';
/** 本应用的 GitHub 贡献者页面。 */
const LINK_CONTRIBUTORS: string = 'https://github.com/WheretoSleepinNJU/njuschedule-hmos/graphs/contributors';
/** UI 组织参考项目。 */
const KAZUMI_REPO: string = 'https://github.com/Predidit/Kazumi';

@ComponentV2
export struct AcknowledgementsPage {
  @Local store: AppStore = AppStore.connect();

  private scroller: Scroller = new Scroller();

  @Builder
  private contributorSection(): void {
    SectionHeader({ title: '贡献' })
    AppCard({ contentPadding: 0 }) {
      SettingsRow({
        icon: $r('sys.symbol.person_2'),
        title: '贡献者',
        subtitle: '欢迎贡献！',
        trailingText: LINK_CONTRIBUTORS === '' ? '待补充' : '打开链接',
        showArrow: false,
        onTap: () => {
          if (LINK_CONTRIBUTORS === '') {
            Feedback.toast(this.getUIContext(), '开源仓库上线后补充链接');
          } else {
            openUrl(this.getUIContext(), LINK_CONTRIBUTORS);
          }
        }
      })
      SettingsRowDivider()
      SettingsRow({
        icon: $r('sys.symbol.person'),
        title: '上游 Flutter 项目作者',
        subtitle: `${DEVELOPER_UPSTREAM}：数据模型、教务导入脚本、分享码协议与讲座服务`,
        trailingText: '打开链接',
        showArrow: false,
        onTap: () => {
          openUrl(this.getUIContext(), LegacyUrl.BLOG);
        }
      })
    }
  }

  @Builder
  private serviceSection(): void {
    SectionHeader({ title: '服务' })
    AppCard({ contentPadding: 0 }) {
      SettingsRow({
        icon: $r('sys.symbol.book'),
        title: '讲座数据接口',
        subtitle: '南大讲座数据，由上游作者 idealclover 提供',
        trailingText: '打开链接',
        showArrow: false,
        onTap: () => {
          openUrl(this.getUIContext(), LegacyUrl.BACKEND);
        }
      })
    }
  }

  @Builder
  private projectSection(): void {
    SectionHeader({ title: '开源项目' })
    AppCard({ contentPadding: 0 }) {
      SettingsRow({
        icon: $r('sys.symbol.calendar'),
        title: '南哪课表（上游 Flutter 项目）',
        subtitle: '数据模型、教务导入配置与解析脚本、分享码协议来源',
        trailingText: '打开链接',
        showArrow: false,
        onTap: () => {
          openUrl(this.getUIContext(), LegacyUrl.OPEN_SOURCE);
        }
      })
      SettingsRowDivider()
      SettingsRow({
        icon: $r('sys.symbol.paintpalette'),
        title: 'Kazumi',
        subtitle: 'UI 组织参考',
        trailingText: '打开链接',
        showArrow: false,
        onTap: () => {
          openUrl(this.getUIContext(), KAZUMI_REPO);
        }
      })
    }
  }

  @Builder
  private platformSection(): void {
    SectionHeader({ title: '平台' })
    AppCard() {
      Text('HarmonyOS / ArkUI 提供了声明式 UI、状态管理 V2、HDS 组件、ArkWeb、Scan Kit、' +
        'Form Kit、数据库与首选项等系统能力，本应用基于这些官方能力实现。')
        .fontSize(FontSize.BodySm)
        .fontColor(Colors.TextSecondary)
        .lineHeight(20)
        .width('100%')
    }
  }

  build() {
    HdsNavDestination() {
      Column() {
        Scroll(this.scroller) {
          Column({ space: Spacing.Lg }) {
            this.contributorSection()
            this.serviceSection()
            this.projectSection()
            this.platformSection()
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
    .titleBar(hdsSubPageTitleBar('致谢'))
    .bindToScrollable([this.scroller])
  }
}
