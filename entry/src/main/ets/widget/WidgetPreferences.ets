/**
 * 小组件使用的用户首选项访问。
 *
 * FormExtension 与主应用是不同进程，普通 Preferences 实例会缓存在进程内；
 * 这里在每次计算前移除缓存，强制从已 flush 的持久化文件重新加载。
 */
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const STORE_NAME: string = 'nju_schedule_next';

export class WidgetPreferences {
  private static formViewKey(formId: string): string {
    return `widget2x2View_${formId}`;
  }

  static async fresh(context: common.Context): Promise<preferences.Preferences> {
    await preferences.removePreferencesFromCache(context, { name: STORE_NAME });
    return preferences.getPreferences(context, { name: STORE_NAME });
  }

  /** 2x2 当前视图（list / focus）；按 formId 独立持久化。 */
  static async getFormView(context: common.Context, formId: string): Promise<string> {
    const store: preferences.Preferences = await WidgetPreferences.fresh(context);
    const view: preferences.ValueType = await store.get(WidgetPreferences.formViewKey(formId), 'list');
    return view === 'focus' ? 'focus' : 'list';
  }

  static async setFormView(context: common.Context, formId: string, view: string): Promise<void> {
    const store: preferences.Preferences = await WidgetPreferences.fresh(context);
    await store.put(WidgetPreferences.formViewKey(formId), view === 'focus' ? 'focus' : 'list');
    await store.flush();
  }
}
