/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, Configuration, ConfigurationConstant, systemConfiguration, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppBootstrap } from '../app/AppBootstrap';
import { WidgetData } from '../data/WidgetData';
import { AppState } from '../app/AppState';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    // 数据层初始化（偏好 / 数据库 / 周次 / 配色池），完成后置 Ready。
    AppBootstrap.run(this.context).catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'bootstrap rejected: %{public}s', JSON.stringify(err));
    });
    this.primeSystemColorMode();
    try {
      this.context.getApplicationContext().onSystemConfigurationUpdated(this.systemConfigCallback);
      console.info('[EntryAbility] registered system configuration callback');
    } catch (err) {
      console.warn(`[EntryAbility] register system callback failed: ${JSON.stringify(err)}`);
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  /** 真正的系统深浅色变化回调（不受 App 内 setColorMode 影响）。 */
  private systemConfigCallback: systemConfiguration.UpdatedCallback = {
    onColorModeUpdated: (colorMode: ConfigurationConstant.ColorMode) => {
      const dark: boolean = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      console.info(`[EntryAbility] system color mode updated: ${dark ? 'dark' : 'light'}`);
      AppState.noteSystemColorMode(dark);
    }
  };

  /** 把当前生效的深浅色写入 AppStore（课程块标题配色依赖它）。 */
  private syncColorMode(): void {
    try {
      const dark: boolean = this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      AppState.setIsDark(dark);
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'syncColorMode failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 启动时记录「真正的系统深浅色」：这一时刻 App 还没有调用 setColorMode，
   * ability 的 config 就是系统值；后续系统切换由 onSystemConfigurationUpdated 回调更新。
   * 这是触发式检测，不使用定时器（定时器链曾导致主线程卡死）。
   */
  private primeSystemColorMode(): void {
    try {
      const dark: boolean = this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      AppState.noteSystemColorMode(dark);
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'prime system color mode failed: %{public}s', JSON.stringify(err));
    }
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    this.syncColorMode();
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    // 窗口尺寸写入 AppStore，供外壳与页面选择断点。
    windowStage.getMainWindow().then((mainWindow: window.Window) => {
      const rect: window.Rect = mainWindow.getWindowProperties().windowRect;
      AppState.setWindowSize(rect.width, rect.height);
      EntryAbility.enableImmersiveLayout(mainWindow);
      mainWindow.on('windowSizeChange', (size: window.Size) => {
        AppState.setWindowSize(size.width, size.height);
      });
    }).catch((err: Error) => {
      hilog.warn(DOMAIN, 'testTag', 'window size unavailable: %{public}s', JSON.stringify(err));
    });
  }

  /**
   * 沉浸式布局：全屏绘制，并把状态栏/手势条避让高度写入 AppStore，
   * 页面自行决定内容是否延伸到系统区域（参考 hydrotoolkit-hmos 的实现）。
   */
  private static enableImmersiveLayout(mainWindow: window.Window): void {
    try {
      mainWindow.setWindowLayoutFullScreen(true);
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'full screen layout failed: %{public}s', JSON.stringify(err));
      return;
    }
    const publishInsets = (): void => {
      try {
        const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const indicatorArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        AppState.setWindowInsets(systemArea.topRect.height, indicatorArea.bottomRect.height);
      } catch (err) {
        hilog.warn(DOMAIN, 'testTag', 'avoid area unavailable: %{public}s', JSON.stringify(err));
      }
    };
    publishInsets();
    mainWindow.on('avoidAreaChange', () => {
      publishInsets();
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    this.syncColorMode();
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    // 回到前台时刷新桌面小组件数据（跨天、切周、改课后下一次打开即更新）。
    WidgetData.write().catch((err: Error) => {
      hilog.warn(DOMAIN, 'testTag', 'widget refresh failed: %{public}s', JSON.stringify(err));
    });
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    // 用户从应用回到桌面时补推一次最新卡片数据。
    WidgetData.write().catch((err: Error) => {
      hilog.warn(DOMAIN, 'testTag', 'widget background reload failed: %{public}s', JSON.stringify(err));
    });
  }
}