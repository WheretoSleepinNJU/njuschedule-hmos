/** 导出系统日历期间的不可取消加载弹窗。 */
import { CustomContentDialogV2 } from '@kit.ArkUI';
import { AppStore } from '../../app/AppStore';
import { Colors, FontSize, Spacing } from '../../common/design/Tokens';

@ComponentV2
export struct CalendarLoadingDialog {
  @Local store: AppStore = AppStore.connect();

  @Builder
  private loadingContent(): void {
    Column({ space: Spacing.Md }) {
      LoadingProgress()
        .width(36)
        .height(36)
        .color(this.store.accentDisplay)
      Text('正在导出课程日程，请稍候…')
        .fontSize(FontSize.Body)
        .fontColor(Colors.TextSecondary)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: Spacing.Md, bottom: Spacing.Md })
  }

  build() {
    CustomContentDialogV2({
      primaryTitle: '导出到系统日历',
      contentBuilder: () => {
        this.loadingContent()
      }
    })
  }
}
