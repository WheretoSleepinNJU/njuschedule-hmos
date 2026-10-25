/**
 * 桌面小组件数据（主应用侧）。
 *
 * 数据的**计算**统一由 `widget/WidgetDataProvider` 完成（卡片侧与主应用共用同一套逻辑，
 * 避免两份口径）；主应用只负责：
 * 1. 启动 / 回前台 / 数据变化时触发一次计算并写入 preferences 快照；
 * 2. 用 formProvider.updateForm 主动推给所有已添加的卡片。
 *
 * 这样即使主应用长时间未打开，卡片侧也能在周期更新时自己算（见 EntryFormAbility）。
 */
import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { AppContext } from '../app/AppContext';
import { AppPreferences } from '../app/AppPreferences';
import { WidgetDataProvider } from '../widget/WidgetDataProvider';

export class WidgetData {
  /** preferences 里保存 widget JSON 的 key（与 FormExtensionAbility 约定一致）。 */
  static readonly DATA_KEY: string = 'widgetData';
  /** 已添加卡片的 formId 列表（JSON 数组字符串）。 */
  static readonly FORMS_KEY: string = 'widgetFormIds';

  /** 计算并写入今日课程快照，然后通知所有卡片刷新。 */
  static async write(): Promise<void> {
    try {
      const json: string = await WidgetDataProvider.buildJson(AppContext.get());
      if (json === '') {
        return;
      }
      await AppPreferences.put(WidgetData.DATA_KEY, json);
      await WidgetData.notifyForms();
    } catch (err) {
      console.warn(`[WidgetData] write failed: ${JSON.stringify(err)}`);
    }
  }

  /** 通知所有已添加的卡片刷新（main 进程调用）。 */
  static async notifyForms(): Promise<void> {
    const raw: string = await AppPreferences.getString(WidgetData.FORMS_KEY, '');
    if (raw === '') {
      return;
    }
    let ids: string[] = [];
    try {
      ids = JSON.parse(raw) as string[];
    } catch (err) {
      return;
    }
    if (!Array.isArray(ids)) {
      ids = [];
    }
    // prefs 里的 formId 可能来自旧安装/已移除卡片；向系统查询当前仍在桌面的卡片并合并，
    // 保证主题色、深浅色或课程配色变化能立即推送到当前实际存在的卡片。
    try {
      const running: formInfo.RunningFormInfo[] = await formProvider.getPublishedRunningFormInfos();
      for (let i = 0; i < running.length; i++) {
        const formId: string = running[i].formId;
        if (formId !== '' && ids.indexOf(formId) < 0) {
          ids.push(formId);
        }
      }
    } catch (err) {
      console.warn(`[WidgetData] query running forms failed: ${JSON.stringify(err)}`);
    }
    if (ids.length === 0) {
      return;
    }
    const json: string = await AppPreferences.getString(WidgetData.DATA_KEY, '');
    if (json === '') {
      return;
    }
    for (let i = 0; i < ids.length; i++) {
      try {
        await formProvider.updateForm(ids[i], formBindingData.createFormBindingData({ data: json }));
      } catch (err) {
        console.warn(`[WidgetData] updateForm ${ids[i]} failed: ${JSON.stringify(err)}`);
      }
    }
  }
}
