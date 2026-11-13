/**
 * 背景切换时机设置：退出课表页 / 自定义天数。
 *
 * 只负责时机偏好（prefs 持久化、天数选择器）与对应设置行；
 * 实际的换图逻辑在 `BackgroundImage.rotateOnLeave()`。
 */
import { AppPreferences, PrefKeys } from '../../app/AppPreferences';
import { AppStore } from '../../app/AppStore';
import { Colors, FontSize, Spacing } from '../../common/design/Tokens';
import { applyTextPickerAccent } from '../../common/ui/TextPickerStyle';
import { SettingsItemDivider, SettingsRow } from '../../common/ui/SettingsListItems';
import { menuItemDividerStyle } from '../../common/ui/MenuDivider';

const MAX_SWITCH_DAYS: number = 365;
/** 切换时机选项（下标与 switchModeIndex 一致）。 */
const SWITCH_MODE_LABELS: string[] = ['退出课表页', '自定义天数'];

@ComponentV2
export struct BackgroundSwitchTiming {
  @Local store: AppStore = AppStore.connect();
  /** 0=退出课表页，1=自定义天数。 */
  @Local switchModeIndex: number = 0;
  @Local switchDays: number = 1;

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

  /** 切换时机：显式动画驱动「切换间隔」行展开/收起，偏好异步持久化。 */
  private applySwitchMode(index: number): void {
    if (index === this.switchModeIndex) {
      return;
    }
    this.getUIContext().animateTo({ duration: 300, curve: Curve.Smooth }, () => {
      this.switchModeIndex = index;
    });
    this.persistSwitchMode(index);
  }

  private async persistSwitchMode(index: number): Promise<void> {
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

  @Builder
  private switchModeMenu() {
    Menu() {
      ForEach(SWITCH_MODE_LABELS, (label: string, index: number) => {
        MenuItem({ content: label })
          .onClick(() => {
            this.applySwitchMode(index);
          })
      }, (label: string) => label)
    }
    .menuItemDivider(menuItemDividerStyle())
  }

  build() {
    Column() {
      Row({ space: Spacing.Md }) {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(24)
          .fontColor([Colors.TextSecondary])
        Text('切换时机')
          .fontSize(FontSize.Body)
          .fontColor(Colors.TextPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Row() {
          Text(SWITCH_MODE_LABELS[this.switchModeIndex])
            .fontSize(FontSize.BodySm)
            .fontColor(Colors.TextSecondary)
            .margin({ right: Spacing.Sm })
          SymbolGlyph($r('sys.symbol.arrowtriangle_down_fill'))
            .fontSize(FontSize.Body)
            .fontColor([Colors.TextTertiary])
        }
        .bindMenu(this.switchModeMenu())
      }
      .width('100%')
      .constraintSize({ minHeight: 56 })
      .padding({ left: Spacing.Sm, right: Spacing.Sm })
      .alignItems(VerticalAlign.Center)

      if (this.switchModeIndex === 1) {
        Column() {
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
        .width('100%')
        .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.Smooth }))
      }
    }
    .width('100%')
  }
}
