# Claude Code / Codex 双平台兼容设计

- 日期：2026-07-23
- 状态：双平台实现、远端发布、本机 Codex 升级和 Codex runtime smoke 已完成；Claude runtime smoke 因 CLI 未安装而未执行
- 仓库：https://github.com/hangwenlei/My-Skills
- 范围：`chinese` 与 `sync` 两个插件、双平台 marketplace、验证、发布及本机 Codex 升级

## 1. 背景

现有发布物以 Claude Code 为中心：

- marketplace 位于 `.claude-plugin/marketplace.json`；
- plugin manifest 位于各插件的 `.claude-plugin/plugin.json`；
- `chinese` 只维护 `.claude/settings.json` 与 `CLAUDE.md`；
- `sync` 依赖 `CLAUDE.md` 的 `@HANDOFF.md` 导入；
- README、验证脚本和更新命令均只描述 Claude Code。

Codex 当前能通过 legacy 兼容层安装该 marketplace，但发布物缺少 Codex 原生入口，skill 的实际行为也不会维护 `AGENTS.md`。当前工作树中删除的 Claude 文件属于未完成迁移；本次改造恢复它们，并新增 Codex 支持，不放弃 Claude Code。

## 2. 目标与成功标准

### 2.1 功能目标

- Claude Code 中继续使用 `/chinese:init` 与 `/sync:docs`。
- Codex 中使用 `$chinese:init` 与 `$sync:docs`，也可从 `/skills` 选择。
- 两个平台执行相同业务目标，但使用各自原生的项目指令载体：
  - Claude Code：`.claude/settings.json`、`CLAUDE.md`；
  - Codex：`AGENTS.md`。
- 两个平台共用同一个 Git marketplace 仓库和同一份核心 `SKILL.md`；Claude
  额外使用一个保留手动调用开关的薄入口，避免业务逻辑分叉。
- 现有内容保留、重复运行幂等、异常哨兵不被静默覆盖。

### 2.2 发布目标

- Claude 与 Codex 各自拥有原生 marketplace 和 plugin manifest。
- 两套 manifest 的插件名称、版本和核心描述保持一致。
- 发布仍是向 `origin/main` 推送；不提交到官方公共 Plugins Directory。
- 发布后升级本机已安装的 Codex 插件，不直接编辑 Codex cache 或配置注册表。

### 2.3 明确限制

Codex 当前不允许第三方 plugin 注册任意 slash command。Codex 的第三方 skill 原生入口是 `$skill` 或 `/skills`；因此不宣称 Codex 支持 `/chinese:init` 或 `/sync:docs`。两平台保留相同的命名空间与功能，但使用各自原生调用语法。

## 3. 方案选择

采用“Claude 显式调用薄入口 + 一份共享核心 `SKILL.md` + 双平台发布元数据”。

### 3.1 被选方案

- Claude marketplace 继续以 `plugins/<plugin>` 为插件根；根目录
  `skills/<skill-name>/SKILL.md` 是薄入口，保留
  `disable-model-invocation: true` 与 Claude 工具声明。
- Codex marketplace 以 `plugins/<plugin>/codex` 为插件根；其中
  `skills/<skill-name>/SKILL.md` 是唯一核心流程，不包含 Claude-only frontmatter，
  并通过 Codex skill 校验。
- Claude 薄入口只负责确认原生 slash 入口、声明当前宿主为 Claude Code，并通过
  `${CLAUDE_PLUGIN_ROOT}` 完整读取同插件 `codex/skills/.../SKILL.md` 后执行；
  读取失败时停止，不复制核心业务步骤。
- Codex 为核心 skill 增加 `agents/openai.yaml`，设置
  `policy.allow_implicit_invocation: false`。
- 正常打包下的宿主身份有可观察来源：Claude 由薄入口显式声明，Codex 由
  `codex/` 插件根直接加载。不能根据项目中已有的 `CLAUDE.md` 或 `AGENTS.md`
  猜测宿主；若核心流程脱离上述入口被单独读取，停止写入。
- Claude 继续通过 `/chinese:init` 与 `/sync:docs` 显式调用；Codex 继续通过
  `$chinese:init` 与 `$sync:docs` 或 `/skills` 显式选择。

