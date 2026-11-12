/**
 * 应用外壳路由入口：宽屏首页打开子页面时，先切换到 Split，再等待一帧左右让
 * Navigation 完成模式切换，最后 push 路由。
 *
 * 与官方 CommonAppDevelopment 多设备适配案例一致：
 * Navigation 的 mode 切换有响应时间，直接在 push 过程中切模式会让两个动画重叠。
 */
export interface ShellRouteBridge {
  /** 返回 true 表示刚切换到 Split，调用方需要等待模式切换完成。 */
  enterChild: () => boolean;
  /** 子页面标题栏返回：宽屏回到首页时需要先退回 Stack 再 pop。 */
  exitChild: () => void;
}

const MODE_SWITCH_DELAY: number = 20;

export class ShellRouter {
  private static bridge: ShellRouteBridge | undefined = undefined;

  static setBridge(bridge: ShellRouteBridge): void {
    ShellRouter.bridge = bridge;
  }

  private static async prepareChild(): Promise<void> {
    const needsDelay: boolean = ShellRouter.bridge !== undefined && ShellRouter.bridge.enterChild();
    if (!needsDelay) {
      return;
    }
    await new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, MODE_SWITCH_DELAY);
    });
  }

  static async push(stack: NavPathStack, name: string, param: Object | null = null,
    onPop?: (popInfo: PopInfo) => void): Promise<void> {
    await ShellRouter.prepareChild();
    stack.pushPathByName(name, param, onPop);
  }

  static async pushOnce(stack: NavPathStack, name: string,
    param: Object | null = null): Promise<void> {
    await ShellRouter.prepareChild();
    try {
      stack.pushPath(new NavPathInfo(name, param), { launchMode: LaunchMode.POP_TO_SINGLETON });
    } catch (err) {
      console.warn(`[ShellRouter] push ${name} failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 同级页面：已有子页面时直接替换当前页，不把旧页面留在返回栈里。
   * 用于课程编辑这类“任意课程都是同级”的页面，返回时直接回到主页面。
   */
  static async replaceOrPush(stack: NavPathStack, name: string,
    param: Object | null = null): Promise<void> {
    await ShellRouter.prepareChild();
    if (stack.getAllPathName().length > 0) {
      stack.replacePathByName(name, param);
      return;
    }
    stack.pushPathByName(name, param);
  }

  /** 子页面标题栏返回的统一入口。 */
  static back(): void {
    if (ShellRouter.bridge !== undefined) {
      ShellRouter.bridge.exitChild();
    }
  }
}
