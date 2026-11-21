/**
 * 背景蒙版设置：调节图片背景上的蒙版不透明度。
 *
 * Slider 采用官方 ArkUI 组件用法：value/min/max/step + onChange(mode)，
 * 只在拖动结束（End）或点击轨道（Click）时持久化，避免拖动过程中频繁写 prefs。
 * 列表滚动期间切换为 SLIDE_ONLY，避免上下滑 List 时误触 Slider 点击（官方 FAQ faqs-arkui-1107）。
 */
import { AppPreferences, PrefKeys } from '../../app/AppPreferences';
import { AppState } from '../../app/AppState';
import { AppStore } from '../../app/AppStore';
import { Colors, FontSize, Spacing } from '../../common/design/Tokens';

const DEFAULT_MASK_OPACITY: number = 50;

@ComponentV2
export struct BackgroundMaskSetting {
  @Local store: AppStore = AppStore.connect();
  /** 外层设置列表是否正在滚动；滚动时禁止 Slider 点击改值。 */
  @Param isListScrolling: boolean = false;

  private resetMaskOpacity(): void {
    AppState.setBackgroundMaskOpacity(DEFAULT_MASK_OPACITY);
    this.persistMaskOpacity(DEFAULT_MASK_OPACITY);
  }

  private persistMaskOpacity(value: number): void {
    AppPreferences.put(PrefKeys.BackgroundMaskOpacity, value).catch((err: Error) => {
      console.error(`[BackgroundMask] save opacity failed: ${JSON.stringify(err)}`);
    });
  }

  build() {
    Column() {
      Row({ space: Spacing.Md }) {
        SymbolGlyph($r('sys.symbol.circle_lefthalf_inset_filled'))
          .fontSize(24)
          .fontColor([Colors.TextSecondary])
        Text('背景蒙版')
          .fontSize(FontSize.Body)
          .fontColor(Colors.TextPrimary)
          .layoutWeight(1)
        if (this.store.backgroundMaskOpacity !== DEFAULT_MASK_OPACITY) {
          Button('恢复默认', { type: ButtonType.Capsule })
            .fontSize(FontSize.Caption)
            .fontColor(Colors.TextSecondary)
            .backgroundColor(Colors.SurfaceHigh)
            .height(28)
            .padding({ left: Spacing.Sm, right: Spacing.Sm })
            .onClick(() => {
              this.resetMaskOpacity();
            })
        }
        Text(`${this.store.backgroundMaskOpacity}%`)
          .fontSize(FontSize.BodySm)
          .fontColor(Colors.TextSecondary)
      }
      .width('100%')
      .constraintSize({ minHeight: 56 })
      .padding({ left: Spacing.Sm, right: Spacing.Sm })
      .alignItems(VerticalAlign.Center)

      Slider({
        value: this.store.backgroundMaskOpacity,
        min: 0,
        max: 100,
        step: 1,
        style: SliderStyle.InSet
      })
        .width('100%')
        .padding({ left: Spacing.Md, right: Spacing.Md, bottom: Spacing.Sm })
        .blockColor(Colors.Surface)
        .trackColor(Colors.SurfaceHigh)
        .selectedColor(this.store.accentDisplay)
        .sliderInteractionMode(this.isListScrolling ?
          SliderInteraction.SLIDE_ONLY : SliderInteraction.SLIDE_AND_CLICK_UP)
        .onChange((value: number, mode: SliderChangeMode) => {
          AppState.setBackgroundMaskOpacity(value);
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.persistMaskOpacity(this.store.backgroundMaskOpacity);
          }
        })
    }
    .width('100%')
  }
}
