# AGENTS.md — 呢喃课表 · HarmonyOS（ArkTS 重写）

> 适用范围：本仓库全部目录。面向参与本仓库的开发者与 AI Agent。
> 项目介绍见 [README.md](README.md)，贡献流程见 [CONTRIBUTING.md](CONTRIBUTING.md)，开发命令速查见 [docs/README.md](docs/README.md)。

## 0. 开发前必读：RTFM / STFW（强制）

> 修改 bug、实现功能、改 UI/交互之前，**先查 HarmonyOS 官方文档与最佳实践**，直接采用官方推荐做法；
> 不允许凭记忆猜 API、猜事件时序、猜组件能力，也不允许在官方已有现成机制时自己另造一套。

1. **RTFM**：优先查 HarmonyOS 官方文档 / FAQ / 最佳实践，组件能力与事件时序以 SDK `.d.ts` 为准；
2. **STFW**：查华为开发者联盟、社区问答与博客，优先官方来源；
3. **先找现成实现**：官方示例、同类 HarmonyOS 工程、上游 Flutter 项目的既有行为；
4. **记录依据**：在代码注释或提交信息中写清参考的文档/问答与结论；仍不确定时先讨论，不要猜。

### 反面清单（本项目已踩过的坑）

- 凭直觉用 `@Builder` 传参做动态标题 → 参数变化不重绘；先查 Builder/状态管理文档。
- Swiper 用外部状态驱动 `.index()` 又在动画回调里改该状态 → 滑动闪动/回弹；保持 `currentIndex` 单一来源。
- 沉浸式布局到处加 `expandSafeArea` 而不查「窗口沉浸 + 避让区」文档 → 底部空白/内容被遮挡。
- 自己写手势模拟翻页 → 方向、阈值、连切都容易错；优先使用 `Swiper` 等系统组件。

## 1. 项目定位

- 用 ArkTS / ArkUI 原生重写的南京大学课程表 App「呢喃课表」，目标设备 phone / tablet / 2in1。
- 上游行为基准：[WheretoSleepinNJU/NJU-Class-Shedule-Flutter](https://github.com/WheretoSleepinNJU/NJU-Class-Shedule-Flutter)（只读参考）。
  功能范围、教务导入流程、数据模型以它为准；UI 按 HarmonyOS 规范重做，不逐像素复刻。
- `bundleName` 保持 `com.njuschedulenext.jesse`（不改包名，避免破坏升级与本地数据）。
- 仅 ArkTS 原生实现，不做 Flutter / WebView 壳。

## 2. 工具链与常用命令

HarmonyOS 26 SDK（API 26）+ DevEco Command Line Tools（`devecocli`）：

```bash
devecocli build [--build-mode release]
devecocli check arkts $(find entry/src/main/ets -name '*.ets' | tr '\n' ' ')
devecocli check lint
devecocli device list
devecocli ui screenshot --device <serial> --path /tmp/shot.png
```

- 签名材料不入库：`build-profile.json5` 的 `signingConfigs` 保持为空；本机签名放 `external-signing-config.json`（已 gitignore，示例见 `external-signing-config.example.json`），由根 `hvigorfile.ts` 条件注入。
- 提交前必须通过 build + check arkts；涉及 UI 的改动需真机验证（使用 Demo 数据）。

## 3. UI 与代码约定

```
entry/src/main/ets/
  app/        AppContext / AppPreferences / AppState / AppStore / AppBootstrap / Appearance / ThemeAccent
  common/     常量、日期/路由工具、AppVersion、NavStackResolver
    design/   Tokens（颜色/尺寸/间距/字号/圆角）、Breakpoints
    ui/       跨功能组件（AppCard / SectionHeader / EmptyState / Feedback / HdsSubPage / ArrayDataSource）
  data/       Db / RdbUtil / Repository / ScheduleModel / WeekUtil / ColorPool / DemoData /
              Lecture / BackgroundImage / ShareCodec / WidgetData
  widget/     桌面小组件（2x2 / 2x4 / 4x4）
  features/   timetable / courses / import / share / lectures / settings
  pages/      Index.ets（HdsNavigation + HdsTabs + NavPathStack）
```

- 外壳使用 HDS 组件（`HdsNavigation` / `HdsTabs` / `hdsMaterial`），不自行调模糊/材质参数。
- 子页面统一使用 `HdsNavDestination` + `common/ui/HdsSubPage.hdsSubPageTitleBar()`，禁止自绘标题栏。
- 颜色走 `$r('app.color.*')` + `resources/dark`；尺寸/字号/圆角走 `Tokens.ets`，禁止硬编码。
- **状态管理只用 V2**：`@ComponentV2` / `@Local` / `@Param` / `@Event` / `@ObservedV2` / `@Trace`；
  全局状态走 `AppStore`（`AppStorageV2`），写入统一走 `AppState.setXxx`；禁止新增 V1 装饰器。
- 通用组件放 `common/ui`，业务组件放 `features/<域>`；网络与存储不直接写进页面。

## 4. 数据、隐私与合规

- 仅申请 `ohos.permission.INTERNET`；无账号、无自建服务器、无第三方 SDK/广告/统计/推送/崩溃上报。
- 课程、课表、设置与背景图仅保存在本机；分享码完全在本机生成/解析。
- 教务导入使用 ArkWeb + 注入 `rawfile/import/tools/*.js`；账号密码由学校页面直接处理，应用不读取/不保存。
- 新增权限、第三方依赖、数据 schema、导入域名/方式前，先在 Issue 中讨论。
- 隐私政策：正文在 `features/settings/legal/LegalDocuments.ets`，同步维护 `docs/privacy-policy.md`；
  任何文案变更需同步 AGC 托管隐私声明版本。
- 新增开源依赖时同步 `features/settings/ThirdPartyLicenseData.ets` 与 `NOTICE`。

## 5. Git 与提交

- 分支：`main` 为公开/发布基线，`develop` 为集成分支；功能/修复从 `develop` 拉 `feature/<topic>`，完成后合回。
- 提交信息使用 `type: 描述`（如 `feat: 课表周视图`、`fix: 分享码多帧合并`），遵循 Conventional Commits。
- 不提交构建产物、签名材料、密钥、设备序列号、真实课表/账号等敏感信息。
- 推荐小步提交；一个 PR 只解决一件事。
- **公开仓库只在功能完成并验证通过、准备发布时更新**：调试过程中的提交保留在本地 `develop`，
  不要随改随推；需要发布时再把完成的功能批量同步到 `public-main` 并推送。

## 6. 文档

- 开发速查：[docs/README.md](docs/README.md)
- 隐私政策：`docs/privacy-policy.md`
- 版本记录：[CHANGELOG.md](CHANGELOG.md)
- 完整移植调研与开发过程文档已归档，不在仓库内；如需查阅请向维护者索取。
- 仓库级约束以本文件为准；贡献流程与 AI 辅助规则见 [CONTRIBUTING.md](CONTRIBUTING.md)。
