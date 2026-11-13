/**
 * 课表管理页（路由名 `tables`）。
 *
 * 功能（对齐旧版 lib/Pages/ManageTable/ManageTableView.dart）：
 * - 列出全部课表（CourseTableRepository.getAll）
 * - 右上角 +：教务导入（与课程页共用 import 入口）/ 新建课表菜单
 * - 重命名（命名弹窗，数据保留在 data 字段）
 * - 删除（CourseTableRepository.delete 级联删除课程，AlertDialog 二次确认）
 * - 切换当前课表（AppPreferences.setTableId + AppState.setCurrentTable，返回时外壳自动刷新）
 */
import {
  HdsNavDestination,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitleBarOptions,
  IconStyleMode
} from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { AppState } from '../../app/AppState';
import { Colors, HdsMetrics, Spacing } from '../../common/design/Tokens';
import { Feedback } from '../../common/ui/Feedback';
import { EmptyState } from '../../common/ui/EmptyState';
import { CourseTable } from '../../data/models/Models';
import { CourseTableRepository } from '../../data/CourseTableRepository';
import { AppStore } from '../../app/AppStore';
import { hdsSubPageBackPressed, hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import { ShellRouter } from '../../common/ShellRouter';
import { IS_2IN1 } from '../../common/DeviceType';
import { NameDialog } from './NameDialog';
import { SettingsItemDivider, SettingsItemGroup, SettingsRow } from '../../common/ui/SettingsListItems';
import { NameDialogController } from '../../common/ui/NameDialogController';

/**
 * 单张课表卡片。
 *
 * 独立组件持有自己的 @Builder 菜单，才能把方法引用直接传给
 * bindContextMenuWithResponse（其参数类型为 CustomBuilderT<ResponseType>）。
 * 不要把内联箭头函数传给该接口：运行时不会被识别为合法菜单构造器，
 * 表现为长按/右键都没有菜单。
 */
@ComponentV2
struct CourseTableCard {
  @Param table: CourseTable = new CourseTable();
  @Param isCurrent: boolean = false;
  @Event onTap: () => void = () => {
  };
  @Event onRename: () => void = () => {
  };
  @Event onDelete: () => void = () => {
  };

  // 触发方式由框架传入；当前长按和右键使用相同菜单，保留参数以匹配 CustomBuilderT<ResponseType>。
  @Builder
  private tableMenu(_responseType: ResponseType): void {
    Menu() {
      MenuItem({
        content: '重命名',
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.pencil_line'))
      })
        .onClick(this.onRename)
      if (!this.isCurrent) {
        MenuItem({
          content: '删除课表',
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash'))
            .fontColor([Colors.Error])
        })
          .onClick(this.onDelete)
      }
    }
  }

  private subtitleText(): string {
    const editHint: string = IS_2IN1 ? '右键编辑' : '长按编辑';
    return this.isCurrent ? `当前使用，${editHint}` : `点击切换为当前课表，${editHint}`;
  }

  build() {
    Stack() {
      SettingsRow({
        icon: $r('sys.symbol.calendar'),
        title: this.table.name,
        subtitle: this.subtitleText(),
        trailingText: this.isCurrent ? '当前' : '',
        onTap: this.onTap
      })
    }
    .width('100%')
    .bindContextMenuWithResponse(this.tableMenu, {
      preview: MenuPreviewMode.IMAGE
    })
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
    this.pageStack.pop();
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
                      onTap: () => {
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
