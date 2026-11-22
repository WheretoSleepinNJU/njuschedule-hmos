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
import { WidgetPreferences } from './WidgetPreferences';
import { WIDGET_TOGGLE_FLIP_MS } from './WidgetCommon';

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
    this.handleFormEvent(formId, message);
  }

  /** 2x2 切换按钮：等翻转动画结束后刷新 list / focus 视图。 */
  private async handleFormEvent(formId: string, message: string): Promise<void> {
    let action: string = message;
    try {
      // postCardAction 的 onFormEvent message 是系统包了一层的事件信封：
      // { action: 'message', params: { message: 'toggle2x2Focus' } }
      const envelope: Record<string, Object> = JSON.parse(message) as Record<string, Object>;
      const paramsObject: Object | undefined = envelope['params'];
      if (paramsObject !== undefined) {
        const params: Record<string, string> = paramsObject as Record<string, string>;
        if (params['message'] !== undefined) {
          action = params['message'];
        } else if (params['action'] !== undefined) {
          action = params['action'];
        }
      } else if (envelope['message'] !== undefined) {
        action = envelope['message'] as string;
      }
    } catch (err) {
      // message 也可能是纯字符串，直接按原值处理。
    }
    try {
      if (action === 'toggle2x2Focus') {
        const current: string = await WidgetPreferences.getFormView(this.context, formId);
        await WidgetPreferences.setFormView(this.context, formId, current === 'focus' ? 'list' : 'focus');
        // 等图标完成 180° 翻转后再刷新卡片，避免 Form 更新提前打断动画。
        await this.delay(WIDGET_TOGGLE_FLIP_MS);
      }
    } catch (err) {
      console.warn(`[EntryFormAbility] form event failed: ${JSON.stringify(err)}`);
    }
    await this.pushForm(formId);
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }

  /** FormExtension 内是唯一的数据计算与卡片推送入口。 */
  private async pushForm(formId: string): Promise<void> {
    try {
      const view: string = await WidgetPreferences.getFormView(this.context, formId);
      const json: string = await WidgetDataProvider.buildJson(this.context, view);
      if (json === '') {
        return;
      }
      await formProvider.updateForm(formId, formBindingData.createFormBindingData({ data: json }));
      let minutes: number = WidgetBoundary.nextRefreshMinutes(json);
      if (view === 'focus') {
        // focus 视图显示实时课程进度，至少每 5 分钟刷新一次。
        minutes = minutes > 0 ? Math.min(minutes, 5) : 5;
      }
      if (minutes > 0) {
        // 触发式刷新：列表视图只预约最近的上下课边界，不做分钟级轮询。
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
