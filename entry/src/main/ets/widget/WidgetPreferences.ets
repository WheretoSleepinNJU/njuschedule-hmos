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
  static async fresh(context: common.Context): Promise<preferences.Preferences> {
    await preferences.removePreferencesFromCache(context, { name: STORE_NAME });
    return preferences.getPreferences(context, { name: STORE_NAME });
  }
}
