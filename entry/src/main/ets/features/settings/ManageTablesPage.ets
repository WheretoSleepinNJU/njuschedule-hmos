/**
 * 课表管理页（路由名 `tables`）。
 *
 * 功能（对齐旧版 lib/Pages/ManageTable/ManageTableView.dart）：
 * - 列出全部课表（CourseTableRepository.getAll）
 * - 右上角 +：教务导入（与课程页共用 import 入口）/ 新建课表菜单
 * - 重命名（命名弹窗，数据保留在 data 字段）
 * - 删除（CourseTableRepository.delete 级联删除课程，AlertDialog 二次确认）
 * - 切换当前课表（卡片下拉菜单触发，原地刷新列表，不退出页面）
 * - 长按拖动交换课表顺序（参考 HarmonyOS_Samples/list-exchange，V2 重写）
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
import { NameDialogController } from '../../common/ui/NameDialogController';
import { menuItemDividerStyle } from '../../common/ui/MenuDivider';

/** 课表行高度与行内图标尺寸；拖拽阈值、分隔线缩进和卡片高度统一引用。 */
const TABLE_ROW_HEIGHT: number = 56;
const TABLE_ROW_ICON_SIZE: number = 24;

/** 拖动中的行浮起阴影 / 普通行无阴影。 */
const DRAG_SHADOW: ShadowOptions = { radius: 16, color: '#33000000', offsetX: 0, offsetY: 4 };
const REST_SHADOW: ShadowOptions = { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 };
const DRAG_SCALE: number = 1.04;
const NEIGHBOR_SHRINK: number = 0.06;

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
        .fontSize(TABLE_ROW_ICON_SIZE)
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
    .constraintSize({ minHeight: TABLE_ROW_HEIGHT })
    .padding({ left: Spacing.Md, right: Spacing.Sm })
    .backgroundColor(Color.Transparent)
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

  // ---- 列表项交换（参考 HarmonyOS_Samples/list-exchange，按本项目 V2 重写） ----
  /** 正在拖动的课表 id；-1 表示无拖动。 */
  @Local draggingId: number = -1;
  /** 拖动项相对落点的偏移；交换后减去一行高度，保证视觉连续。 */
  @Local dragOffsetY: number = 0;
  /** 已完成的交换累计位移，用于修正 PanGesture 的 offsetY。 */
  @Local dragRefOffsetY: number = 0;
  /** 单张卡片高度，由 onAreaChange 实测；用于交换阈值与位移动画。 */
  private itemHeight: number = TABLE_ROW_HEIGHT;
  private orderDirty: boolean = false;

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

  // ---- 列表项交换 ----

  private indexOfTable(tableId: number): number {
    for (let i = 0; i < this.tables.length; i++) {
      if (this.tables[i].id === tableId) {
        return i;
      }
    }
    return -1;
  }

  private hasTables(): boolean {
    return !this.loading && this.tables.length > 0;
  }

  private beginDrag(table: CourseTable): void {
    if (this.draggingId >= 0) {
      return;
    }
    this.orderDirty = false;
    this.getUIContext().animateTo({ curve: Curve.Friction, duration: 180 }, () => {
      this.draggingId = table.id;
      this.dragOffsetY = 0;
      this.dragRefOffsetY = 0;
    });
  }

  private updateDrag(table: CourseTable, offsetY: number): void {
    if (this.draggingId !== table.id) {
      return;
    }
    const index: number = this.indexOfTable(table.id);
    if (index < 0) {
      return;
    }
    const current: number = offsetY - this.dragRefOffsetY;
    this.dragOffsetY = current;
    const pitch: number = this.itemHeight;
    if (pitch <= 0 || Math.abs(current) <= pitch / 2) {
      return;
    }
    const direction: number = current > 0 ? 1 : -1;
    const target: number = index + direction;
    if (target < 0 || target >= this.tables.length) {
      return;
    }
    const reordered: CourseTable[] = this.tables.slice();
    const moved: CourseTable[] = reordered.splice(index, 1);
    reordered.splice(target, 0, moved[0]);
    this.getUIContext().animateTo({ curve: Curve.Friction, duration: 220 }, () => {
      this.dragOffsetY = current - direction * pitch;
      this.dragRefOffsetY = this.dragRefOffsetY + direction * pitch;
      this.tables = reordered;
      this.orderDirty = true;
    });
  }

  private endDrag(): void {
    if (this.draggingId < 0) {
      return;
    }
    const shouldSave: boolean = this.orderDirty;
    this.orderDirty = false;
    this.getUIContext().animateTo({ curve: Curve.Friction, duration: 220 }, () => {
      this.draggingId = -1;
      this.dragOffsetY = 0;
      this.dragRefOffsetY = 0;
    });
    if (shouldSave) {
      CourseTableRepository.saveOrder(this.tables).catch((err: Error) => {
        console.warn(`[Tables] 保存课表顺序失败: ${JSON.stringify(err)}`);
      });
    }
  }

  /** 拖动项放大，目标方向的相邻项轻微缩小，形成“让位”效果。 */
  private itemScale(table: CourseTable): number {
    if (this.draggingId === table.id) {
      return DRAG_SCALE;
    }
    if (this.draggingId < 0 || this.dragOffsetY === 0) {
      return 1;
    }
    const dragIndex: number = this.indexOfTable(this.draggingId);
    const index: number = this.indexOfTable(table.id);
    if (dragIndex < 0 || index < 0) {
      return 1;
    }
    const direction: number = this.dragOffsetY > 0 ? 1 : -1;
    if (index !== dragIndex + direction) {
      return 1;
    }
    const pitch: number = this.itemHeight;
    const ratio: number = pitch > 0 ? Math.min(1, Math.abs(this.dragOffsetY) / (pitch / 2)) : 0;
    return 1 - NEIGHBOR_SHRINK * ratio;
  }

  /** 大分组卡行间分隔线；行背景已拼出整卡，仅需分隔线。 */
  private listDivider(): ListDividerOptions {
    if (!this.hasTables() || this.tables.length <= 1) {
      return { strokeWidth: 0, color: Colors.OutlineLight };
    }
    return {
      strokeWidth: 1,
      color: Colors.OutlineLight,
      startMargin: Spacing.Md + TABLE_ROW_ICON_SIZE + Spacing.Md,
      endMargin: Spacing.Md
    };
  }

  /**
   * 行背景拼出大分组卡：首行上圆角、末行下圆角，中间行直角；
   * 拖动中的行四角都圆，作为浮起卡片。
   */
  private rowRadius(table: CourseTable): BorderRadiuses {
    if (this.draggingId === table.id) {
      return { topLeft: Radius.Lg, topRight: Radius.Lg, bottomLeft: Radius.Lg, bottomRight: Radius.Lg };
    }
    const index: number = this.indexOfTable(table.id);
    const top: number = index <= 0 ? Radius.Xxl : 0;
    const bottom: number = index === this.tables.length - 1 ? Radius.Xxl : 0;
    return { topLeft: top, topRight: top, bottomLeft: bottom, bottomRight: bottom };
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
          if (this.hasTables()) {
            Row({ space: Spacing.Sm }) {
              Text('全部课表')
                .fontSize(FontSize.BodySm)
                .fontColor(Colors.TextTertiary)
              Blank()
              Text('长按拖动排序')
                .fontSize(FontSize.Caption)
                .fontColor(Colors.TextTertiary)
            }
            .width('100%')
            .constraintSize({ maxWidth: 800 })
            .padding({
              left: Spacing.Md,
              right: Spacing.Md,
              top: HdsMetrics.contentTopInset(px2vp(this.store.windowTopInset)) + Spacing.Md,
              bottom: Spacing.Sm
            })
          }

          List({ space: 0, scroller: this.scroller }) {
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
              // 每行背景拼出官方样例式的大分组卡（首/末行圆角），行间用 List divider。
              // 每张课表独立 ListItem，才能用 translate/scale 做交换动效；参考官方 list-exchange。
              ForEach(this.tables, (table: CourseTable) => {
                ListItem() {
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
                }
                .width('100%')
                .zIndex(this.draggingId === table.id ? 2 : 0)
                .backgroundColor(Colors.Surface)
                .borderRadius(this.rowRadius(table))
                .translate({ y: this.draggingId === table.id ? this.dragOffsetY : 0 })
                .scale({ x: this.itemScale(table), y: this.itemScale(table) })
                .shadow(this.draggingId === table.id ? DRAG_SHADOW : REST_SHADOW)
                .onAreaChange((_oldValue: Area, newValue: Area) => {
                  const height: number = Number(newValue.height);
                  if (height > 0 && this.draggingId < 0) {
                    this.itemHeight = height;
                  }
                })
                .gesture(
                  GestureGroup(GestureMode.Sequence,
                    LongPressGesture()
                      .onAction((_event: GestureEvent) => {
                        this.beginDrag(table);
                      }),
                    PanGesture()
                      .onActionUpdate((event: GestureEvent) => {
                        this.updateDrag(table, event.offsetY);
                      })
                      .onActionEnd((_event: GestureEvent) => {
                        this.endDrag();
                      })
                  ).onCancel(() => {
                    this.endDrag();
                  })
                )
              }, (table: CourseTable) => `${table.id}-${table.name}`)
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: 800 })
          .layoutWeight(1)
          .divider(this.listDivider())
          .padding({
            top: this.hasTables() ? 0 : HdsMetrics.contentTopInset(px2vp(this.store.windowTopInset)) + Spacing.Md
          })
          .margin({ bottom: Spacing.Xxxl + HdsMetrics.FloatingTabBarClearance })
          .clip(false)
          .cachedCount(3, true)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        }
        .width('100%')
        .height('100%')
        .padding({ left: Spacing.Md, right: Spacing.Md })
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
