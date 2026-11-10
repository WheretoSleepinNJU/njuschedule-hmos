/**
 * 一级 Tab 页面容器。
 *
 * 根 HdsNavigation 不显示标题栏，由每个 Tab 的 HdsNavDestination 提供
 * 系统材质标题栏和滚动模糊绑定。三个一级 Tab 共用这一套结构。
 */
import {
  HdsNavDestination,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitleBarOptions
} from '@kit.UIDesignKit';
import { hdsSubPageTitleBar } from './HdsSubPage';

@ComponentV2
export struct HdsTabPage {
  @Param title: string = '';
  @Param subtitle: string = '';
  @Param menu: HdsNavigationMenuContentOptions | undefined = undefined;
  /** 当前页面的滚动容器，用于标题栏滚动模糊联动。 */
  @Param scrollables: Scroller[] = [];
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  private emptyContent() {
  }

  private titleBarOptions(): HdsNavigationTitleBarOptions {
    // 与所有子页面共用同一套 HDS 标题栏材质与渐变模糊配置。
    return hdsSubPageTitleBar(this.title, this.subtitle, this.menu);
  }

  build() {
    HdsNavDestination() {
      this.content()
    }
    .titleBar(this.titleBarOptions())
    .hideBackButton(true)
    .bindToScrollable(this.scrollables)
    .width('100%')
    .height('100%')
  }
}
