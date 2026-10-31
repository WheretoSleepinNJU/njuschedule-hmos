/**
 * 服务卡片（桌面小组件）扩展能力。
 *
 * 数据计算统一在 FormExtension 进程中完成：卡片侧直接读本模块 preferences/RDB，
 * 主应用数据变化时通过 updateForm 立即推送；FormExtension 同时负责
 * setFormNextRefreshTime 预约上下课边界，避免 30 分钟轮询。
 */
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { WidgetDataProvider } from './WidgetDataProvider';
import { WidgetBoundary } from './WidgetBoundary';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const parameters: Record<string, Object> | undefined = want.parameters;
    const formId: string = parameters === undefined ? '' :
      `${parameters[formInfo.FormParam.IDENTITY_KEY] ?? ''}`;
    if (formId !== '') {
      this.pushForm(formId);
    }
    return formBindingData.createFormBindingData({ data: '' });
  }

  onUpdateForm(formId: string): void {
    this.pushForm(formId);
  }

  onFormEvent(formId: string, message: string): void {
    this.pushForm(formId);
  }

  /** FormExtension 内是唯一的数据计算与卡片推送入口。 */
  private async pushForm(formId: string): Promise<void> {
    try {
      const json: string = await WidgetDataProvider.buildJson(this.context);
      if (json === '') {
        return;
      }
      await formProvider.updateForm(formId, formBindingData.createFormBindingData({ data: json }));
      const minutes: number = WidgetBoundary.nextRefreshMinutes(json);
      if (minutes > 0) {
        // 触发式刷新：只预约最近的上下课边界，不做分钟级轮询。
        // API 最小 5 分钟，因此边界不足 5 分钟时只能延后到 5 分钟。
        try {
          await formProvider.setFormNextRefreshTime(formId, minutes);
        } catch (err) {
          console.warn(`[EntryFormAbility] setFormNextRefreshTime failed: ${JSON.stringify(err)}`);
        }
      }
    } catch (err) {
      console.warn(`[EntryFormAbility] pushForm failed: ${JSON.stringify(err)}`);
    }
  }
}