### 3.2 未选方案

- **平台各维护一份完整 SKILL**：能分别保留专属 frontmatter，但公共逻辑重复，
  长期容易漂移。
- **单个 SKILL 同时服务两个宿主**：改动最少，但为通过 Codex
  `quick_validate.py` 必须移除 `disable-model-invocation`，正文措辞无法等价替代
  Claude 的手动调用硬开关。
- **保留 Claude frontmatter、只补 Codex manifest**：Codex
  `quick_validate.py` 会继续拒绝 `disable-model-invocation`，不满足原生兼容目标。
- **完全迁移为 Codex-only**：会破坏现有 Claude Code 用户和原命令，违反需求。

## 4. 发布结构

```text
My-Skills/
├── .claude-plugin/
│   └── marketplace.json
├── .agents/
│   └── plugins/
│       └── marketplace.json
├── plugins/
│   ├── chinese/
│   │   ├── .claude-plugin/plugin.json
│   │   ├── skills/init/SKILL.md
│   │   └── codex/
│   │       ├── .codex-plugin/plugin.json
│   │       └── skills/init/
│   │           ├── SKILL.md
│   │           └── agents/openai.yaml
│   └── sync/
│       ├── .claude-plugin/plugin.json
│       ├── skills/docs/SKILL.md
│       └── codex/
│           ├── .codex-plugin/plugin.json
│           └── skills/docs/
│               ├── SKILL.md
│               └── agents/openai.yaml
├── AGENTS.md
├── CLAUDE.md
├── HANDOFF.md
├── README.md
└── tests/validate-plugin.ps1
```

### 4.1 Marketplace

- `.claude-plugin/marketplace.json` 保留 Claude Code 格式和两个相对路径 source。
- `.agents/plugins/marketplace.json` 使用 Codex 原生格式：
  - 顶层 `name` 与 `interface.displayName`；
  - 每个条目含 `source.source`、`source.path`；
  - 每个条目含 `policy.installation`、`policy.authentication`、`category`。
- Claude marketplace 指向 `./plugins/chinese` 与 `./plugins/sync`。
- Codex marketplace 指向 `./plugins/chinese/codex` 与
  `./plugins/sync/codex`。

### 4.2 Plugin manifest

- `chinese`：`1.0.0` 升至 `1.1.0`。
- `sync`：`1.1.0` 升至 `1.2.0`。
- 同一插件父目录的 `.claude-plugin/plugin.json` 与 `codex/.codex-plugin/plugin.json`
  使用相同版本和相同平台中性核心描述。
- Codex manifest 补齐当前 validator 要求的作者和 interface 元数据，但不虚构图标、隐私政策或不存在的能力。

## 5. `chinese` 运行设计

### 5.1 共同前置

1. Claude 只能由带 `disable-model-invocation: true` 的 `/chinese:init` 薄入口进入；
   Codex 只能由 `allow_implicit_invocation: false` 的 `$chinese:init` 或 `/skills`
   选择进入。核心流程脱离这两种入口时不写文件。
2. Claude 薄入口完整读取共享核心并显式传递 Claude 宿主；Codex 直接加载
   `codex/` 插件根的核心。因此不通过项目文件猜宿主。
3. 在 Git 仓库中用 `git rev-parse --show-toplevel` 定位项目根；非 Git 项目回退到当前工作目录。
4. 所有现有文件均保留未纳入哨兵区块的内容。
5. 若只发现开始或结束单边哨兵，停止修改对应文件并报告，避免吞掉用户内容。

### 5.2 Claude Code 分支

- 幂等更新项目根 `.claude/settings.json` 的 `language: "chinese"`，保留其它键。
- 幂等维护项目根 `CLAUDE.md` 中的 `chinese:init` 哨兵区块。
- 不修改 `AGENTS.md`。

### 5.3 Codex 分支

- 幂等维护项目根 `AGENTS.md` 中的 `chinese:init` 哨兵区块。
- 不创建不存在的 `.codex/settings.json` 或 `language` 配置。
- 不修改 `.claude/settings.json` 或 `CLAUDE.md`。
- 若根目录存在 `AGENTS.override.md`，报告其可能遮蔽 `AGENTS.md`；不自动修改 override 文件。

