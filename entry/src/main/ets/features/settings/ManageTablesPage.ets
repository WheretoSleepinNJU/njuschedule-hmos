/**
 * 课表管理页（路由名 `tables`）。
 *
 * 功能（对齐旧版 lib/Pages/ManageTable/ManageTableView.dart）：
 * - 列出全部课表（CourseTableRepository.getAll）
 * - 新建 / 重命名（命名弹窗，数据保留在 data 字段）
 * - 删除（CourseTableRepository.delete 级联删除课程，AlertDialog 二次确认）
 * - 切换当前课表（AppPreferences.setTableId + AppState.setCurrentTable，返回时外壳自动刷新）
 */
import {
  HdsNavDestination,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitleBarOptions,
  IconStyleMode
} from '@kit.UIDesignKit';
import { AppPreferences } from '../../app/AppPreferences';
import { AppState } from '../../app/AppState';
import { Colors, FontSize, HdsMetrics, Spacing } from '../../common/design/Tokens';
import { Feedback } from '../../common/ui/Feedback';
import { AppCard } from '../../common/ui/AppCard';
import { EmptyState } from '../../common/ui/EmptyState';
import { BadgeTone, StatusBadge } from '../../common/ui/StatusBadge';
import { CourseTable } from '../../data/models/Models';
import { CourseTableRepository } from '../../data/CourseTableRepository';
import { AppStore } from '../../app/AppStore';
import { hdsSubPageTitleBar } from '../../common/ui/HdsSubPage';
import { TableNameDialog } from './TableNameDialog';

@ComponentV2
export struct ManageTablesPage {
  /** V2 全局 Store。 */
  @Local store: AppStore = AppStore.connect();
  @Param pageStack: NavPathStack = new NavPathStack();

  @Local tables: CourseTable[] = [];
  @Local loading: boolean = true;

  private scroller: Scroller = new Scroller();
  /** promptAction.openCustomDialog 返回的弹窗 id（-1 表示未打开）。 */
  private dialogId: number = -1;

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

  private async closeNameDialog(): Promise<void> {
    if (this.dialogId < 0) {
      return;
    }
    const id: number = this.dialogId;
    this.dialogId = -1;
    try {
      this.getUIContext().getPromptAction().closeCustomDialog(id);
    } catch (err) {
      console.warn(`[Tables] close name dialog failed: ${JSON.stringify(err)}`);
    }
  }

  /** openCustomDialog 的 builder 必须是组件内 @Builder 的箭头包装（官方 FAQ，否则闪退）。 */
  @Builder
  private nameDialogContent(title: string, initialName: string, confirmText: string,
    onSubmit: (name: string) => void) {
    TableNameDialog({
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

  private async openNameDialog(title: string, initialName: string, confirmText: string,
    onSubmit: (name: string) => void): Promise<void> {
    await this.closeNameDialog();
    try {
      this.dialogId = await this.getUIContext().getPromptAction().openCustomDialog({
        builder: () => {
          this.nameDialogContent(title, initialName, confirmText, onSubmit);
        },
        autoCancel: true,
        alignment: DialogAlignment.Center
      });
    } catch (err) {
      console.error(`[Tables] open name dialog failed: ${JSON.stringify(err)}`);
    }
  }

  private openCreateDialog(): void {
    this.openNameDialog('新建课表', '', '创建', (name: string) => {
      this.createTable(name);
    });
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

  @Builder
  private tableCard(table: CourseTable): void {
    AppCard({ contentPadding: 0 }) {
      Row({ space: Spacing.Md }) {
        Column({ space: 4 }) {
          Row({ space: Spacing.Sm }) {
            Text(table.name)
              .fontSize(FontSize.Body)
              .fontWeight(table.id === this.store.tableId ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(Colors.TextPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '70%' })
            if (table.id === this.store.tableId) {
              StatusBadge({ text: '当前使用', tone: BadgeTone.Primary })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(table.id === this.store.tableId ? '正在显示这张课表' : '点击切换为当前课表')
            .fontSize(FontSize.BodySm)
            .fontColor(Colors.TextTertiary)
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('重命名')
          .fontSize(FontSize.BodySm)
          .fontColor(this.store.accentDisplay)
          .padding({ left: Spacing.Sm, right: Spacing.Sm, top: Spacing.Xs, bottom: Spacing.Xs })
          .onClick(() => {
            this.openRenameDialog(table);
          })

        if (table.id !== this.store.tableId) {
          Row() {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(18)
              .fontColor([Colors.Error])
          }
          .width(36)
          .height(36)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.confirmDelete(table);
          })
        }
      }
      .width('100%')
      .padding({ left: Spacing.Lg, right: Spacing.Md, top: Spacing.Md, bottom: Spacing.Md })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.switchTable(table);
      })
    }
  }

  private titleBarOptions(): HdsNavigationTitleBarOptions {
    const menu: HdsNavigationMenuContentOptions = {
      value: [{
        content: {
          icon: $r('sys.symbol.plus'),
          type: IconStyleMode.NORMAL,
          action: () => {
            this.openCreateDialog();
          }
        }
      }]
    };
    return hdsSubPageTitleBar('课表管理', '', menu);
  }

  build() {
    HdsNavDestination() {
      Column() {

      Scroll(this.scroller) {
        Column() {
          Column({ space: Spacing.Md }) {
            Text('点击课表可切换为当前课表；删除课表会同时删除其中的全部课程。')
              .fontSize(FontSize.Caption)
              .fontColor(Colors.TextTertiary)
              .width('100%')

            if (this.loading) {
              Row() {
                LoadingProgress()
                  .width(28)
                  .height(28)
                  .color(this.store.accentDisplay)
              }
              .width('100%')
              .height(120)
              .justifyContent(FlexAlign.Center)
            } else if (this.tables.length === 0) {
              EmptyState({
                title: '还没有课表',
                description: '点击右上角「+」新建课表后即可添加课程'
              })
            } else {
              ForEach(this.tables, (table: CourseTable) => {
                this.tableCard(table)
              }, (table: CourseTable) => table.id.toString())
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: 800 })
          .padding({
            left: Spacing.Lg,
            right: Spacing.Lg,
            top: HdsMetrics.contentTopInset(px2vp(this.store.windowTopInset)) + Spacing.Md,
            bottom: Spacing.Xxxl
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.Background)
    }
    .titleBar(this.titleBarOptions())
    .bindToScrollable([this.scroller])
  }
}
