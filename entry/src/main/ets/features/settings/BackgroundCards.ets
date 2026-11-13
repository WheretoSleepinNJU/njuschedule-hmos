/**
 * 课表背景缩略图卡片：内置预设与自定义图片共用缩略图、选中描边与点击回弹；
 * 自定义图片额外支持长按/右键菜单（重命名、删除）。
 */
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { AppStore } from '../../app/AppStore';
import { Colors, FontSize, Radius, Spacing } from '../../common/design/Tokens';
import { BackgroundImage, CustomBackground } from '../../data/BackgroundImage';

const THUMB_WIDTH: number = 72;
const THUMB_HEIGHT: number = 108;

/** 缩略图本体：图片 + 选中强调色描边 + 点击回弹。 */
@ComponentV2
struct BackgroundThumb {
  @Local store: AppStore = AppStore.connect();
  @Param source: ResourceStr = '';
  @Param selected: boolean = false;
  @Event onTap: () => void = () => {
  };

  build() {
    Stack() {
      // Image 默认开启长按拖拽（拖到小艺会触发系统识图），会和点击/长按菜单冲突。
      Image(this.source)
        .width(THUMB_WIDTH)
        .height(THUMB_HEIGHT)
        .objectFit(ImageFit.Cover)
        .borderRadius(Radius.Md)
        .draggable(false)
      if (this.selected) {
        Row()
          .width(THUMB_WIDTH)
          .height(THUMB_HEIGHT)
          .borderRadius(Radius.Md)
          .border({ width: 2, color: this.store.accentDisplay })
      }
    }
    .width(THUMB_WIDTH)
    .height(THUMB_HEIGHT)
    .onClick(() => {
      this.onTap();
    })
    .clickEffect({ level: ClickEffectLevel.LIGHT })
  }
}

/** 内置预设缩略图：点击切换选中状态。 */
@ComponentV2
export struct PresetBackgroundCard {
  @Local store: AppStore = AppStore.connect();
  @Param name: string = '';
  @Event onTap: () => void = () => {
  };

  private isSelected(): boolean {
    return this.store.backgroundSelectedKeys.indexOf(BackgroundImage.presetKey(this.name)) >= 0;
  }

  build() {
    Column({ space: Spacing.Xs }) {
      BackgroundThumb({
        source: $rawfile(`backgrounds/${this.name}`),
        selected: this.isSelected(),
        onTap: () => {
          this.onTap();
        }
      })
      Text(BackgroundImage.presetLabel(this.name))
        .fontSize(FontSize.Caption)
        .fontColor(this.isSelected() ? this.store.accentDisplay : Colors.TextTertiary)
    }
  }
}

/** 自定义背景缩略图：点击切换选中状态，长按/右键弹出重命名、删除菜单。 */
@ComponentV2
export struct CustomBackgroundCard {
  @Local store: AppStore = AppStore.connect();
  @Param item: CustomBackground = new CustomBackground();
  @Event onTap: () => void = () => {
  };
  @Event onRename: () => void = () => {
  };
  @Event onDelete: () => void = () => {
  };

  private isSelected(): boolean {
    return this.store.backgroundSelectedKeys.indexOf(BackgroundImage.customKey(this.item.path)) >= 0;
  }

  // 触发方式由框架传入；长按和右键共用同一菜单，保留参数以匹配 CustomBuilderT<ResponseType>。
  @Builder
  private menu(_responseType: ResponseType): void {
    Menu() {
      MenuItem({
        content: '重命名',
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.pencil_line'))
      })
        .onClick(this.onRename)
      MenuItem({
        content: '删除',
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash'))
          .fontColor([Colors.Error])
      })
        .onClick(this.onDelete)
    }
  }

  build() {
    Column({ space: Spacing.Xs }) {
      BackgroundThumb({
        source: BackgroundImage.thumbnailUri(this.item.path),
        selected: this.isSelected(),
        onTap: () => {
          this.onTap();
        }
      })
      Text(this.item.name)
        .fontSize(FontSize.Caption)
        .fontColor(this.isSelected() ? this.store.accentDisplay : Colors.TextTertiary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(THUMB_WIDTH)
        .textAlign(TextAlign.Center)
    }
    .bindContextMenuWithResponse(this.menu, {
      preview: MenuPreviewMode.IMAGE
    })
  }
}
