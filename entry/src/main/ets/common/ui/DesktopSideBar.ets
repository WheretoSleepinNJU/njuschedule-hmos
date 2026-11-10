/** 2in1/PC 侧边导航：图标 + 文字的纵向一级导航。 */
import { AppStore } from '../../app/AppStore';
import { Colors, FontSize, Radius, Spacing } from '../design/Tokens';

@ComponentV2
export struct DesktopSideBar {
  @Local store: AppStore = AppStore.connect();
  @Param labels: string[] = [];
  @Param icons: Resource[] = [];
  @Param activeIndex: number = 0;
  @Event onSelect: (index: number) => void = () => {
  };

  build() {
    Column({ space: 2 }) {
      ForEach(this.labels, (label: string, index: number) => {
        Row() {
          SymbolGlyph(this.icons[index])
            .fontSize(24)
            .fontColor([this.activeIndex === index ? this.store.accentDisplay : Colors.TextSecondary])
            .margin({ left: Spacing.Sm })
          Text(label)
            .fontSize(FontSize.Body)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.activeIndex === index ? this.store.accentDisplay : Colors.TextPrimary)
            .margin({ left: Spacing.Md })
        }
        .width('100%')
        .height(40)
        .borderRadius(Radius.Sm)
        .backgroundColor(this.activeIndex === index ? this.store.accentSoft : Color.Transparent)
        .onClick(() => {
          this.onSelect(index);
        })
      }, (label: string, index: number) => `sidebar-${label}-${index}`)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding({ left: Spacing.Lg, right: Spacing.Lg, top: Spacing.Sm })
    .backgroundColor(Colors.Background)
  }
}
