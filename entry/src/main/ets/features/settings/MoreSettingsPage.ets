/**
 * 自定义外观页（路由名 `more-settings`）。
 *
 * 汇总所有外观相关设置：
 * - 外观模式：跟随系统 / 浅色 / 深色（Appearance.apply）
 * - 主题色：9 个预设 + 自定义 #RRGGBB（ThemeAccent）
 * - 课表背景：内置预设 / 相册选择 / 移除（BackgroundImage）
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
import { hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import { ThemeAccent } from '../../app/ThemeAccent';
import { Appearance } from '../../app/Appearance';
import { Colors, FontSize, HdsMetrics, Radius, Spacing } from '../../common/design/Tokens';
import { Feedback } from '../../common/ui/Feedback';
import { BackgroundImage } from '../../data/BackgroundImage';
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
  /** 当前选中的内置背景（本地状态：点击后立即反馈勾选，不依赖 AppStorage 的异步刷新）。 */
  @Local selectedPreset: string = '';
  @Local customHexInput: string = '';
  /** 外观模式分段按钮（系统预置 CapsuleSegmentButtonV2 单选胶囊样式）。 */
  private appearanceItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '跟随系统' },
    { text: '浅色' },
    { text: '深色' }
  ]);

  /** 当前课程配色池 id。 */
  @Local selectedPaletteId: string = CourseColorPalettes.DEFAULT_ID;

  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.selectedPreset = BackgroundImage.currentPreset();
    this.customHexInput = ThemeAccent.currentCustomHex();
    this.loadPaletteSelection();
  }

  @Monitor('store.backgroundImagePath')
  private onBackgroundPathChanged(_monitor: IMonitor): void {
    this.selectedPreset = BackgroundImage.currentPreset();
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
        Stack({ alignContent: Alignment.BottomEnd }) {
          Column({ space: Spacing.Sm }) {
            this.themePreview(hex)
            Text(THEME_NAMES[index])
              .fontSize(FontSize.Body)
              .fontWeight(FontWeight.Medium)
              .fontColor(Colors.TextPrimary)
              .width('100%')
              .maxLines(1)
            Text(THEME_DESCS[index])
              .fontSize(FontSize.Caption)
              .fontColor(Colors.TextTertiary)
              .width('100%')
              .maxLines(1)
          }
          .width('100%')
          .padding(Spacing.Md)
          .backgroundColor(Colors.Surface)
          .borderRadius(Radius.Xl)
          .border({
            width: this.store.themeAccentIndex === index ? 2 : 1,
            color: this.store.themeAccentIndex === index ? this.store.accentDisplay : Colors.OutlineLight
          })
          .alignItems(HorizontalAlign.Start)
          .onClick(() => {
            this.applyTheme(index);
          })

          if (this.store.themeAccentIndex === index) {
            Row() {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(14)
                .fontColor([Colors.TextOnPrimary])
            }
            .width(24)
            .height(24)
            .borderRadius(Radius.Round)
            .backgroundColor(this.store.accentDisplay)
            .justifyContent(FlexAlign.Center)
            .margin({ right: Spacing.Md, bottom: Spacing.Sm })
          }
        }
        .width('48%')
        .margin({ bottom: Spacing.Md })
      }, (hex: string, index: number) => `theme-card-${index}`)
    }
    .width('100%')


          SettingsItemDivider({ startMargin: 12 })
      Column({ space: Spacing.Sm }) {
        Row({ space: Spacing.Sm }) {
          Text('自定义配色')
            .fontSize(FontSize.Body)
            .fontColor(Colors.TextPrimary)
          Blank()
          Text(this.store.themeAccentIndex === ThemeAccent.CUSTOM_INDEX && ThemeAccent.currentCustomHex() !== '' ?
            ThemeAccent.currentCustomHex() : `当前 ${ThemeAccent.preset(this.store.themeAccentIndex)}`)
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
        }
        .width('100%')
        .padding({ left: Spacing.Md, right: Spacing.Md, top: Spacing.Md, bottom: Spacing.Md })
        .alignItems(HorizontalAlign.Start)
      }
    }
  }

  /** 主题配色卡片的示意图：用该配色的深浅变体拼出类似「聊天气泡」的示意。 */
  @Builder
  private themePreview(hex: string) {
    Column({ space: 5 }) {
      Row({ space: 6 }) {
        Row()
          .width(28)
          .height(10)
          .borderRadius(5)
          .backgroundColor(Colors.Surface)
        Row()
          .width(28)
          .height(10)
          .borderRadius(5)
          .backgroundColor(hex)
          .opacity(0.25)
        Blank()
        Row()
          .width(34)
          .height(18)
          .borderRadius(9)
          .backgroundColor(hex)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 6 }) {
        Row()
          .width(56)
          .height(8)
          .borderRadius(4)
          .backgroundColor(hex)
        Blank()
        Row()
          .width(26)
          .height(26)
          .borderRadius(13)
          .backgroundColor(hex)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row()
        .width(44)
        .height(8)
        .borderRadius(4)
        .backgroundColor(hex)
        .opacity(0.25)
    }
    .width('100%')
    .height(76)
    .padding(10)
    .backgroundColor(Colors.SurfaceHigh)
    .borderRadius(Radius.Md)
  }

  /** 应用自定义色（#RRGGBB）。 */
  private applyCustomTheme(): void {
    const hex: string = this.customHexInput.trim();
    if (!ThemeAccent.isHex(hex)) {
      Feedback.toast(this.getUIContext(), '请输入合法的颜色值，如 #6A2C91');
      return;
    }
    ThemeAccent.applyCustom(hex).then((ok: boolean) => {
      if (ok) {
        this.customHexInput = hex.toUpperCase();
        Feedback.toast(this.getUIContext(), '已应用自定义主题色');
      }
    }).catch((err: Error) => {
      console.error(`[Settings] apply custom theme failed: ${JSON.stringify(err)}`);
    });
  }

  /** 切换强调色：写 AppStore（@Trace 全量重绘）+ prefs 持久化。 */
  private applyTheme(index: number): void {
    ThemeAccent.apply(index).catch((err: Error) => {
      console.error(`[Settings] apply theme failed: ${JSON.stringify(err)}`);
    });
  }

  @Builder
  private backgroundSection(): void {
    ListItem() {
      SettingsItemGroup({ title: '课表背景' }) {
        Column() {
          Row({ space: Spacing.Md }) {
            ForEach(BackgroundImage.PRESETS, (name: string) => {
              Column({ space: Spacing.Xs }) {
                Stack() {
                  Image($rawfile(`backgrounds/${name}`))
                    .width(72)
                    .height(108)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(Radius.Md)
                  if (this.selectedPreset === name) {
                    Row() {
                      SymbolGlyph($r('sys.symbol.checkmark'))
                        .fontSize(16)
                        .fontColor([Colors.TextOnPrimary])
                    }
                    .width(72)
                    .height(108)
                    .borderRadius(Radius.Md)
                    .backgroundColor(Colors.Scrim)
                    .justifyContent(FlexAlign.Center)
                    .border({ width: 2, color: this.store.accentDisplay })
                  }
                }
                .width(72)
                .height(108)

                Text(BackgroundImage.presetLabel(name))
                  .fontSize(FontSize.Caption)
                  .fontColor(this.selectedPreset === name ? Colors.Primary : Colors.TextTertiary)
              }
              .onClick(() => {
                this.applyPreset(name);
              })
            }, (name: string) => `bg-${name}`)
          }
          .width('100%')
          .padding({ left: Spacing.Md, right: Spacing.Md, top: Spacing.Md, bottom: Spacing.Md })
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('100%')

        SettingsItemDivider({ startMargin: 12 })

        SettingsRow({
          icon: $r('sys.symbol.picture'),
          title: this.store.backgroundImagePath === '' ? '从相册选择并裁剪' : '从相册更换并裁剪',
          showArrow: false,
          subtitle: this.store.backgroundImagePath === '' ? '在系统图库中裁剪/旋转后使用' : '当前已设置背景图',
          onTap: () => {
            this.pickBackground();
          }
        })
        if (this.store.backgroundImagePath !== '') {
          SettingsItemDivider()
          SettingsRow({
            icon: $r('sys.symbol.trash'),
            title: '移除背景图片',
            showArrow: false,
            danger: true,
            onTap: () => {
              this.clearBackground();
            }
          })
        }
      }
    }
  }

  private async applyPreset(name: string): Promise<void> {
    const previous: string = this.selectedPreset;
    // 先更新本地选中态，点击后立即显示勾选
    this.selectedPreset = name;
    try {
      await BackgroundImage.applyPreset(name);
      Feedback.toast(this.getUIContext(), `已切换为「${BackgroundImage.presetLabel(name)}」背景`);
    } catch (err) {
      this.selectedPreset = previous;
      console.error(`[MoreSettings] apply preset background failed: ${JSON.stringify(err)}`);
      Feedback.toast(this.getUIContext(), '切换背景失败');
    }
  }

  private async pickBackground(): Promise<void> {
    try {
      const ok: boolean = await BackgroundImage.pick();
      if (ok) {
        this.selectedPreset = '';
        Feedback.toast(this.getUIContext(), '背景图已更新');
      }
    } catch (err) {
      console.error(`[MoreSettings] pick background failed: ${JSON.stringify(err)}`);
      Feedback.toast(this.getUIContext(), '选择图片失败');
    }
  }

  private async clearBackground(): Promise<void> {
    try {
      await BackgroundImage.clear();
      this.selectedPreset = '';
      Feedback.toast(this.getUIContext(), '已移除背景图');
    } catch (err) {
      console.error(`[MoreSettings] clear background failed: ${JSON.stringify(err)}`);
    }
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
          bottom: Spacing.Xxxl
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
    .bindToScrollable([this.scroller])
  }

}
