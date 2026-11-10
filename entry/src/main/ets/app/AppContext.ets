/**
 * 应用级 Context 持有者。
 *
 * relationalStore / preferences 都需要 Context，数据层不直接依赖 UI，因此由
 * EntryAbility.onCreate 注入一次，数据层通过 `AppContext.get()` 取用。
 */
import { common } from '@kit.AbilityKit';

export class AppContext {
  private static abilityContext: common.UIAbilityContext | null = null;

  static init(context: common.UIAbilityContext): void {
    AppContext.abilityContext = context;
  }

  static get(): common.UIAbilityContext {
    const ctx: common.UIAbilityContext | null = AppContext.abilityContext;
    if (ctx === null) {
      throw new Error('AppContext 未初始化：EntryAbility.onCreate 必须先调用 AppContext.init');
    }
    return ctx;
  }
}
