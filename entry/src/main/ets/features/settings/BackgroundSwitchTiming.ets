/**
 * 背景切换时机设置：退出课表页 / 自定义天数。
 *
 * 只负责时机偏好（prefs 持久化、天数选择器）与对应设置行；
 * 实际的换图逻辑在 `BackgroundImage.rotateOnLeave()`。
 */
import { CapsuleSegmentButtonV2, ColorMetrics, LengthMetrics, SegmentButtonV2Items } from '@kit.ArkUI';
import { AppPreferences, PrefKeys } from '../../app/AppPreferences';
import { AppStore } from '../../app/AppStore';
import { Colors, FontSize, Spacing } from '../../common/design/Tokens';
import { applyTextPickerAccent } from '../../common/ui/TextPickerStyle';
import { SettingsItemDivider, SettingsRow } from '../../common/ui/SettingsListItems';

const MAX_SWITCH_DAYS: number = 365;

@ComponentV2
export struct BackgroundSwitchTiming {
  @Local store: AppStore = AppStore.connect();
  /** 0=退出课表页，1=自定义天数。 */
  @Local switchModeIndex: number = 0;
  @Local switchDays: number = 1;
  /** 切换时机分段按钮（与深浅色选择器同款胶囊样式）。 */
  private switchModeItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '退出课表页' },
    { text: '自定义天数' }
  ]);

  aboutToAppear(): void {
    this.loadSwitchSettings();
  }

  private async loadSwitchSettings(): Promise<void> {
    try {
      const mode: string = await AppPreferences.getString(PrefKeys.BackgroundSwitchMode, 'exit');
      this.switchModeIndex = mode === 'days' ? 1 : 0;
      this.switchDays = Math.max(1,
        Math.min(MAX_SWITCH_DAYS, await AppPreferences.getInt(PrefKeys.BackgroundSwitchDays, 1)));
    } catch (err) {
      console.error(`[BackgroundSwitch] load settings failed: ${JSON.stringify(err)}`);
    }
  }

  private async applySwitchMode(index: number): Promise<void> {
    this.switchModeIndex = index;
    try {
      await AppPreferences.put(PrefKeys.BackgroundSwitchMode, index === 1 ? 'days' : 'exit');
    } catch (err) {
      console.error(`[BackgroundSwitch] save mode failed: ${JSON.stringify(err)}`);
    }
  }

  private openSwitchDaysPicker(): void {
    const choices: string[] = [];
    for (let day = 1; day <= MAX_SWITCH_DAYS; day++) {
      choices.push(`${day} 天`);
    }
    this.getUIContext().showTextPickerDialog(applyTextPickerAccent(this.store, {
      range: choices,
      selected: this.switchDays - 1,
      canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const index: number = Array.isArray(result.index) ? result.index[0] : result.index as number;
        this.persistSwitchDays(index + 1);
      }
    }));
  }

  private async persistSwitchDays(days: number): Promise<void> {
    this.switchDays = days;
    try {
      await AppPreferences.put(PrefKeys.BackgroundSwitchDays, days);
    } catch (err) {
      console.error(`[BackgroundSwitch] save days failed: ${JSON.stringify(err)}`);
    }
  }

  build() {
    Column() {
      Column() {
        Row({ space: Spacing.Md }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(24)
            .fontColor([Colors.TextSecondary])
          Column({ space: 2 }) {
            Text('切换时机')
              .fontSize(FontSize.Body)
              .fontColor(Colors.TextPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .constraintSize({ minHeight: 56 })
        .alignItems(VerticalAlign.Center)

        Row() {
          CapsuleSegmentButtonV2({
            items: this.switchModeItems,
            selectedIndex: this.switchModeIndex,
            $selectedIndex: (index: number): void => {
              this.applySwitchMode(index);
            },
            buttonBackgroundColor: ColorMetrics.resourceColor(Colors.SurfaceHigh),
            itemSelectedBackgroundColor: ColorMetrics.resourceColor(Colors.Surface),
            itemFontColor: ColorMetrics.resourceColor(Colors.TextSecondary),
            itemSelectedFontColor: ColorMetrics.resourceColor(Colors.TextPrimary),
            itemFontSize: LengthMetrics.fp(FontSize.BodySm),
            itemSelectedFontSize: LengthMetrics.fp(FontSize.BodySm)
          })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: Spacing.Sm, right: Spacing.Sm, bottom: Spacing.Md })

      if (this.switchModeIndex === 1) {
        SettingsItemDivider()
        SettingsRow({
          icon: $r('sys.symbol.calendar_badge_clock'),
          title: '切换间隔',
          trailingText: `${this.switchDays} 天`,
          onTap: () => {
            this.openSwitchDaysPicker();
          }
        })
      }
    }
    .width('100%')
  }
}
