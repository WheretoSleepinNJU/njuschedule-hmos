/**
 * 宽屏设置页：左侧设置主列表，右侧设置子页面。
 *
 * 依据官方 NavigationSettings 示例的 master-detail 结构：
 * - 根 Navigation 只承载设置模块，使用 Split 模式；
 * - SettingsView 作为 NavBar，子页面作为 NavDestination；
 * - 窄屏仍由外壳的 HdsTabs 直接承载 SettingsView，不进入本组件。
 */
import {
  HdsNavDestination,
  HdsNavigation,
  HdsNavDestinationTitleMode
} from '@kit.UIDesignKit';
import { Colors } from '../../common/design/Tokens';
import { SettingsView } from './SettingsView';
import { ManageTablesPage } from './ManageTablesPage';
import { MoreSettingsPage } from './MoreSettingsPage';
import { AboutPage } from './AboutPage';
import { OpenSourceLicensesPage } from './OpenSourceLicensesPage';
import { AcknowledgementsPage } from './AcknowledgementsPage';
import { PrivacyPage } from './PrivacyPage';
import { LecturesPage } from '../lectures/LecturesPage';
import { SharePage } from '../share/SharePage';

@ComponentV2
export struct SettingsSplitView {
  /** 设置子页面使用独立栈，避免和主外壳的课程/导入路由混在一起。 */
  private settingsStack: NavPathStack = new NavPathStack();

  @Param scroller: Scroller = new Scroller();

  @Builder
  private destinationBuilder(name: string, param: Object) {
    HdsNavDestination() {
      if (name === 'tables') {
        ManageTablesPage({ pageStack: this.settingsStack })
      } else if (name === 'more-settings') {
        MoreSettingsPage()
      } else if (name === 'about') {
        AboutPage({ pageStack: this.settingsStack })
      } else if (name === 'licenses') {
        OpenSourceLicensesPage()
      } else if (name === 'acknowledgements') {
        AcknowledgementsPage({})
      } else if (name === 'privacy') {
        PrivacyPage({})
      } else if (name === 'lectures') {
        LecturesPage({})
      } else if (name === 'share') {
        SharePage({})
      }
    }
    .hideTitleBar(true)
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .width('100%')
    .height('100%')
  }

  build() {
    HdsNavigation(this.settingsStack) {
      SettingsView({
        pageStack: this.settingsStack,
        scroller: this.scroller
      })
    }
    .mode(NavigationMode.Split)
    .navBarWidth(320)
    .hideTitleBar(true)
    .navDestination(this.destinationBuilder)
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.Background)
  }
}
