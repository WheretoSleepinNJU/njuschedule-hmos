/**
 * 第三方许可证页（路由名 `licenses`，从「关于 → 第三方许可证」进入）。
 *
 * 组织逻辑参考同类应用：顶部应用名/版本/许可证 + 开源组件列表（名称 + 许可数量），
 * 点击组件进入完整许可证文本详情页；下方单列「平台能力（非开源库）」。
 *
 * 收录范围：对比上游 Flutter 项目「关于 → 开源库」清单，只保留上游使用、
 * 且本应用移植了对应能力的开源库，许可证与版权归原作者。
 * 数据见 ThirdPartyLicenseData。
 */
import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppStore } from '../../app/AppStore';
import { readVersionName } from '../../common/AppVersion';
import { LicenseDetailParam } from '../../common/RouteParams';
import { Colors, FontSize, HdsMetrics, Spacing } from '../../common/design/Tokens';
import { hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import { AppCard } from '../../common/ui/AppCard';
import { SectionHeader } from '../../common/ui/SectionHeader';
import { SettingsRowDivider } from './SettingsCommon';
import { THIRD_PARTY_LICENSES, ThirdPartyLicense } from './ThirdPartyLicenseData';

const FALLBACK_VERSION: string = '0.1.6';
const ROUTE_LICENSE_DETAIL: string = 'license-detail';

/** 系统能力（非第三方开源库，遵循 HarmonyOS SDK 许可协议）。 */
const PLATFORM_ITEMS: string[] = [
  'ArkUI / ArkTS 声明式 UI 与状态管理 V2（@ComponentV2 / @ObservedV2）',
  'AbilityKit（Stage 模型、UIAbility、ApplicationContext）',
  'ArkData（relationalStore 数据库、preferences 首选项）',
  'ArkWeb（教务导入登录页）',
  'Scan Kit（分享码二维码生成与系统扫码界面）',
  'Form Kit（桌面小组件）',
  'ImageKit / PhotoViewPicker（课表背景图）',
  'UIDesignKit HDS（HdsNavigation / HdsTabs / HdsNavDestination / 系统材质）'
];

@ComponentV2
export struct OpenSourceLicensesPage {
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

  private openLicense(item: ThirdPartyLicense): void {
    this.pageStack.pushPathByName(ROUTE_LICENSE_DETAIL, new LicenseDetailParam(item.name));
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
  private componentRow(item: ThirdPartyLicense) {
    Column({ space: Spacing.Xs }) {
      Row() {
        Text(item.name)
          .fontSize(FontSize.Title)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.TextPrimary)
          .layoutWeight(1)
        Text(`${item.licenseCount} 份许可`)
          .fontSize(FontSize.Caption)
          .fontColor(Colors.TextTertiary)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([Colors.TextTertiary])
      }
      .width('100%')
      Text(`${item.license} · ${item.copyright}`)
        .fontSize(FontSize.BodySm)
        .fontColor(Colors.TextSecondary)
        .width('100%')
    }
    .width('100%')
    .padding({ left: Spacing.Lg, right: Spacing.Lg, top: Spacing.Md, bottom: Spacing.Md })
    .onClick(() => {
      this.openLicense(item);
    })
  }

  @Builder
  private componentSection(): void {
    SectionHeader({
      title: '开源组件',
      caption: '上游项目使用、且本应用移植对应能力的开源库'
    })
    AppCard({ contentPadding: 0 }) {
      ForEach(THIRD_PARTY_LICENSES, (item: ThirdPartyLicense, index: number) => {
        if (index > 0) {
          SettingsRowDivider()
        }
        this.componentRow(item)
      }, (item: ThirdPartyLicense) => item.name)
    }
  }

  @Builder
  private platformSection(): void {
    SectionHeader({ title: '平台能力（非开源库）' })
    AppCard() {
      Column({ space: Spacing.Sm }) {
        Text('以下能力由 HarmonyOS SDK 提供，遵循华为 HarmonyOS SDK 许可协议，不属于第三方开源库：')
          .fontSize(FontSize.BodySm)
          .fontColor(Colors.TextSecondary)
          .width('100%')
        ForEach(PLATFORM_ITEMS, (text: string) => {
          Text(`· ${text}`)
            .fontSize(FontSize.BodySm)
            .fontColor(Colors.TextTertiary)
            .width('100%')
        }, (text: string) => text)
      }
      .alignItems(HorizontalAlign.Start)
    }
  }

  build() {
    HdsNavDestination() {
      Column() {
        Scroll(this.scroller) {
          Column({ space: Spacing.Lg }) {
            this.header()
            this.componentSection()
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
    .titleBar(hdsSubPageTitleBar('第三方许可证'))
    .bindToScrollable([this.scroller])
  }
}
