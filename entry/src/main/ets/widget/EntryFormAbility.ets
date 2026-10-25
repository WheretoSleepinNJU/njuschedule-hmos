/**
 * 服务卡片（桌面小组件）扩展能力。
 *
 * 数据来源与旧版一致：主应用把「今日课程」快照写进 preferences，
 * 卡片侧只读这份快照渲染，避免两套数据访问路径。
 */
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { WidgetDataProvider } from './WidgetDataProvider';

const STORE_NAME: string = 'nju_schedule_next';
const DATA_KEY: string = 'widgetData';
const FORMS_KEY: string = 'widgetFormIds';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const parameters: Record<string, Object> | undefined = want.parameters;
    const formId: string = parameters === undefined ? '' :
      `${parameters[formInfo.FormParam.IDENTITY_KEY] ?? ''}`;
    if (formId !== '') {
      this.registerForm(formId);
      this.pushForm(formId);
    }
    return formBindingData.createFormBindingData({ data: '' });
  }

  onRemoveForm(formId: string): void {
    this.unregisterForm(formId);
  }

  onUpdateForm(formId: string): void {
    // 卡片从桌面恢复时 onAddForm 可能不再触发，补登记保证主应用能主动刷新。
    this.registerForm(formId);
    this.pushForm(formId);
  }

  onFormEvent(formId: string, message: string): void {
    this.pushForm(formId);
  }

  private async openStore(): Promise<preferences.Preferences> {
    const options: preferences.Options = { name: STORE_NAME };
    return preferences.getPreferences(this.context, options);
  }

  /**
   * 卡片侧现场计算数据（读 prefs + 本模块 RDB），不再只依赖主应用推送的快照；
   * 这样 App 多天没打开、跨周、跨天都不会显示旧数据。
   */
  private async pushForm(formId: string): Promise<void> {
    try {
      const json: string = await WidgetDataProvider.buildJson(this.context);
      await formProvider.updateForm(formId, formBindingData.createFormBindingData({ data: json }));
    } catch (err) {
      console.warn(`[EntryFormAbility] pushForm failed: ${JSON.stringify(err)}`);
    }
  }

  private async registerForm(formId: string): Promise<void> {
    try {
      const store: preferences.Preferences = await this.openStore();
      const raw: preferences.ValueType = await store.get(FORMS_KEY, '');
      const ids: string[] = this.parseIds(typeof raw === 'string' ? raw : '');
      if (ids.indexOf(formId) < 0) {
        ids.push(formId);
        await store.put(FORMS_KEY, JSON.stringify(ids));
        await store.flush();
      }
    } catch (err) {
      console.warn(`[EntryFormAbility] registerForm failed: ${JSON.stringify(err)}`);
    }
  }

  private async unregisterForm(formId: string): Promise<void> {
    try {
      const store: preferences.Preferences = await this.openStore();
      const raw: preferences.ValueType = await store.get(FORMS_KEY, '');
      const ids: string[] = this.parseIds(typeof raw === 'string' ? raw : '');
      const index: number = ids.indexOf(formId);
      if (index >= 0) {
        ids.splice(index, 1);
        await store.put(FORMS_KEY, JSON.stringify(ids));
        await store.flush();
      }
    } catch (err) {
      console.warn(`[EntryFormAbility] unregisterForm failed: ${JSON.stringify(err)}`);
    }
  }

  private parseIds(raw: string): string[] {
    if (raw === '') {
      return [];
    }
    try {
      const parsed: string[] = JSON.parse(raw) as string[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (err) {
      return [];
    }
  }
}
