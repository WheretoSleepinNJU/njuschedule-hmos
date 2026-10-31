/**
 * 第三方许可证页（路由名 `licenses`，从「关于 → 第三方许可证」进入）。
 *
 * 组织逻辑参考同类应用：顶部应用名/版本/许可证 + 开源组件列表（名称 + 许可数量），
 * 点击组件使用系统浏览器打开对应仓库/包管理器的许可证页面。
 *
 * 收录范围：对比上游 Flutter 项目「关于 → 开源库」清单，只保留上游使用、
 * 且本应用移植了对应能力的开源库，许可证与版权归原作者。
 * 数据见 ThirdPartyLicenseData。
 */
import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppStore } from '../../app/AppStore';
import { readVersionName } from '../../common/AppVersion';
import { Colors, FontSize, HdsMetrics, Spacing } from '../../common/design/Tokens';
import { hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import { openUrl } from '../../common/ui/OpenLink';
import { SettingsItemDivider, SettingsItemGroup, SettingsRow } from '../../common/ui/SettingsListItems';
import { THIRD_PARTY_LICENSES, ThirdPartyLicense } from './ThirdPartyLicenseData';

const FALLBACK_VERSION: string = '0.1.6';


@ComponentV2
export struct OpenSourceLicensesPage {
  @Local store: AppStore = AppStore.connect();
  @Local version: string = FALLBACK_VERSION;

  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadVersion();
  }

  private async loadVersion(): Promise<void> {
    this.version = await readVersionName(FALLBACK_VERSION);
  }

  @Builder
  private header(): void {
    Column({ space: Spacing.Xs }) {
      Text($r('app.string.EntryAbility_label'))
        .fontSize(FontSize.Hero)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.TextPrimary)
      Text(`v${this.version}`)
        .fontSize(FontSize.BodySm)
        .fontColor(Colors.TextTertiary)
      Text('呢喃课表 · Apache License 2.0')
        .fontSize(FontSize.BodySm)
        .fontColor(Colors.TextSecondary)
        .margin({ top: Spacing.Sm })
      Text('Powered by HarmonyOS / ArkUI')
        .fontSize(FontSize.Caption)
        .fontColor(Colors.TextTertiary)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: Spacing.Xl, bottom: Spacing.Md })
  }


  @Builder
  private componentSection(): void {
    ListItem() {
      SettingsItemGroup({ title: '开源组件' }) {
        ForEach(THIRD_PARTY_LICENSES, (item: ThirdPartyLicense, index: number) => {
          if (index > 0) {
            SettingsItemDivider()
          }
          SettingsRow({
            icon: $r('sys.symbol.code'),
            title: item.name,
            subtitle: `${item.license} · ${item.copyright}`,
            trailingText: `${item.licenseCount} 份许可`,
            externalLink: true,
            onTap: () => {
              openUrl(this.getUIContext(), item.url);
            }
          })
        }, (item: ThirdPartyLicense) => item.name)
      }
    }
  }



  build() {
    HdsNavDestination() {
      Column() {
        List({ space: Spacing.Md, scroller: this.scroller }) {
          ListItem() {
            this.header()
          }
          this.componentSection()
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
    .titleBar(hdsSubPageTitleBar('第三方许可证'))
    .bindToScrollable([this.scroller])
  }

}
