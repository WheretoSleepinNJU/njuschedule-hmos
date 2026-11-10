/**
 * 子页面导航栈解析：`HdsNavDestination.onReady` 之前用外壳传入的 `@Param pageStack`，
 * onReady 之后用 NavDestinationContext.pathStack。各子页统一调用，避免重复实现。
 */
export function resolveNavStack(stack: NavPathStack | null, fallback: NavPathStack): NavPathStack {
  return stack === null ? fallback : stack;
}

/**
 * 单例页面入栈：同名页面已在栈中时不再重复叠加。
 *
 * 使用 Navigation 官方 LaunchMode.POP_TO_SINGLETON：
 * - 栈中已有同名 NavDestination 时，移除其上方的页面并回到该页面；
 * - 没有同名页面时按普通 push 处理。
 *
 * 适用于设置等“主从/层级”页面，避免连续点击同一条目造成无限返回。
 */
export function pushPageOnce(stack: NavPathStack, name: string, param: Object | null = null): void {
  try {
    stack.pushPath(new NavPathInfo(name, param), { launchMode: LaunchMode.POP_TO_SINGLETON });
  } catch (err) {
    console.warn(`[NavStack] push ${name} failed: ${JSON.stringify(err)}`);
  }
}
