# 呢喃课表 · 开发速查手册

> 面向仓库贡献者与维护者的速查页。完整的移植调研、开发过程与历史设计文档已归档，**不随开源仓库发布**。
> 更多约定见根目录 [AGENTS.md](../AGENTS.md) 与 [CONTRIBUTING.md](../CONTRIBUTING.md)。
> 仓库：[https://github.com/WheretoSleepinNJU/njuschedule-hmos](https://github.com/WheretoSleepinNJU/njuschedule-hmos)　|　问题反馈：[Issues](https://github.com/WheretoSleepinNJU/njuschedule-hmos/issues)

## 1. 项目速览

| 项 | 值 |
| --- | --- |
| 应用名 | 呢喃课表（英文：NJU Schedule NEXT） |
| 包名 | `com.njuschedulenext.jesse`（保持不变，避免破坏升级与本地数据） |
| 平台 / SDK | HarmonyOS 26（API 26），Stage 模型，phone / tablet / 2in1 |
| UI | ArkTS / ArkUI 原生重写；**仅状态管理 V2** |
| 上游 | Flutter 版「南哪课表」（idealclover，Apache-2.0） |
| 数据 | 全部本地：关系型数据库 `course.db` + preferences；无账号、无自建服务器 |
| 权限 | 仅 `ohos.permission.INTERNET` |
| 许可 | Apache License 2.0（见 `LICENSE` / `NOTICE`） |

## 2. 常用命令

```bash
# 构建（debug / release）
devecocli build
devecocli build --build-mode release

# 静态检查（提交前必跑）
devecocli check arkts $(find entry/src/main/ets -name '*.ets' | tr '\n' ' ')
devecocli check lint

# 设备
devecocli device list
devecocli ui screenshot --device <serial> --path /tmp/shot.png
```

真机安装需要签名。仓库**不携带签名材料**：`build-profile.json5` 的 `signingConfigs` 保持为空；本机签名配置放在 `external-signing-config.json`（已 gitignore，示例见 `external-signing-config.example.json`），由根 `hvigorfile.ts` 条件注入。**任何证书、keystore、口令、Profile 都不要提交。**

## 2.0 CI

`.github/workflows/ci.yml` 在 push / PR 时执行：

- 使用 `ErBWs/setup-ohos@v2` 安装固定版本 HarmonyOS CLI；
- `ohpm install --all`；
- `hvigorw assembleHap` 构建 release 未签名 HAP；
- `node --test` 校验版本号、CHANGELOG、导入配置与脚本；
- `codelinter` 静态检查；
- 上传 HAP 与 `SHA256SUMS` artifact。

CI **只构建未签名 HAP**，不接触发布证书；正式签名仍在本机完成。

## 2.0.1 Tag Release

推送 `v*` tag 时，`.github/workflows/release.yml` 会：

- 校验 tag 与 `AppScope/app.json5` 的版本一致；
- 跑仓库测试、构建 release 未签名 HAP、执行静态检查；
- 从 `CHANGELOG.md` 提取对应版本作为 Release 说明；
- 自动创建 GitHub Release，并上传 `njuschedule-hmos-<version>-unsigned.hap` 与 `SHA256SUMS`。

## 2.1 版本与发布

参考 Kazumi 的版本管理方式：**单一版本源 + 语义化版本 + 发布 tag**。

- 版本唯一来源：`AppScope/app.json5` 的 `versionName` / `versionCode`；
- `versionName` 使用语义化版本，如 `0.1.6`；
- `versionCode` 由语义版本编码，保证单调递增：
  `1_000_000 + major*10000 + minor*100 + patch`
  （`0.1.6` → `1000106`；前导 `1_000_000` 为兼容已发布版本的基数）；
- 发布流程：
  1. 更新 `AppScope/app.json5`；
  2. 更新 `CHANGELOG.md` 对应版本记录；
  3. 提交并打 tag（如 `v0.1.6`）推送；
  4. tag 会触发 Release workflow，自动构建未签名 HAP、生成 SHA256SUMS 并发布 GitHub Release；
  5. 签名 `.app` 仍在本机生成后手动上传 AGC。

不要只改 `versionName` 不改 `versionCode`，否则 HarmonyOS 无法覆盖安装升级。

## 3. 目录结构

```
entry/src/main/ets/
  app/        AppContext / AppPreferences / AppState / AppStore / AppBootstrap / Appearance / ThemeAccent
  common/     Constants / DateUtils / RouteParams / AppVersion / NavStackResolver
    design/   Tokens（颜色/字号/间距/圆角/课表尺寸）、Breakpoints
    ui/       跨功能组件：AppCard / SectionHeader / EmptyState / Feedback / HdsSubPage / ArrayDataSource 等
  data/       Db、RdbUtil、各 Repository、ScheduleModel、WeekUtil、ColorPool、DemoData、
              Lecture、BackgroundImage、ShareCodec、WidgetData
  widget/     桌面小组件（2x2 / 2x4 / 4x4）与 Form 数据
  features/   timetable / courses / import / share / lectures / settings
  pages/      Index.ets（HdsNavigation + HdsTabs + NavPathStack 路由）
entry/src/main/resources/  string/color 资源、rawfile/import（schoolList.json + tools/*.js）、背景图
```

## 4. 编码约定（必须）

- **状态管理只用 V2**：`@ComponentV2` / `@Local` / `@Param` / `@Event` / `@ObservedV2` / `@Trace`；
  全局状态走 `AppStore`（`AppStorageV2`），写入统一走 `AppState.setXxx`。禁止新增 V1 装饰器。
- **外壳只用 HDS**：`HdsNavigation` / `HdsTabs` / `hdsMaterial`；子页面统一 `HdsNavDestination` +
  `hdsSubPageTitleBar()`，不要自绘标题栏。
- **颜色与尺寸走令牌**：颜色用 `$r('app.color.*')` + `resources/dark`，尺寸/字号/圆角走 `Tokens.ets`。
- **通用组件放 `common/ui`**，业务组件留在 `features/<域>`；网络与存储不直接写进页面。
- 改 UI / 交互前先查 HarmonyOS 官方文档与最佳实践（RTFM / STFW），不凭记忆猜 API 或事件时序。
- 新增权限、第三方依赖、数据 schema、导入方式前先讨论；新增开源依赖时同步 `ThirdPartyLicenseData.ets` 与 `NOTICE`。
- 修改隐私政策时：同步 `features/settings/legal/LegalDocuments.ets` 与 `docs/privacy-policy.md`，
  并与 AGC 托管隐私声明版本保持一致。

## 5. 关键实现与坑

- **标题栏滚动模糊**：`HdsNavigation` 的 `bindToScrollable` 只绑定当前 Tab 的 Scroller；
  课表 25 个周页面轮换绑定时同一时刻只绑一个，避免互相干扰。
- **课表周切换**：`Swiper` 的 `currentIndex` 保持单一来源，不要在动画回调里反向驱动外部状态。
- **沉浸式布局**：内容顶部使用 `HdsMetrics.contentTopInset(px2vp(store.windowTopInset))`，
  padding 必须放在 Scroll 内部（否则标题栏模糊联动失效）。
- **分享码**：`ncs://qr/v2`，gzip + URL-safe base64 + CRC32 + 多帧；与上游旧版互通，改动需保持向后兼容。
- **教务导入**：ArkWeb 打开学校页面 + 注入 `rawfile/import/tools/*.js`；账号密码由学校页面直接处理，
  应用不读取/不保存。新增学校或域名需要评估并记录。
- **桌面小组件**：卡片侧读取本地数据计算，不依赖应用进程常驻。

## 6. 文档地图

| 文档 | 用途 |
| --- | --- |
| [README.md](../README.md) | 项目介绍、功能与构建 |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | 贡献指引（开发环境、PR、AI 辅助规则） |
| [SECURITY.md](../SECURITY.md) | 安全漏洞报告与测试边界 |
| [privacy-policy.md](privacy-policy.md) | 隐私政策（应用内同源） |
| [AGENTS.md](../AGENTS.md) | 仓库级开发/Agent 约定 |
| `CHANGELOG.md` | 版本更新记录 |
