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

export class WidgetData {
  static async write(): Promise<void> {
    try {
      const json: string = await WidgetDataProvider.buildJson(AppContext.get());
      if (json === '') {
        return;
      }
      const running: formInfo.RunningFormInfo[] = await formProvider.getPublishedRunningFormInfos();
      if (running.length === 0) {
        console.warn('[WidgetData] no running forms');
        return;
      }
      for (let i = 0; i < running.length; i++) {
        try {
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
