# 贡献指引

欢迎提交 Pull Request 一起建设这个项目！在开始之前，请先阅读这份指引，以保障审阅者与您之间的协作效率。

## 开发环境设置

### 前置需求

- **DevEco Command Line Tools**（`devecocli`）与 **HarmonyOS 26 SDK（API 26）**
- 一台 HarmonyOS 真机或模拟器
  - 模拟器可安装未签名 HAP；真机安装需要本机签名（签名材料不入库）
- 建议保证可访问 GitHub 与 HarmonyOS 官方文档，便于查阅 API 与最佳实践

### 基本配置

```bash
# 克隆仓库
git clone https://github.com/WheretoSleepinNJU/njuschedule-hmos.git
cd njuschedule-hmos

# 构建（未签名 HAP）
devecocli build

# 静态检查
devecocli check arkts $(find entry/src/main/ets -name '*.ets' | tr '\n' ' ')
devecocli check lint

# 真机签名（本机配置，不要提交）
cp external-signing-config.example.json external-signing-config.json
# 按示例填写证书 / Profile / keystore 与口令后：
devecocli build
# 产物：entry/build/default/outputs/default/entry-default-signed.hap
```

更详细的命令与目录说明见 [docs/README.md](docs/README.md)，仓库级开发约定见 [AGENTS.md](AGENTS.md)。

## 代码质量

您的更改应该通过构建与静态检查：

```bash
devecocli build
devecocli check arkts $(find entry/src/main/ets -name '*.ets' | tr '\n' ' ')
devecocli check lint
```

涉及 UI、导入、分享、卡片等功能的改动，请在真机上验证（可以使用应用内置的 Demo 课表，**不要提交真实课表/账号数据**）。

## 编写规范

项目按 `app -> 数据/状态 -> features -> pages` 分层，不同职责的组件分目录存放，互不混写：

- UI 与业务组件按域放在 `features/<域>`，跨域通用组件才放 `common/ui`
- 网络与存储不直接写在页面里，统一走 `data/` 与 `app/` 层
- 状态管理**只使用 V2**（`@ComponentV2` / `@Local` / `@Param` / `@Event` / `@ObservedV2` / `@Trace`），不新增 V1 装饰器
- 颜色、尺寸、间距走 `Tokens` 与资源限定词，不硬编码
- 改 UI / 交互前先查 HarmonyOS 官方文档与最佳实践，并在代码注释或提交信息中说明依据

开发过程中，您应该**慎重考虑**新增外部库、会导致包体积大量膨胀的实现和其它不安全的行为：

- 如果要引入新的外部库——先考虑是否有更轻量的实现，以及是否会破坏「无第三方 SDK / 最小权限」的原则
- 如果功能会导致包体积巨增——也许这个功能目前不应该实现
- 如果性能表现大打折扣——当前功能的思路是不是需要重新考虑
- 新增权限、第三方依赖、数据 schema、导入方式前，请先在 Issue 中讨论

当出现行为或风险改动时，您应该同步更新相关文档与测试；涉及隐私政策的改动需将 `AppBootstrap.PRIVACY_VERSION` +1。

## 更改与 Commits

建议使用 [Conventional Commits](https://www.conventionalcommits.org/)：

```
feat(timetable): 支持课表背景图
fix(share): 修复多帧分享码合并失败
refactor(courses): 拆分课程表单组件
chore: 补充开源许可信息
docs: 更新开发速查手册
```

**不建议使用模糊不清的 commits**。准确的提交信息能说明您做出的工作，为审查提供便利。

## 推送与 Pull Requests

### 限制

您的 PR 至少应该符合以下基本要求：

- **一个 PR 只解决一件事情**。比起把多个功能、调整和修复堆在一个 PR 中，把它们拆开分别提交是更好的选择。
- **一个 PR 更改的代码量不应过多**。上千行的改动建议拆分，利于审查和修改。
- **提交 PR 时的描述部分必须由您亲自填写**。您可以利用 AI 润色措辞，但不得让 AI 直接生成整个描述，也不得完全依赖 AI 撰写。

### 类型

- **Bug 修复**：请先提 Issue（或引用已有 Issue）并确认问题已修复。
- **新功能**：编写代码和推送前，请确认功能已被维护者认可，避免因不在计划内而被拒绝。
- **重构**：重构与新功能应清楚分开，重构 PR 中不要加入新功能。

### PR 标题

PR 标题遵循 Conventional Commits 格式：

```
feat(settings): 关于页增加致谢子页面
fix(import): 修复教务导入刷新后卡在错误页
refactor(licenses): 统一第三方许可证数据
```

### 推送 PR 之后

维护者会尽快审查。若检查失败、存在合并冲突或有审查意见，请及时修复。未合并的 PR 通常会说明原因，例如：

- 实现带来不可接受的性能开销或包体积增长
- 引入安全/隐私风险，或违反「无第三方 SDK、最小权限」原则
- 实现过于臃肿，可能有更合适的方法
- 改动不在当前计划内

**这并非对您工作的否定**，只是因为贡献可能暂不适合项目当前情况。感谢您的付出！

### AI 参与辅助开发

欢迎使用 AI 辅助开发。但无法接受直接让 AI 生成代码、不加检查就提交，或反复「AI 生成 → 报错 → 再让 AI 修」而不理解改动内容。

当您使用 AI 参与开发时，请遵守：

1. 如果您使用了 AI 辅助开发，**不应隐瞒**；
2. 您应当理解 AI 写出的每行代码，了解 AI 做了什么；
3. 审查者询问改动原因时，您需要能够解释，无论代码由谁编写；
4. PR 中不应出现多轮「AI 生成 → 修复 → 修复」的循环，这通常说明没有审查 AI 产物。

PR 模板中有 AI 辅助说明项；如果使用了 AI，请注明**具体模型名称**（例如 `DeepSeek-V3.2`、`Claude Sonnet 4.5`），帮助审查者判断代码质量。

## 许可证

本项目基于 [Apache License 2.0](LICENSE) 授权。参与贡献即表示您同意您的代码以此许可证进行许可。
