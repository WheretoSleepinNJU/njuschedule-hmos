/**
 * 桌面小组件数据同步（主应用侧）。
 *
 * 即时数据变化（课程编辑、切周、主题色）走 Form Kit 的“卡片提供方主动刷新”：
 * 主进程根据最新 DB + preferences 计算 payload，再通过 formProvider.updateForm
 * 直接推给当前已添加的卡片。这个路径是官方主动刷新机制，不依赖 Form 定时器。
 *
 * 上下课边界仍由 FormExtensionAbility 的 setFormNextRefreshTime 触发。
 */
import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { AppContext } from '../app/AppContext';
import { WidgetDataProvider } from '../widget/WidgetDataProvider';
import { WidgetPreferences } from '../widget/WidgetPreferences';

export class WidgetData {
  static async write(): Promise<void> {
    try {
      const running: formInfo.RunningFormInfo[] = await formProvider.getPublishedRunningFormInfos();
      if (running.length === 0) {
        console.warn('[WidgetData] no running forms');
        return;
      }
      // 2x2 的 list/focus 视图按 formId 独立持久化，主应用刷新时也要保持当前视图。
      const jsonByView: Map<string, string> = new Map();
      for (let i = 0; i < running.length; i++) {
        try {
          let view: string = 'list';
          if (running[i].formName === 'widget_2x2') {
            view = await WidgetPreferences.getFormView(AppContext.get(), running[i].formId);
          }
          let json: string | undefined = jsonByView.get(view);
          if (json === undefined) {
            json = await WidgetDataProvider.buildJson(AppContext.get(), view);
            jsonByView.set(view, json);
          }
          if (json === '') {
            continue;
          }
          await formProvider.updateForm(running[i].formId,
            formBindingData.createFormBindingData({ data: json }));
        } catch (err) {
          console.warn(`[WidgetData] updateForm ${running[i].formId} failed: ${JSON.stringify(err)}`);
        }
      }
    } catch (err) {
      console.warn(`[WidgetData] write failed: ${JSON.stringify(err)}`);
    }
  }
}