## 6. `sync` 运行设计

### 6.1 现场收集

- 只从 Claude `/sync:docs` 手动薄入口或 Codex `$sync:docs`/`/skills`
  显式入口进入；核心流程脱离入口时不写文件。
- 先定位项目根。
- 默认只读取不含正文的安全元数据，包括 Git status、name-status、stat、
  numstat，以及不含 commit subject 的 hash/date 历史；旧 `HANDOFF.md` 和
  当前对话也必须先经过敏感信息筛查。
- raw diff 或测试输出只有在同一个本地调用内完成捕获、扫描和完整脱敏后才能
  返回；Windows PowerShell 5.1 使用 `System.Diagnostics.Process` 或等价的
  stdout/stderr 隔离机制，不让原始内容先进入任务上下文。
- raw 内容优先只保留在本地进程内存；若必须使用系统临时文件，只有在精确路径
  和 reparse point 安全检查通过后才能清理，并在清理后断言目标不存在。
- 过滤、子命令或清理失败时 fail closed，不回显 raw 内容；只返回固定错误摘要
  和非敏感路径，保留现场供诊断。
- 实时 Git、测试和文件状态优先于旧 HANDOFF；旧 HANDOFF 只作为线索。
- 非 Git 项目跳过 Git 命令，仍可依据对话与文件生成交接。

### 6.2 HANDOFF

- 继续快照式整体重写，保持现有固定结构。
- 同一事实只出现一次。
- 明确区分已完成、进行中和未验证事项，不把计划或旧交接写成当前事实。

### 6.3 新任务续接

- Claude Code：继续在 `CLAUDE.md` 幂等维护独占一行的 `@HANDOFF.md`。
- Codex：在 `AGENTS.md` 幂等维护 `sync:docs` 哨兵区块，要求新任务开始时先读取项目根 `HANDOFF.md`，并在冲突时以实时 Git、测试和文件状态为准。
- Codex 不使用裸 `@HANDOFF.md`，因为其 AGENTS 机制没有定义 Claude 的文件导入语法。
- 若存在 `AGENTS.override.md`，仅报告遮蔽风险，不自动修改。

### 6.4 刷新与收敛其它文档

- 保留现有日志型跳过、聚焦本次主题、`过时`/`可收敛`/`可合并`、不丢信息和受众边界规则。
- 建议项使用稳定编号。
- 初次调用列出建议后停止，未经确认不改其它文档。
- 继续执行时使用平台原生显式入口：
  - Claude：`/sync:docs 应用 1,3`
  - Codex：`$sync:docs 应用 1,3`
- 完成后先读取相关安全 diff 元数据；只有在上述证据闸门内完成同调用捕获、
  扫描和完整脱敏后，才能返回正文摘要。
- Skill 自身不执行 commit。

## 7. 仓库文档处理

- 保留并更新用户新增的 `AGENTS.md`，删除无效的裸 `@HANDOFF.md`，改为明确读取指令。
- 恢复 `CLAUDE.md` 与 `.claude/settings.json`，保持仓库自身的 Claude Code 兼容。
- README 并排说明：
  - Claude marketplace 安装、调用、升级；
  - Codex marketplace 安装、调用、升级；
  - 两平台共用同一 Git 仓库但入口语法不同。
- 更新 HANDOFF，使其反映实际 Git 状态、新版本和新的验证/升级命令。
- 旧设计文档保留为历史记录；本设计覆盖其中 Claude-only 的发布与运行假设。

## 8. 验证设计

### 8.1 Skill TDD / 前向测试

每个 skill 按顺序完成 RED、GREEN、REFACTOR：

1. 用当前版本运行 Codex 场景，记录它只写 Claude 文件或只挂 `CLAUDE.md` 的基线失败。
2. 先运行无新指导的控制组并保存逐次证据，再增加 Claude 薄入口和 Codex 核心。
3. 在隔离临时目录中由新上下文 agent 执行相同场景，确认 Codex 分支正确。
4. 补充边界场景，关闭新发现的歧义或绕过。
5. 完成一个 skill 的验证后再修改下一个。

