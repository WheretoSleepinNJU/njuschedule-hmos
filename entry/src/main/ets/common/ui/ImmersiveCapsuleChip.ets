/**
 * 标题栏/bottomBuilder 内使用的沉浸光感胶囊。
 *
 * 仅用于已经位于 Navigation/NavDestination 标题栏区域的场景；
 * Button.systemMaterial 的系统材质在这些容器内才会生效。
 */
import { uiMaterial } from '@kit.ArkUI';
import { AppStore } from '../../app/AppStore';
import { CapsuleMetrics, Colors, FontSize, Radius, Spacing } from '../design/Tokens';

const NORMAL_MATERIAL: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
  style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
  interactive: true,
  lightEffect: {},
  applyShadow: false
});

@ComponentV2
export struct ImmersiveCapsuleChip {
  @Local store: AppStore = AppStore.connect();
  @Param label: string = '';
  @Param selected: boolean = false;
  @Param maxWidth: number = CapsuleMetrics.MaxWidth;
  @Event onTap: () => void = () => {
  };

  private selectedMaterial(): uiMaterial.ImmersiveMaterial {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      materialColor: this.store.accentSoft,
      interactive: true,
      lightEffect: {},
      applyShadow: false
    });
  }

  build() {
    Button({ type: ButtonType.Capsule }) {
      Text(this.label)
        .fontSize(FontSize.BodySm)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.selected ? this.store.accentDisplay : Colors.TextSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: this.maxWidth })
    }
    .padding({ left: Spacing.Lg, right: Spacing.Lg, top: Spacing.Sm, bottom: Spacing.Sm })
    // 材质不支持时回退到实色；支持时 systemMaterial 会覆盖背景。
    .backgroundColor(this.selected ? this.store.accentDisplay : Colors.SurfaceHigh)
    .borderRadius(Radius.Round)
    .systemMaterial(this.selected ? this.selectedMaterial() : NORMAL_MATERIAL)
    .accessibilityText(this.label)
    .onClick(() => {
      this.onTap();
    })
  }
}
