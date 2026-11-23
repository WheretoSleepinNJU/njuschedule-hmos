/**
 * 教务导入入口页（路由名 `import`，无路由参数）。
 *
 * 对应旧版 `lib/Pages/Import/ImportView.dart` 的「在线学校列表」部分：
 * - 学校列表改为从随包 rawfile 读取（见 SchoolRepository）；
 * - 旧版三条内置路径（Cer/JW/XK）远端开关当前全关，这里只保留 BE 学校列表路径；
 * - 旧版没有搜索框，这里新增按 title / pinyin / description 过滤；
 * - 追加旧版 `getDemoClasses` 的触达入口（示例课表，数据层在 `data/DemoData.ets`）。
 *
 * 根节点是 `HdsNavDestination`：标题栏统一由 common/ui/HdsSubPage 的系统标题栏提供
 * （动态模糊 / 返回键 / 安全区由 HDS 处理），本页只负责内容。
 */
import { resolveNavStack } from '../../common/NavStackResolver';
import { HdsNavDestination, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit';
import { AppState } from '../../app/AppState';
import { Colors, FontSize, HdsMetrics, Spacing } from '../../common/design/Tokens';
import { Feedback } from '../../common/ui/Feedback';
import { AppStore } from '../../app/AppStore';
import { hdsSubPageBackPressed, hdsSubPageTitleBar, hdsTitleBarBottomBar } from '../../common/ui/HdsSubPage';
import { EmptyState } from '../../common/ui/EmptyState';
import { DemoData } from '../../data/DemoData';
import { ShellRouter } from '../../common/ShellRouter';
import { ImportWebParam } from './ImportParams';
import { SchoolConfig } from './SchoolConfig';
import { SchoolRepository } from './SchoolRepository';
import { SettingsItemDivider, SettingsItemGroup, SettingsRow } from '../../common/ui/SettingsListItems';
import { SEARCH_MATERIAL } from '../../common/ui/SystemMaterial';

const ROUTE_IMPORT_WEB: string = 'import-web';
/** 标题栏搜索框区域高度。 */
const TITLE_SEARCH_HEIGHT: number = 52;

class SchoolLetterGroup {
  letter: string = '#';
  schools: SchoolConfig[] = [];

  constructor(letter: string) {
    this.letter = letter;
  }
}

@ComponentV2
export struct ImportView {
  /** V2 全局 Store（主题色 / 避让区 / 当前课表）。 */
  @Local store: AppStore = AppStore.connect();

  /** 外壳注入的导航栈；正常也走 onReady 里的 pathStack。 */
  @Param pageStack: NavPathStack = new NavPathStack();

  @Local schools: SchoolConfig[] = [];
  @Local letterGroups: SchoolLetterGroup[] = [];
  @Local keyword: string = '';
  @Local loading: boolean = true;
  @Local loadError: string = '';
  @Local demoBusy: boolean = false;
  /** 分组内容版本：变化时强制 ForEach 重建 ListItemGroup，避免大 key 拼接。 */
  private letterGroupsVersion: number = 0;

  private stack: NavPathStack | null = null;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadSchools(false);
  }

  private navStack(): NavPathStack {
    return resolveNavStack(this.stack, this.pageStack);
  }


  private async loadSchools(forceReload: boolean): Promise<void> {
    this.loading = true;
    this.loadError = '';
    try {
      const list: SchoolConfig[] = await SchoolRepository.loadAll(forceReload);
      this.schools = SchoolRepository.sortedByPinyin(list);
      this.rebuildLetterGroups();
    } catch (err) {
      this.schools = [];
      this.letterGroups = [];
      this.loadError = err instanceof Error ? err.message : '读取学校列表失败';
      console.error(`[Import] 学校列表加载失败: ${this.loadError}`);
    } finally {
      this.loading = false;
    }
  }

  /** 关键字变化/列表加载后重建分组；# 置顶，其余按字母排序。 */
  private rebuildLetterGroups(keyword: string = this.keyword): void {
    const groups: SchoolLetterGroup[] = [];
    const byLetter: Map<string, SchoolLetterGroup> = new Map<string, SchoolLetterGroup>();
    const schools: SchoolConfig[] = SchoolRepository.search(this.schools, keyword);
    for (let i = 0; i < schools.length; i++) {
      const letter: string = schools[i].tagIndex;
      let group: SchoolLetterGroup | undefined = byLetter.get(letter);
      if (group === undefined) {
        group = new SchoolLetterGroup(letter);
        byLetter.set(letter, group);
        groups.push(group);
      }
      group.schools.push(schools[i]);
    }
    groups.sort((a: SchoolLetterGroup, b: SchoolLetterGroup): number => {
      const rankA: number = a.letter === '#' ? 0 : a.letter.charCodeAt(0) - 64;
      const rankB: number = b.letter === '#' ? 0 : b.letter.charCodeAt(0) - 64;
      return rankA - rankB;
    });
    this.letterGroups = groups;
    this.letterGroupsVersion += 1;
  }

  private openSchool(school: SchoolConfig): void {
    if (!school.isUsable()) {
      Feedback.toast(this.getUIContext(), '该学校当前不可用');
      return;
    }
    ShellRouter.push(this.navStack(), ROUTE_IMPORT_WEB, new ImportWebParam(school));
  }

  /** 旧版 getDemoClasses 的入口：创建 Demo 课表并切为当前课表。 */
  private async createDemoTable(): Promise<void> {
    if (this.demoBusy) {
      return;
    }
    this.demoBusy = true;
    try {
      const tableId: number = await DemoData.createDemoTable();
      await AppState.switchTable(tableId);
      Feedback.toast(this.getUIContext(), '示例课表已创建，已切换到该课表');
      this.navStack().pop();
    } catch (err) {
      const message: string = err instanceof Error ? err.message : '未知错误';
      console.error(`[Import] 创建示例课表失败: ${message}`);
      Feedback.toast(this.getUIContext(), '创建示例课表失败');
    } finally {
      this.demoBusy = false;
    }
  }

  // ---- UI ----

  @Builder
  private quickStartSection(): void {
    ListItem() {
      SettingsItemGroup({ title: '快速开始' }) {
        SettingsRow({
          icon: $r('sys.symbol.book_pages'),
          title: '没有教务账号？先用示例课表看看',
          subtitle: '创建一张 Demo 课表，立刻体验周视图与课程块',
          trailingText: this.demoBusy ? '创建中…' : '',
          showArrow: !this.demoBusy,
          onTap: () => {
            this.createDemoTable();
          }
        })
        SettingsItemDivider()
        SettingsRow({
          icon: $r('sys.symbol.qrcode'),
          title: '从分享码导入',
          subtitle: '粘贴其他设备分享的 ncs://qr 课表编码',
          onTap: () => {
            ShellRouter.push(this.navStack(), 'import-code', null);
          }
        })
      }
    }
  }

  @Builder
  private titleBarSearch() {
    Column() {
      Search({ value: this.keyword, placeholder: '搜索学校名称或拼音' })
        .width('100%')
        .height(40)
        .backgroundColor(Color.Transparent)
        .systemMaterial(SEARCH_MATERIAL)
        .textFont({ size: FontSize.Body })
        .onChange((value: string) => {
          this.keyword = value;
          this.rebuildLetterGroups(value);
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: Spacing.Md, right: Spacing.Md, top: Spacing.Xs, bottom: Spacing.Xs })
  }

  private titleBarOptions(): HdsNavigationTitleBarOptions {
    const options: HdsNavigationTitleBarOptions =
      hdsSubPageTitleBar('教务导入', '选择学校并登录教务系统，进入课表页后自动导入');
    hdsTitleBarBottomBar(options, TITLE_SEARCH_HEIGHT, () => {
      this.titleBarSearch();
    });
    return options;
  }

  @Builder
  private schoolRow(school: SchoolConfig) {
    SettingsRow({
      icon: $r('sys.symbol.book'),
      title: school.title,
      subtitle: school.description,
      trailingText: school.disabled ? '暂不可用' : '',
      showArrow: !school.disabled,
      onTap: () => {
        this.openSchool(school);
      }
    })
  }

  @Builder
  private schoolLetterHeader(letter: string) {
    Text(letter)
      .fontSize(FontSize.BodySm)
      .fontWeight(FontWeight.Medium)
      .fontColor(Colors.TextTertiary)
      .width('100%')
      .height(Spacing.Xxxl)
      .padding({ left: Spacing.Md })
      .backgroundColor(Colors.Background)
  }

  @Builder
  private schoolList() {
    // 直接读取 @Local letterGroups；不要通过 @Builder 参数传入数组，避免参数变化不重绘。
    ForEach(this.letterGroups, (group: SchoolLetterGroup) => {
      ListItemGroup({ header: this.schoolLetterHeader(group.letter) }) {
        ListItem() {
          SettingsItemGroup() {
            ForEach(group.schools, (school: SchoolConfig, index: number) => {
              if (index > 0) {
                SettingsItemDivider()
              }
              this.schoolRow(school)
            }, (school: SchoolConfig) => `${school.pinyin}|${school.title}`)
          }
        }
      }
    }, (group: SchoolLetterGroup) => `school-letter-${group.letter}-${this.letterGroupsVersion}`)
  }


  build() {
    HdsNavDestination() {
      Column() {
        List({ space: Spacing.Md, scroller: this.scroller }) {
          // 顶部留白放在滚动内容里，标题栏才能照常采样并做模糊。
          ListItem() {
            Row()
              .width('100%')
              .height(HdsMetrics.contentTopInset(px2vp(this.store.windowTopInset)) +
                TITLE_SEARCH_HEIGHT + Spacing.Md)
          }

          this.quickStartSection()

          if (this.loading) {
            ListItem() {
              Column({ space: Spacing.Sm }) {
                LoadingProgress()
                  .width(30)
                  .height(30)
                  .color(this.store.accentDisplay)
                Text('正在读取学校列表…')
                  .fontSize(FontSize.BodySm)
                  .fontColor(Colors.TextTertiary)
              }
              .width('100%')
              .height(160)
              .justifyContent(FlexAlign.Center)
            }
          } else if (this.loadError !== '') {
            ListItem() {
              EmptyState({
                title: '学校列表加载失败',
                description: this.loadError,
                icon: $r('sys.symbol.exclamationmark_circle'),
                actionText: '重新加载',
                onAction: () => {
                  this.loadSchools(true);
                }
              })
            }
          } else if (this.letterGroups.length === 0) {
            ListItem() {
              EmptyState({
                title: '没有匹配的学校',
                description: '换个关键字试试，或清空搜索框查看全部学校',
                icon: $r('sys.symbol.magnifyingglass')
              })
            }
          } else {
            this.schoolList()
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: 800 })
        .layoutWeight(1)
        .height('100%')
        .padding({
          left: Spacing.Md,
          right: Spacing.Md,
          bottom: Spacing.Xxxl
        })
        .clip(false)
        .cachedCount(3, true)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .sticky(StickyStyle.Header)
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(Colors.Background)
    }
    .titleBar(this.titleBarOptions())
    .onBackPressed(hdsSubPageBackPressed)
    .bindToScrollable([this.scroller])
    .onReady((ctx: NavDestinationContext) => {
      this.stack = ctx.pathStack;
    })
  }

}
