/**
 * 子页面标题栏的统一配置（全局唯一入口）。
 *
 * 直接用系统预置 `HdsNavDestination` 的标题栏：自带动态模糊、随滚动显隐/材质与返回按钮，
 * 不需要每个页面自绘标题栏。新子页面统一按下面方式使用：
 *
 * ```
 * HdsNavDestination() {
 *   Scroll(this.scroller) { ... }
 * }
 * .titleBar(hdsSubPageTitleBar('标题'))      // 可选第二参数副标题、第三参数菜单项
 * .onBackPressed(hdsSubPageBackPressed)     // 返回键：宽屏先退回 Stack 再出栈
 * .bindToScrollable([this.scroller])
 * ```
 *
 * 页面滚动内容顶部要预留 `HdsMetrics.contentTopInset(px2vp(store.windowTopInset))`，
 * 让内容从标题栏下方开始、继续滚动时进入标题栏下方产生模糊。
 */
import { hdsMaterial, HdsNavigationMenuContentOptions, HdsNavigationTitle, HdsNavigationTitleBarOptions, ScrollEffectType } from '@kit.UIDesignKit';
import { ShellRouter } from '../ShellRouter';

/** 生成标准子页面标题栏配置：系统渐变模糊 + 自适应光感材质（与主 HdsNavigation 一致）。 */
export function hdsSubPageTitleBar(title: string, subtitle: string = '',
  menu?: HdsNavigationMenuContentOptions): HdsNavigationTitleBarOptions {
  const titleObj: HdsNavigationTitle = { mainTitle: title };
  if (subtitle !== '') {
    titleObj.subTitle = subtitle;
  }
  const options: HdsNavigationTitleBarOptions = {
    avoidLayoutSafeArea: true,
    content: {
      title: titleObj
    },
    style: {
      scrollEffectOpts: {
        scrollEffectType: ScrollEffectType.GRADIENT_BLUR
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    }
  };
  if (menu !== undefined) {
    options.content!.menu = menu;
  }
  return options;
}

/**
 * 子页面系统返回键的统一处理：图标由 HDS 默认返回按钮提供（与系统一致），
 * 这里只接管返回逻辑——宽屏分栏回首页需要先退回 Stack，不能交给默认 pop。
 */
export function hdsSubPageBackPressed(): boolean {
  ShellRouter.back();
  return true;
}