### 8.2 结构验证

- 扩展 `tests/validate-plugin.ps1`：
  - 验证两套 marketplace；
  - 验证四个 plugin manifest；
  - 验证同一插件两套版本一致；
  - 验证同一插件两套平台中性 description 完全一致；
  - 验证 Codex marketplace policy/category/source；
  - 验证 Claude 薄入口保留 `disable-model-invocation: true` 并引用共享核心；
  - 验证 `agents/openai.yaml` 禁止隐式调用；
  - 验证 Codex 核心 SKILL 不包含 Claude-only frontmatter；
  - 保留 sync 去重能力的防回退检查。
- 用 `PYTHONUTF8=1` 对两个 `codex/skills/...` 核心运行 Codex
  `quick_validate.py`。
- 对两个 `plugins/<name>/codex` 插件根运行 Codex `validate_plugin.py`。
- 若可在不改变用户 Claude 安装状态的前提下调用官方 Claude validator，则运行；否则明确记录本机没有 Claude CLI，不声称完成 Claude 运行时 smoke test。

### 8.3 行为场景

`chinese`：

- Claude：新建/合并 `.claude/settings.json`，保留 `CLAUDE.md` 内容，重复运行幂等。
- Codex：新建/保留 `AGENTS.md`，重复运行幂等。
- 从仓库子目录调用仍修改项目根。
- 单边哨兵时停止并保留原内容。

`sync`：

- Claude：生成 HANDOFF 并挂 `CLAUDE.md`。
- Codex：生成 HANDOFF 并写入 AGENTS 读取指令。
- HANDOFF 快照重写、同一事实不重复。
- 不确认时其它文档零改动。
- 覆盖超集合并、重复收敛、日志型跳过、受众边界、不确认不改、HANDOFF 自身去重六场景。
- 旧 HANDOFF 与实时 Git 冲突时，以实时证据为准。

## 9. 发布与本机升级

本节所列流程已执行完成：实现已发布到远端 `main`，本机 Codex marketplace
和两个插件已升级，并已用全新 `codex exec --ephemeral` 进程完成 Codex
runtime smoke。Claude CLI 未安装，因此 Claude runtime smoke 未执行。

### 9.1 发布前门槛

- 只提交本设计和后续明确列入范围的文件。
- 检查没有意外删除 Claude marketplace、manifest 或项目指令文件。
- 全部结构验证、行为场景与 diff 复核通过。
- 不在同一版本号下覆盖内容。

### 9.2 发布

```powershell
git push origin main
```

该 Git 仓库同时是 Claude 和 Codex marketplace 源；一次 push 发布两套入口。

### 9.3 本机 Codex 升级

```powershell
codex plugin marketplace upgrade my-skills
codex plugin add chinese@my-skills
codex plugin add sync@my-skills
```

随后核对：

- marketplace revision 指向本次发布提交；
- `chinese@my-skills` 为 `1.1.0`；
- `sync@my-skills` 为 `1.2.0`；
- cache 中包含 `.codex-plugin/plugin.json` 与更新后的 skill；
- 用新的 `codex exec --ephemeral` 进程在隔离仓库实际调用两个 skill，
  验证发现、平台隔离和幂等哨兵。

本机未安装 Claude CLI，因此不修改或伪造 Claude 本机安装状态；README 提供 Claude 正常升级命令。

## 10. 非目标

- 不向官方公共 Plugins Directory 提交审核。
- 不为 Codex 虚构第三方 slash alias。
- 不添加 `.codex/settings.json` 语言字段。
- 不让 skill 自动 commit。
- 不直接编辑 `~/.codex/plugins/cache` 或插件注册配置。
- 不顺带重构与双平台兼容无关的历史设计和文档。

## 11. 平台依据

- Claude Code skills：
  https://code.claude.com/docs/en/slash-commands
- Claude Code plugin 结构与 component path：
  https://code.claude.com/docs/en/plugins-reference
- Codex plugin 构建与 native marketplace：
  https://learn.chatgpt.com/docs/build-plugins
- Codex plugin CLI：
  https://learn.chatgpt.com/docs/developer-commands
