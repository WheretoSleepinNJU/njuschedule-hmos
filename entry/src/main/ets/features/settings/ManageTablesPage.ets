/**
 * 课表管理页（路由名 `tables`）。
 *
 * 功能（对齐旧版 lib/Pages/ManageTable/ManageTableView.dart）：
 * - 列出全部课表（CourseTableRepository.getAll）
 * - 右上角 +：教务导入（与课程页共用 import 入口）/ 新建课表菜单
 * - 重命名（命名弹窗，数据保留在 data 字段）
 * - 删除（CourseTableRepository.delete 级联删除课程，AlertDialog 二次确认）
 * - 切换当前课表（卡片下拉菜单触发，原地刷新列表，不退出页面）
 */
import {
  HdsNavDestination,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitleBarOptions,
  IconStyleMode
} from '@kit.UIDesignKit';
import { AppState } from '../../app/AppState';
import { Colors, FontSize, HdsMetrics, Radius, Spacing } from '../../common/design/Tokens';
import { Feedback } from '../../common/ui/Feedback';
import { EmptyState } from '../../common/ui/EmptyState';
import { CourseTable } from '../../data/models/Models';
import { CourseTableRepository } from '../../data/CourseTableRepository';
import { AppStore } from '../../app/AppStore';
import { hdsSubPageBackPressed, hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import { ShellRouter } from '../../common/ShellRouter';
import { NameDialog } from './NameDialog';
import { SettingsItemDivider, SettingsItemGroup } from '../../common/ui/SettingsListItems';
import { NameDialogController } from '../../common/ui/NameDialogController';
import { menuItemDividerStyle } from '../../common/ui/MenuDivider';

/**
 * 单张课表卡片：标题 + 右侧「当前使用/点击展开」下拉菜单。
 */
@ComponentV2
struct CourseTableCard {
  @Param table: CourseTable = new CourseTable();
  @Param isCurrent: boolean = false;
  @Event onSwitch: () => void = () => {
  };
  @Event onRename: () => void = () => {
  };
  @Event onDelete: () => void = () => {
  };

  @Builder
  private tableMenu(): void {
    Menu() {
      MenuItem({ content: '切换课表' })
        .enabled(!this.isCurrent)
        .onClick(this.onSwitch)
      MenuItem({ content: '重命名' })
        .onClick(this.onRename)
      MenuItem({ content: '删除课表' })
        .contentFontColor(Colors.Error)
        .onClick(this.onDelete)
    }
    .menuItemDivider(menuItemDividerStyle())
  }

  build() {
    Row({ space: Spacing.Md }) {
      SymbolGlyph($r('sys.symbol.calendar'))
        .fontSize(24)
        .fontColor([Colors.TextSecondary])
      Text(this.table.name)
        .fontSize(FontSize.Body)
        .fontColor(Colors.TextPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      Row({ space: Spacing.Xs }) {
        Text(this.isCurrent ? '当前使用' : '点击展开')
          .fontSize(FontSize.BodySm)
          .fontColor(Colors.TextTertiary)
        SymbolGlyph($r('sys.symbol.arrowtriangle_down_fill'))
          .fontSize(FontSize.Body)
          .fontColor([Colors.TextTertiary])
      }
      .padding(Spacing.Sm)
      .bindMenu(this.tableMenu)
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({ left: Spacing.Sm, right: Spacing.Sm })
    .backgroundColor(Colors.Surface)
    .borderRadius(Radius.Xl)
    .alignItems(VerticalAlign.Center)
  }
}

@ComponentV2
export struct ManageTablesPage {
  /** V2 全局 Store。 */
  @Local store: AppStore = AppStore.connect();
  @Local pageStack: NavPathStack = new NavPathStack();

  @Local tables: CourseTable[] = [];
  @Local loading: boolean = true;
  /** 标题栏「+」展开菜单的显隐（bindMenu 绑定）。 */
  @Local addMenuOpen: boolean = false;

  private scroller: Scroller = new Scroller();
  private nameDialog: NameDialogController = new NameDialogController();

  aboutToAppear(): void {
    this.loadTables();
  }

  aboutToDisappear(): void {
    this.closeNameDialog();
  }

  /** 教务导入等外部数据变化后自动刷新列表，无需退出页面再进入。 */
  @Monitor('store.dataRevision')
  private onDataRevisionChanged(_monitor: IMonitor): void {
    this.loadTables();
  }

  private async loadTables(): Promise<void> {
    try {
      this.tables = await CourseTableRepository.getAll();
    } catch (err) {
      console.error(`[Tables] 读取课表列表失败: ${JSON.stringify(err)}`);
    } finally {
      this.loading = false;
    }
  }

  // ---- 弹窗 ----

  private closeNameDialog(): Promise<void> {
    return this.nameDialog.close(this.getUIContext());
  }

  /** openCustomDialog 的 builder 必须是组件内 @Builder 的箭头包装（官方 FAQ，否则闪退）。 */
  @Builder
  private nameDialogContent(title: string, initialName: string, confirmText: string,
    onSubmit: (name: string) => void) {
    NameDialog({
      title: title,
      initialName: initialName,
      confirmText: confirmText,
      onSubmit: (name: string): void => {
        this.closeNameDialog();
        onSubmit(name);
      },
      onCancel: (): void => {
        this.closeNameDialog();
      }
    })
  }

  private openNameDialog(title: string, initialName: string, confirmText: string,
    onSubmit: (name: string) => void): Promise<void> {
    return this.nameDialog.open(this.getUIContext(), () => {
      this.nameDialogContent(title, initialName, confirmText, onSubmit);
    });
  }

  private openCreateDialog(): void {
    this.openNameDialog('新建课表', '', '创建', (name: string) => {
      this.createTable(name);
    });
  }

  /** 标题栏「+」菜单：教务导入（与课程页共用 import 入口）/ 新建课表。 */
  private addMenuItems(): MenuElement[] {
    return [
      {
        value: '教务导入',
        icon: $r('sys.symbol.book_pages'),
        action: () => {
          this.addMenuOpen = false;
          ShellRouter.push(this.pageStack, 'import', null);
        }
      },
      {
        value: '添加课表',
        icon: $r('sys.symbol.plus'),
        action: () => {
          this.addMenuOpen = false;
          this.openCreateDialog();
        }
      }
    ];
  }

  private openRenameDialog(table: CourseTable): void {
    this.openNameDialog('重命名课表', table.name, '保存', (name: string) => {
      this.renameTable(table.id, name);
    });
  }

  // ---- 数据操作 ----

  private async switchTableData(tableId: number): Promise<void> {
    try {
      await AppState.switchTable(tableId);
    } catch (err) {
      console.error(`[Tables] 切换课表失败: ${JSON.stringify(err)}`);
    }
  }

  private async createTable(name: string): Promise<void> {
    try {
      const inserted: CourseTable = await CourseTableRepository.insert(new CourseTable(name, ''));
      if (inserted.id > 0) {
        await this.switchTableData(inserted.id);
        Feedback.toast(this.getUIContext(), '已新建课表并切换');
      }
    } catch (err) {
      console.error(`[Tables] 新建课表失败: ${JSON.stringify(err)}`);
      Feedback.toast(this.getUIContext(), '新建课表失败');
    }
    await this.loadTables();
  }

  private async renameTable(tableId: number, name: string): Promise<void> {
    try {
      const table: CourseTable | null = await CourseTableRepository.getById(tableId);
      if (table === null) {
        return;
      }
      table.name = name;
      await CourseTableRepository.update(table);
      await AppState.bumpDataRevision();
      Feedback.toast(this.getUIContext(), '已重命名课表');
    } catch (err) {
      console.error(`[Tables] 重命名课表失败: ${JSON.stringify(err)}`);
      Feedback.toast(this.getUIContext(), '重命名失败');
    }
    await this.loadTables();
  }

  private confirmDelete(table: CourseTable): void {
    Feedback.confirmDanger(this.getUIContext(), '删除课表', `将删除课表「${table.name}」及其中的全部课程，此操作无法恢复。`, '删除', () => {
      this.deleteTable(table.id);
    });
  }

  private async deleteTable(tableId: number): Promise<void> {
    try {
      await CourseTableRepository.delete(tableId);
      const remaining: CourseTable[] = await CourseTableRepository.getAll();
      if (remaining.length === 0) {
        // 至少保留一张课表（旧版启动兜底同样会建默认课表）。
        await CourseTableRepository.ensureDefaultTable();
        const tables: CourseTable[] = await CourseTableRepository.getAll();
        if (tables.length > 0) {
          await this.switchTableData(tables[0].id);
        }
      } else if (tableId === this.store.tableId) {
        await this.switchTableData(remaining[0].id);
      } else {
        await AppState.bumpDataRevision();
      }
      Feedback.toast(this.getUIContext(), '已删除课表');
    } catch (err) {
      console.error(`[Tables] 删除课表失败: ${JSON.stringify(err)}`);
      Feedback.toast(this.getUIContext(), '删除课表失败');
    }
    await this.loadTables();
  }

  private async switchTable(table: CourseTable): Promise<void> {
    if (table.id === this.store.tableId) {
      return;
    }
    await this.switchTableData(table.id);
    Feedback.toast(this.getUIContext(), `已切换到「${table.name}」`);
  }

  // ---- UI ----

  private titleBarOptions(): HdsNavigationTitleBarOptions {
    const menu: HdsNavigationMenuContentOptions = {
      value: [{
        content: {
          icon: $r('sys.symbol.plus'),
          type: IconStyleMode.NORMAL,
          action: () => {
            this.addMenuOpen = !this.addMenuOpen;
          }
        }
      }]
    };
    return hdsSubPageTitleBar('课表管理', '', menu);
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column() {
          List({ space: Spacing.Md, scroller: this.scroller }) {
            if (this.loading) {
              ListItem() {
                Row() {
                  LoadingProgress()
                    .width(28)
                    .height(28)
                    .color(this.store.accentDisplay)
                }
                .width('100%')
                .height(120)
                .justifyContent(FlexAlign.Center)
              }
            } else if (this.tables.length === 0) {
              ListItem() {
                EmptyState({
                  title: '还没有课表',
                  description: '点击右上角「+」从教务导入或新建课表'
                })
              }
            } else {
              ListItem() {
                SettingsItemGroup({ title: '全部课表' }) {
                  ForEach(this.tables, (table: CourseTable, index: number) => {
                    if (index > 0) {
                      SettingsItemDivider()
                    }
                    CourseTableCard({
                      table: table,
                      isCurrent: table.id === this.store.tableId,
                      onSwitch: () => {
                        this.switchTable(table);
                      },
                      onRename: () => {
                        this.openRenameDialog(table);
                      },
                      onDelete: () => {
                        this.confirmDelete(table);
                      }
                    })
                    // ForEach 按 key 复用组件：重命名后 id 不变，key 带上名称才会重建卡片。
                  }, (table: CourseTable, _index: number) => `${table.id}-${table.name}`)
                }
              }
            }
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

        // 标题栏「+」的展开菜单：透明锚点贴合标题栏右上角（与课程页同一做法）。
        Row()
          .width(1)
          .height(1)
          .margin({
            top: HdsMetrics.contentTopInset(px2vp(this.store.windowTopInset)) - 2,
            right: 32
          })
          .bindMenu(this.addMenuOpen, this.addMenuItems(), {
            placement: Placement.BottomRight,
            onDisappear: () => {
              this.addMenuOpen = false;
            }
          })
      }
      .width('100%')
      .height('100%')
    }
    .titleBar(this.titleBarOptions())
    .onBackPressed(hdsSubPageBackPressed)
    .bindToScrollable([this.scroller])
    .onReady((ctx: NavDestinationContext) => {
      this.pageStack = ctx.pathStack;
    })
  }

}
