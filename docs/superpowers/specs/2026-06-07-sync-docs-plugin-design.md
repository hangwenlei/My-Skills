# 设计文档：`sync` 插件（命令 `/sync:docs`）

- 日期：2026-06-07
- 状态：已确认，待制定实现计划
- 仓库：https://github.com/hangwenlei/My-Skills.git（marketplace `my-skills` 的第二个插件）

## 1. 背景与目标

用 Claude Code 开发某个项目到一半时，希望停下来运行一个命令，把「当前开发现场」固化进项目文档；之后新开一个 session、重新导入该项目文件夹，能基于这些文档**无缝续接对话**。同时顺带把项目里其它相关文档刷新到最新状态。

## 2. 调研结论（决定方案的关键事实）

1. **Claude Code 原生会话恢复**（`claude --continue` / `--resume` / `/resume`，transcript 存 `~/.claude/projects/<项目>/<id>.jsonl`）**绑本机、绑仓库路径、靠原始历史**，无法跨机器/跨仓库/换人续接，也不是「项目内文档」。因此需要**文档化**的方案。
2. **新 session 自动加载的官方抓手是 `CLAUDE.md`**（启动时自动读取），且 CLAUDE.md 支持 `@路径` 形式的**导入**，会在启动时把被导入文件的内容一并展开进上下文。这是实现「无缝续接」的关键。
3. **已有现成做法但不贴合**：`HANDOFF.md` 约定、社区插件（如 `thepushkarp/handoff`）、`dotclaude` 的 `/handoff`；Anthropic 官方 `consolidate-memory` 是「记忆整理/去重」而非「会话续接」。没有「中文 + 在本商店 + 含 propose-confirm 文档刷新」的方案，故自研。

## 3. 关键决策

| 决策点 | 结论 | 理由 / 被否方案 |
|--------|------|----------------|
| 产出范围 | **交接快照 + 刷新其它文档** | 既要新 session 续接，又要项目文档保持最新。 |
| 刷新其它文档的控制 | **propose-confirm**：先列「建议更新的文档+原因+拟改要点」，用户确认后才改 | 自动改 README/设计文档等手写文档有误改风险，必须可控。否决「自动改完再报告」「固定清单」。 |
| 续接机制 | **生成 `HANDOFF.md` + 在 `CLAUDE.md` 加 `@HANDOFF.md` 导入** | 新 session 启动自动加载 CLAUDE.md → 连带读入 HANDOFF.md，零操作续接；易变进度与稳定规则分文件存放、互不污染。否决「写进 CLAUDE.md 区块」（混入易变内容）、「只生成不挂自动加载」（不够无缝）。 |
| 命令形式 | **`/sync:docs`**（plugin 名 `sync`、skill 名 `docs`） | 贴合「文档同步」；插件命令强制带命名空间，无法做裸命令。 |
| 是否自动 commit | **不自动 commit** | 提交权留给用户；改完用 `git diff` 复核后自行提交。 |
| HANDOFF.md 写法 | **快照式整体重写**（每次重写，非追加） | 避免进度越堆越乱、过时信息残留。 |
| 模型自动触发 | **关闭**（`disable-model-invocation: true`） | 显式操作，仅在用户手动 `/sync:docs` 时运行。 |

## 4. 架构与目录结构

在现有 marketplace 内新增 `sync` 插件：

```
My-Skills/
├── .claude-plugin/marketplace.json     # 需更新：plugins 数组新增 sync 条目
├── plugins/
│   ├── chinese/...                     # 既有
│   └── sync/                           # 新增插件
│       ├── .claude-plugin/plugin.json
│       └── skills/docs/SKILL.md        # skill 本体
├── README.md                           # 需更新：补充 sync 插件说明
└── tests/validate-plugin.ps1           # 需扩展：覆盖 sync 插件
```

## 5. 运行时行为（`/sync:docs` 五步逻辑）

对**当前工作目录所在项目**执行，全程用简体中文汇报：

### 步骤 1：收集现场状态
- 运行并阅读：`git status`、未提交改动的 `git diff`（含 `--staged`）、最近提交 `git log --oneline -15`。
- 读取已存在的 `HANDOFF.md`（若有）。
- 结合当前对话上下文（本 session 做了什么、决策、下一步）。

### 步骤 2：生成/更新项目根 `HANDOFF.md`（快照式整体重写）
固定结构（缺项可省略，但顺序固定），文件顶部写「> 更新时间：<当前时间>」：
- **概览**：一句话——项目在做什么、当前处于哪个阶段。
- **✅ 已完成**：具体条目（尽量带文件路径）。
- **🔄 进行中**：正在做的事、为什么卡住或待决策。
- **⏭️ 下一步**：新 session 第一件应该做的事。
- **🧠 关键决策与理由**：为什么选 X 不选 Y。
- **📁 重要文件**：路径 + 作用。
- **⚠️ 注意事项/坑**：易踩的坑、约束。
- **▶️ 常用命令**：如何运行/构建/测试。

