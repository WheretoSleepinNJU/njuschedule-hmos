/**
 * 自定义外观页（路由名 `more-settings`）。
 *
 * 汇总所有外观相关设置：
 * - 外观模式：跟随系统 / 浅色 / 深色（Appearance.apply）
 * - 主题色：9 个预设 + 自定义 #RRGGBB（ThemeAccent）
 * - 课表背景：内置预设 + 自定义多图（多选轮播、切换时机、长按重命名/删除）
 * - 课程样式：重置课程配色（ColorPool.shuffle）
 *
 * 分享与迁移、危险操作已外迁到设置初始页（SettingsView）。
 */
import { HdsNavDestination } from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import { AppPreferences } from '../../app/AppPreferences';
import { AppState } from '../../app/AppState';
import { CapsuleSegmentButtonV2, ColorMetrics, LengthMetrics, SegmentButtonV2Items } from '@kit.ArkUI';
import { AppStore } from '../../app/AppStore';
import { hdsSubPageBackPressed, hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import { ThemeAccent } from '../../app/ThemeAccent';
import { Appearance } from '../../app/Appearance';
import { Colors, FontSize, HdsMetrics, Radius, Spacing } from '../../common/design/Tokens';
import { Feedback } from '../../common/ui/Feedback';
import { NameDialogController } from '../../common/ui/NameDialogController';
import { BackgroundImage, CustomBackground } from '../../data/BackgroundImage';
import { CustomBackgroundCard, PresetBackgroundCard } from './BackgroundCards';
import { BackgroundSwitchTiming } from './BackgroundSwitchTiming';
import { ThemeColorCard } from './ThemeColorCard';
import { NameDialog } from './NameDialog';
import { WidgetData } from '../../data/WidgetData';
import { ColorPool } from '../../data/ColorPool';
import { CourseColorPalette, CourseColorPalettes } from '../../data/CourseColorPalettes';
import { SettingsItemDivider, SettingsItemGroup, SettingsRow, SettingsSwitchRow } from '../../common/ui/SettingsListItems';

/** 主题配色卡片的名称与一句话风格说明（顺序与 ThemeAccent.PRESETS 一致）。 */
const THEME_NAMES: string[] = ['清爽蓝', '松雾绿', '深海蓝', '南哪紫', '绯红', '樱花粉', '青雾', '雾霭蓝', '曜石灰'];
const THEME_DESCS: string[] = ['默认清爽蓝', '低饱和松绿', '沉稳深海蓝', '南京哪个大学？', '强烈绯红', '柔和樱粉', '冷静青灰', '淡雅蓝紫', '中性石墨灰'];

@ComponentV2
export struct MoreSettingsPage {
  /** V2 全局 Store（主题色 / 外观模式 / 背景图 / 课表选择）。 */
  @Local store: AppStore = AppStore.connect();
  @Local customHexInput: string = '';
  /** 用户自定义背景图（追加在内置预设之后）。 */
  @Local customImages: CustomBackground[] = [];
  /** 外观模式分段按钮（系统预置 CapsuleSegmentButtonV2 单选胶囊样式）。 */
  private appearanceItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '跟随系统' },
    { text: '浅色' },
    { text: '深色' }
  ]);

  /** 当前课程配色池 id。 */
  @Local selectedPaletteId: string = CourseColorPalettes.DEFAULT_ID;

  private scroller: Scroller = new Scroller();
  private imageDialog: NameDialogController = new NameDialogController();

  aboutToAppear(): void {
    this.customHexInput = ThemeAccent.currentCustomHex();
    this.loadPaletteSelection();
    this.loadCustomImages();
  }

  aboutToDisappear(): void {
    this.closeImageNameDialog();
  }

  private async loadPaletteSelection(): Promise<void> {
    this.selectedPaletteId = await ColorPool.getPaletteId();
  }

  private async selectPalette(id: string): Promise<void> {
    if (id === this.selectedPaletteId) {
      return;
    }
    try {
      await ColorPool.setPalette(id);
      this.selectedPaletteId = id;
      await AppState.bumpDataRevision();
      Feedback.toast(this.getUIContext(), `已切换配色池：${CourseColorPalettes.get(id).name}`);
    } catch (err) {
      console.error(`[MoreSettings] switch palette failed: ${JSON.stringify(err)}`);
      Feedback.toast(this.getUIContext(), '切换配色池失败');
    }
  }

  @Builder
  private paletteCard(palette: CourseColorPalette) {
    Column({ space: Spacing.Sm }) {
      Row() {
        ForEach(palette.colors.slice(0, 6), (color: string, index: number) => {
          Row()
            .layoutWeight(1)
            .height(18)
            .backgroundColor(color)
        }, (color: string, index: number) => `${palette.id}-swatch-${index}`)
      }
      .width('100%')
      .height(18)
      .borderRadius(Radius.Sm)
      .clip(true)

      Row() {
        Text(palette.name)
          .fontSize(FontSize.Body)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.TextPrimary)
        Blank()
        if (this.selectedPaletteId === palette.id) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(14)
            .fontColor([this.store.accentDisplay])
        }
      }
      .width('100%')

      Text(palette.subtitle)
        .fontSize(FontSize.Caption)
        .fontColor(Colors.TextTertiary)
        .maxLines(1)
        .width('100%')
    }
    .width('100%')
    .padding(Spacing.Md)
    .backgroundColor(Colors.Surface)
    .borderRadius(Radius.Lg)
    .border({
      width: this.selectedPaletteId === palette.id ? 2 : 1,
      color: this.selectedPaletteId === palette.id ? this.store.accentDisplay : Colors.OutlineLight
    })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.selectPalette(palette.id);
    })
    .clickEffect({ level: ClickEffectLevel.LIGHT })
  }

  private async resetCourseColors(): Promise<void> {
    try {
      await ColorPool.shuffle();
      await AppState.bumpDataRevision();
      Feedback.toast(this.getUIContext(), '已重置课程配色');
    } catch (err) {
      console.error(`[MoreSettings] 重置配色失败: ${JSON.stringify(err)}`);
      Feedback.toast(this.getUIContext(), '重置配色失败');
    }
  }

  @Builder
  private appearanceSection(): void {
    ListItem() {
      SettingsItemGroup({ title: '外观' }) {
        Row() {
          CapsuleSegmentButtonV2({
            items: this.appearanceItems,
            selectedIndex: this.store.themeModeIndex,
            $selectedIndex: (index: number): void => {
              this.applyAppearance(index);
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
        .padding({ left: Spacing.Md, right: Spacing.Md, top: Spacing.Md, bottom: Spacing.Md })

        SettingsItemDivider({ startMargin: 12 })

        SettingsSwitchRow({
          icon: $r('sys.symbol.sun_max'),
          title: '深色模式自动提亮主题色',
          isOn: this.store.autoDarkAccent,
          onToggle: (isOn: boolean) => {
            this.setAutoDarkAccent(isOn);
          }
        })
      }
    }
  }

  /** 深色模式自动提亮主题色开关：写 Store + prefs，并刷新桌面小组件配色。 */
  private async setAutoDarkAccent(value: boolean): Promise<void> {
    AppState.setAutoDarkAccent(value);
    try {
      await AppPreferences.setAutoDarkAccent(value);
    } catch (err) {
      console.error(`[MoreSettings] 保存自动提亮主题色失败: ${JSON.stringify(err)}`);
    }
    WidgetData.write().catch((err: Error) => {
      console.warn(`[MoreSettings] refresh widgets failed: ${JSON.stringify(err)}`);
    });
  }

  /** 切换深浅色：setColorMode 立即生效（资源限定词自动切换），并持久化。 */
  private applyAppearance(index: number): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    Appearance.apply(index, context).catch((err: Error) => {
      console.error(`[Settings] apply appearance failed: ${JSON.stringify(err)}`);
    });
  }

  @Builder
  private themeSection(): void {
    ListItem() {
      SettingsItemGroup({ title: '主题配色' }) {
        Column({ space: Spacing.Md }) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(ThemeAccent.PRESETS, (hex: string, index: number) => {
              ThemeColorCard({
                hex: hex,
                index: index,
                name: THEME_NAMES[index],
                desc: THEME_DESCS[index],
                custom: false,
                onTap: () => {
                  this.applyTheme(index);
                }
              })
            }, (hex: string, index: number) => `theme-card-${index}`)
            ThemeColorCard({
              hex: '',
              index: ThemeAccent.CUSTOM_INDEX,
              name: '自定义配色',
              desc: '自由选择',
              custom: true,
              onTap: () => {
                this.selectCustomColor();
              }
            })
          }
          .width('100%')

          if (this.store.themeAccentIndex === ThemeAccent.CUSTOM_INDEX) {
            Column({ space: Spacing.Sm }) {
              SettingsItemDivider({ startMargin: 12 })
              Row({ space: Spacing.Sm }) {
                Text('自定义配色')
                  .fontSize(FontSize.Body)
                  .fontColor(Colors.TextPrimary)
                Blank()
                Text(this.store.themeCustomColor)
                  .fontSize(FontSize.Caption)
                  .fontColor(Colors.TextTertiary)
              }
              .width('100%')

              Row({ space: Spacing.Sm }) {
                TextInput({ text: this.customHexInput, placeholder: '自定义色 #RRGGBB' })
                  .height(36)
                  .layoutWeight(1)
                  .fontSize(FontSize.BodySm)
                  .backgroundColor(Colors.SurfaceHigh)
                  .borderRadius(Radius.Sm)
                  .onChange((value: string) => {
                    this.customHexInput = value;
                  })
                Button('应用')
                  .height(36)
                  .fontSize(FontSize.BodySm)
                  .backgroundColor(this.store.accentSoft)
                  .fontColor(this.store.accentDisplay)
                  .onClick(() => {
                    this.applyCustomTheme();
                  })
              }
              .width('100%')
            }
            .width('100%')
            .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.Smooth }))
          }
        }
        .width('100%')
        .padding({ left: Spacing.Md, right: Spacing.Md, top: Spacing.Md, bottom: Spacing.Md })
        .alignItems(HorizontalAlign.Start)
      }
    }
  }

  /** 主题切换统一用显式动画（与编辑课程时段一致），驱动自定义编辑区展开/收起。 */
  private animateThemeChange(apply: () => void): void {
    this.getUIContext().animateTo({ duration: 300, curve: Curve.Smooth }, apply);
  }

  /** 应用自定义色：动画切换 + 成功后回填输入框（可附带提示）。 */
  private applyCustomColor(hex: string, successToast: string = ''): void {
    const normalized: string = hex.trim().toUpperCase();
    this.animateThemeChange(() => {
      ThemeAccent.applyCustom(normalized).then((ok: boolean) => {
        if (!ok) {
          return;
        }
        this.customHexInput = normalized;
        if (successToast !== '') {
          Feedback.toast(this.getUIContext(), successToast);
        }
      }).catch((err: Error) => {
        console.error(`[Settings] apply custom theme failed: ${JSON.stringify(err)}`);
      });
    });
  }

  /** 点自定义配色卡片：有历史自定义色则恢复，否则用当前预设色作为起点并出现输入条目。 */
  private selectCustomColor(): void {
    if (this.store.themeAccentIndex === ThemeAccent.CUSTOM_INDEX) {
      return;
    }
    const saved: string = ThemeAccent.currentCustomHex();
    this.applyCustomColor(saved !== '' ? saved : ThemeAccent.preset(this.store.themeAccentIndex));
  }

  /** 应用输入框里的自定义色（#RRGGBB）。 */
  private applyCustomTheme(): void {
    const hex: string = this.customHexInput.trim().toUpperCase();
    if (!ThemeAccent.isHex(hex)) {
      Feedback.toast(this.getUIContext(), '请输入合法的颜色值，如 #6A2C91');
      return;
    }
    this.applyCustomColor(hex, '已应用自定义主题色');
  }

  /** 切换预设强调色：写 AppStore + prefs 持久化，带动画收合自定义编辑区。 */
  private applyTheme(index: number): void {
    this.animateThemeChange(() => {
      ThemeAccent.apply(index).catch((err: Error) => {
        console.error(`[Settings] apply theme failed: ${JSON.stringify(err)}`);
      });
    });
  }

  @Builder
  private backgroundStrip(): void {
    Scroll() {
      Row({ space: Spacing.Md }) {
        ForEach(BackgroundImage.PRESETS, (name: string) => {
          PresetBackgroundCard({
            name: name,
            onTap: () => {
              this.toggleBackground(BackgroundImage.presetKey(name));
            }
          })
        }, (name: string) => `bg-${name}`)
        ForEach(this.customImages, (item: CustomBackground) => {
          CustomBackgroundCard({
            item: item,
            onTap: () => {
              this.toggleBackground(BackgroundImage.customKey(item.path));
            },
            onRename: () => {
              this.openImageRenameDialog(item);
            },
            onDelete: () => {
              this.confirmDeleteCustomImage(item);
            }
          })
        }, (item: CustomBackground) => `custom-${item.path}-${item.name}`)
      }
      .padding({ left: Spacing.Md, right: Spacing.Md, top: Spacing.Md, bottom: Spacing.Md })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
  }

  @Builder
  private backgroundSection(): void {
    ListItem() {
      SettingsItemGroup({ title: '课表背景' }) {
        this.backgroundStrip()

        SettingsItemDivider({ startMargin: 12 })

        SettingsRow({
          icon: $r('sys.symbol.picture'),
          title: '添加自定义图片',
          showArrow: false,
          subtitle: '从相册选择并裁剪，追加到背景列表',
          onTap: () => {
            this.addCustomImage();
          }
        })

        SettingsItemDivider()
        BackgroundSwitchTiming()
      }
    }
  }

  private async loadCustomImages(): Promise<void> {
    try {
      this.customImages = await BackgroundImage.loadCustom();
    } catch (err) {
      console.error(`[MoreSettings] load custom backgrounds failed: ${JSON.stringify(err)}`);
    }
  }

  /** 点击缩略图切换轮播选中状态（首张选中时会立即成为当前背景）。 */
  private async toggleBackground(key: string): Promise<void> {
    try {
      await BackgroundImage.toggleSelected(key);
    } catch (err) {
      console.error(`[MoreSettings] toggle background failed: ${JSON.stringify(err)}`);
      Feedback.toast(this.getUIContext(), '切换背景失败');
    }
  }

  private async addCustomImage(): Promise<void> {
    try {
      const added: CustomBackground | null = await BackgroundImage.addCustom();
      if (added === null) {
        return;
      }
      await this.loadCustomImages();
      Feedback.toast(this.getUIContext(), `已添加「${added.name}」`);
    } catch (err) {
      console.error(`[MoreSettings] add custom background failed: ${JSON.stringify(err)}`);
      Feedback.toast(this.getUIContext(), '选择图片失败');
    }
  }

  private async renameCustomImage(item: CustomBackground, name: string): Promise<void> {
    try {
      await BackgroundImage.renameCustom(item.path, name);
      await this.loadCustomImages();
      Feedback.toast(this.getUIContext(), '已重命名图片');
    } catch (err) {
      console.error(`[MoreSettings] rename custom background failed: ${JSON.stringify(err)}`);
      Feedback.toast(this.getUIContext(), '重命名失败');
    }
  }

  private confirmDeleteCustomImage(item: CustomBackground): void {
    Feedback.confirmDanger(this.getUIContext(), '删除背景图片',
      `将删除「${item.name}」这张背景图片，此操作无法恢复。`, '删除', () => {
        this.deleteCustomImage(item);
      });
  }

  private async deleteCustomImage(item: CustomBackground): Promise<void> {
    try {
      await BackgroundImage.deleteCustom(item);
      await this.loadCustomImages();
      Feedback.toast(this.getUIContext(), '已删除背景图片');
    } catch (err) {
      console.error(`[MoreSettings] delete custom background failed: ${JSON.stringify(err)}`);
      Feedback.toast(this.getUIContext(), '删除图片失败');
    }
  }

  private closeImageNameDialog(): Promise<void> {
    return this.imageDialog.close(this.getUIContext());
  }

  /** openCustomDialog 的 builder 必须是组件内 @Builder 的箭头包装（官方 FAQ，否则闪退）。 */
  @Builder
  private imageNameDialogContent(item: CustomBackground) {
    NameDialog({
      title: '重命名图片',
      initialName: item.name,
      confirmText: '保存',
      placeholder: '请输入图片名称',
      onSubmit: (name: string): void => {
        this.closeImageNameDialog();
        this.renameCustomImage(item, name);
      },
      onCancel: (): void => {
        this.closeImageNameDialog();
      }
    })
  }

  private openImageRenameDialog(item: CustomBackground): Promise<void> {
    return this.imageDialog.open(this.getUIContext(), () => {
      this.imageNameDialogContent(item);
    });
  }

  @Builder
  private styleSection(): void {
    ListItem() {
      SettingsItemGroup({ title: '课程样式' }) {
        Column({ space: Spacing.Md }) {
          Row() {
            Text('课程配色池')
              .fontSize(FontSize.Body)
              .fontWeight(FontWeight.Medium)
              .fontColor(Colors.TextPrimary)
            Blank()
            Text(CourseColorPalettes.get(this.selectedPaletteId).name)
              .fontSize(FontSize.Caption)
              .fontColor(Colors.TextTertiary)
          }
          .width('100%')

          Grid() {
            ForEach(CourseColorPalettes.LIST, (palette: CourseColorPalette) => {
              GridItem() {
                this.paletteCard(palette)
              }
            }, (palette: CourseColorPalette) => `palette-${palette.id}`)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(Spacing.Md)
          .rowsGap(Spacing.Md)
          .width('100%')
        }
        .width('100%')
        .padding({ left: Spacing.Md, right: Spacing.Md, top: Spacing.Md, bottom: Spacing.Md })
        .alignItems(HorizontalAlign.Start)

        SettingsItemDivider({ startMargin: 12 })

        SettingsRow({
          icon: $r('sys.symbol.paintpalette'),
          title: '重置课程颜色',
          showArrow: false,
          subtitle: '在当前配色池中重新随机分配未自定义颜色的课程',
          onTap: () => {
            this.resetCourseColors();
          }
        })
      }
    }
  }

  build() {
    HdsNavDestination() {
      Column() {
        List({ space: Spacing.Md, scroller: this.scroller }) {
          this.appearanceSection()
          this.themeSection()
          this.backgroundSection()
          this.styleSection()
        }
        .width('100%')
        .constraintSize({ maxWidth: 800 })
        .layoutWeight(1)
        .padding({
          left: Spacing.Md,
          right: Spacing.Md,
          top: HdsMetrics.contentTopInset(px2vp(this.store.windowTopInset)) + Spacing.Md,
          bottom: Spacing.Xxxl + HdsMetrics.FloatingTabBarClearance
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
    .titleBar(hdsSubPageTitleBar('自定义外观'))
    .onBackPressed(hdsSubPageBackPressed)
    .bindToScrollable([this.scroller])
  }

}
