/**
 * 隐私政策页（路由名 `privacy`）。
 *
 * 始终展示 AGC 托管隐私声明：优先通过 privacyManager 查询最新 URL，
 * 本地调试/未上架时使用 AGC 已生成的托管链接；不再回退到应用内本地全文。
 */
import { HdsNavDestination } from '@kit.UIDesignKit';
import { privacyManager } from '@kit.AppGalleryKit';
import { webview } from '@kit.ArkWeb';
import { Colors, FontSize, HdsMetrics, Spacing } from '../../common/design/Tokens';
import { hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import { AppStore } from '../../app/AppStore';

/** AGC 生成的托管隐私声明链接，privacyManager 查不到时使用。 */
const HOSTED_PRIVACY_URL: string =
  'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2068300045962206912';

@ComponentV2
export struct PrivacyPage {
  @Local store: AppStore = AppStore.connect();
  @Local hostedUrl: string = HOSTED_PRIVACY_URL;
  @Local webFailed: boolean = false;

  private webController: webview.WebviewController = new webview.WebviewController();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    try {
      const info: privacyManager.AppPrivacyMgmtInfo = privacyManager.getAppPrivacyMgmtInfo();
      const links: privacyManager.AppPrivacyLink[] = info.privacyInfo;
      for (let i = 0; i < links.length; i++) {
        if (links[i].type === privacyManager.AppPrivacyLinkType.PRIVACY_STATEMENT_LINK && links[i].url.length > 0) {
          this.hostedUrl = links[i].url;
          break;
        }
      }
    } catch (err) {
      // 未上架/本地调试时查不到托管信息，继续使用上面的 AGC 托管链接。
    }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Scroll(this.scroller) {
          Column() {
            Web({ src: this.hostedUrl, controller: this.webController })
              .width('100%')
              .layoutMode(WebLayoutMode.FIT_CONTENT)
              .backgroundColor(Colors.Background)
              .javaScriptAccess(true)
              .domStorageAccess(true)
              .onErrorReceive(() => {
                this.webFailed = true;
              })
          }
          .width('100%')
          .padding({
            top: HdsMetrics.contentTopInset(px2vp(this.store.windowTopInset)) + Spacing.Md,
            bottom: Spacing.Sm + HdsMetrics.FloatingTabBarClearance
          })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        if (this.webFailed) {
          Column({ space: Spacing.Md }) {
            Text('隐私政策加载失败，请检查网络后重试')
              .fontSize(FontSize.Body)
              .fontColor(Colors.TextSecondary)
              .textAlign(TextAlign.Center)
            Button('重新加载')
              .fontSize(FontSize.BodySm)
              .fontColor(Colors.TextPrimary)
              .backgroundColor(Colors.SurfaceHigh)
              .onClick(() => {
                this.webFailed = false;
                this.hostedUrl = HOSTED_PRIVACY_URL;
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .padding(Spacing.Xl)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.Background)
    }
    .titleBar(hdsSubPageTitleBar('隐私政策'))
    .bindToScrollable([this.scroller])
  }
}
