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
import { Colors, HdsMetrics, Spacing } from '../../common/design/Tokens';
import { AppStore } from '../../app/AppStore';
import { Feedback } from '../../common/ui/Feedback';
import { openUrl } from '../../common/ui/OpenLink';
import { hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import { SettingsItemDivider, SettingsItemGroup, SettingsRow } from '../../common/ui/SettingsListItems';

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
    ListItem() {
      SettingsItemGroup({ title: '贡献' }) {
        SettingsRow({
          icon: $r('sys.symbol.person_2'),
          title: '贡献者',
          subtitle: '欢迎贡献！',
          trailingText: LINK_CONTRIBUTORS === '' ? '待补充' : '',
          showArrow: LINK_CONTRIBUTORS !== '',
          externalLink: LINK_CONTRIBUTORS !== '',
          onTap: () => {
            if (LINK_CONTRIBUTORS === '') {
              Feedback.toast(this.getUIContext(), '开源仓库上线后补充链接');
            } else {
              openUrl(this.getUIContext(), LINK_CONTRIBUTORS);
            }
          }
        })
        SettingsItemDivider()
        SettingsRow({
          icon: $r('sys.symbol.person'),
          title: '上游 Flutter 项目作者',
          subtitle: `${DEVELOPER_UPSTREAM}：数据模型、教务导入脚本、分享码协议与讲座服务`,
          externalLink: true,
          onTap: () => {
            openUrl(this.getUIContext(), LegacyUrl.BLOG);
          }
        })
      }
    }
  }

  @Builder
  private serviceSection(): void {
    ListItem() {
      SettingsItemGroup({ title: '服务' }) {
        SettingsRow({
          icon: $r('sys.symbol.book'),
          title: '讲座数据接口',
          subtitle: '南大讲座数据，由上游作者 idealclover 提供',
          externalLink: true,
          onTap: () => {
            openUrl(this.getUIContext(), LegacyUrl.BACKEND);
          }
        })
        SettingsItemDivider()
        SettingsRow({
          icon: $r('sys.symbol.doc_text'),
          title: '教务系统列表获取',
          subtitle: '各校教务导入配置，由上游作者 idealclover 提供',
          externalLink: true,
          onTap: () => {
            openUrl(this.getUIContext(), `${LegacyUrl.UPDATE_ROOT}/schoolList.json`);
          }
        })
      }
    }
  }

  @Builder
  private projectSection(): void {
    ListItem() {
      SettingsItemGroup({ title: '开源项目' }) {
        SettingsRow({
          icon: $r('sys.symbol.calendar'),
          title: '南哪课表（上游 Flutter 项目）',
          subtitle: '数据模型、教务导入配置与解析脚本、分享码协议来源',
          externalLink: true,
          onTap: () => {
            openUrl(this.getUIContext(), LegacyUrl.OPEN_SOURCE);
          }
        })
        SettingsItemDivider()
        SettingsRow({
          icon: $r('sys.symbol.paintpalette'),
          title: 'Kazumi',
          subtitle: 'UI 组织参考',
          externalLink: true,
          onTap: () => {
            openUrl(this.getUIContext(), KAZUMI_REPO);
          }
        })
      }
    }
  }


  build() {
    HdsNavDestination() {
      Column() {
        List({ space: Spacing.Md, scroller: this.scroller }) {
          this.contributorSection()
          this.serviceSection()
          this.projectSection()
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
    .titleBar(hdsSubPageTitleBar('致谢'))
    .bindToScrollable([this.scroller])
  }

}