### 步骤 3：挂自动加载（编辑 `CLAUDE.md`）
- 若 `CLAUDE.md` 不含 `@HANDOFF.md` 这一行：在文件末尾追加一行 `@HANDOFF.md`（前置一个空行）。
- 若 `CLAUDE.md` 不存在：创建之，写入 `# CLAUDE.md` + 空行 + `@HANDOFF.md`。
- 若已含该行：不重复添加（幂等）。
- 目的：新 session 启动自动加载 CLAUDE.md → 连带把 HANDOFF.md 内容读入上下文。

### 步骤 4：刷新其它文档（propose-confirm）
- 基于步骤 1 的改动扫描，列出一张**建议清单**：每项 = 文档路径 + 为什么需要更新 + 拟改要点。
- **暂停并等待用户确认**（用户可全选/选部分/全不选）。
- 仅对用户确认的文档执行更新；未确认的一律不动。

### 步骤 5：汇报
- 列出创建/更新的文件（HANDOFF.md、CLAUDE.md、以及已确认刷新的文档）。
- 提示：用 `git diff` 复核，自行决定 commit；新 session 会自动加载 HANDOFF.md 实现续接。

## 6. 配置文件内容

### 6.1 `.claude-plugin/marketplace.json`（更新）
在 `plugins` 数组追加：
```json
{
  "name": "sync",
  "source": "./plugins/sync",
  "description": "固化开发现场到 HANDOFF.md 并刷新文档，支持新 session 无缝续接"
}
```

### 6.2 `plugins/sync/.claude-plugin/plugin.json`（新增）
```json
{
  "name": "sync",
  "version": "1.0.0",
  "description": "把当前开发现场固化进 HANDOFF.md 并挂到 CLAUDE.md 自动加载，同时按确认刷新其它文档，便于新 session 无缝续接",
  "author": { "name": "hangwenlei" }
}
```

### 6.3 `plugins/sync/skills/docs/SKILL.md`（新增，frontmatter 要点）
```yaml
---
name: docs
description: 固化当前开发现场到 HANDOFF.md、在 CLAUDE.md 挂 @HANDOFF.md 自动加载，并按 propose-confirm 刷新其它文档。仅在用户手动运行 /sync:docs 时执行。
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Bash
---
```
正文：用中文写明第 5 节五步逻辑 + 第 2 节 HANDOFF.md 模板。
> 实现注意：步骤 1 需运行 git 命令读取状态，故需放行 shell 工具（`Bash`；若环境为 PowerShell 则以对应 shell 运行 `git`）。`@HANDOFF.md` 导入语法须在实现时实测确认（CLAUDE.md 的 `@路径` 导入）。

## 7. README（更新要点）
新增「sync 插件」小节：用途、安装（`/plugin install sync@my-skills`）、用法（`/sync:docs`）、效果（生成 HANDOFF.md + 挂 CLAUDE.md 自动加载 + 确认式刷新文档）、以及与 `chinese` 相同的「CLI 安装 / 客户端共用 `~/.claude` 重启生效」说明。

## 8. 测试与验证
1. **结构校验**：扩展 `tests/validate-plugin.ps1`——校验 `plugins/sync/.claude-plugin/plugin.json`、`plugins/sync/skills/docs/SKILL.md` 存在且字段正确；marketplace.json 的 plugins 含 `sync` 且 source 路径存在。
2. **功能性验证**（临时 git 项目，手动按 SKILL.md 步骤实测）：
   - 在有若干未提交改动的临时仓库运行 → 生成 HANDOFF.md（含模板各节）、CLAUDE.md 出现 `@HANDOFF.md`。
   - **幂等**：再次运行 → CLAUDE.md 不重复出现 `@HANDOFF.md`；HANDOFF.md 被整体重写而非堆叠。
   - 无 CLAUDE.md 的目录运行 → 正确创建含 `@HANDOFF.md` 的 CLAUDE.md。
   - propose-confirm：验证「先列清单、不确认不改」的行为（用户拒绝时其它文档零改动）。

## 9. 安装与环境说明
同 `chinese` 插件：`/plugin` 仅 Claude Code CLI 可用；CLI 与 GUI 客户端共用 `~/.claude/`，CLI 装好后重启客户端即生效。安装：`/plugin marketplace add hangwenlei/My-Skills` + `/plugin install sync@my-skills`，命令 `/sync:docs`。

## 10. 非目标（YAGNI）
- 不做单独的 `/resume` 命令（靠 CLAUDE.md `@import` 自动加载即可续接）。
- 不自动 commit。
- 不做跨机器/云端同步（靠 git 仓库本身携带 HANDOFF.md 即可跨机/跨人）。
- 不自动改未经确认的文档。
