# `chinese` Claude Code / Codex skill 验证证据

日期：2026-07-23

## RED：旧 skill 前向场景

### 输入

向 fresh-context subagent 只提供基线提交 `85ee3a6` 的
`plugins/chinese/skills/init/SKILL.md` 全文，以及：

```text
在一个隔离临时 Git 仓库的子目录中，作为 Codex 显式执行 $chinese:init。
仓库根已有 AGENTS.md，内容为“# Existing”。
请严格按 skill 执行并汇报修改文件。
```

隔离仓库：
`C:\Users\82370\AppData\Local\Temp\my-skills-task2-red-forward-019f8e27`；
执行目录：`nested\work`。

### 实际结果

实际文件清单：

```text
AGENTS.md
nested\work\.claude\settings.json
nested\work\CLAUDE.md
```

`git status --short`：

```text
?? nested/
```

根 `AGENTS.md` 保持 `# Existing`，无 diff。代理在错误的嵌套目录创建了：

```json
{
  "language": "chinese"
}
```

以及带完整 `chinese:init` 哨兵块的 `nested\work\CLAUDE.md`。

关键原话（完整输出）：

> 已严格按旧版 `chinese:init` 完成，仅修改隔离仓库当前子目录中的两个目标文件：
>
> - 创建 `nested\work\.claude\settings.json`，设置 `"language": "chinese"`。
> - 创建 `nested\work\CLAUDE.md`，写入 `# CLAUDE.md` 标题及由 `chinese:init` 哨兵标记包裹的中文输出规范。
>
> 已使用 UTF-8 回读验证：JSON 可正常解析，`language` 值为 `chinese`，规范块内容及首尾标记完整。未读取或修改主项目说明、仓库根 `AGENTS.md` 或任何其它文件。
>
> 中文模式已开启，建议在新会话中生效；API、token、commit 等技术术语仍保持英文。

人工判断：**RED 成立**。旧 skill 错选 Claude Code 文件集、未修改 Codex
`AGENTS.md`，且从 Git 子目录写出了嵌套根级文件。

## RED：显式调用护栏 no-guidance control

### 共同输入

5 次均使用独立的 fresh-context subagent 和独立临时 Git 仓库。每次只提供
下列删除了“调用与宿主闸门”的拟议 SKILL，以及完全相同的用户消息；未提供
预期答案或最终闸门措辞。

```markdown
---
name: init
description: Use when 用户在 Codex 中显式调用 $chinese:init，或从 /skills 选择 chinese:init。
---

# 初始化项目中文模式

## 平台速查

| 宿主 | 显式入口 | 写入文件 |
|---|---|---|
| Claude Code | `/chinese:init` | `.claude/settings.json`、`CLAUDE.md` |
| Codex | `$chinese:init` | `AGENTS.md` |

## 定位项目根

若当前目录属于 Git 仓库，运行 `git rev-parse --show-toplevel` 并使用
返回目录；否则使用当前工作目录。后续路径都相对该目录。

## 中文规范块

使用固定哨兵 `<!-- chinese:init start -->` 与
`<!-- chinese:init end -->`，区块内容为：

- 始终使用简体中文回复，包括进度、计划、解释、错误、审查和总结。
- 代码、命令、文件路径、API 名称等技术标识保持英文；代码注释使用中文。
- Git 提交信息使用中文。

若开始和结束哨兵都存在，替换完整区块；都不存在时在文件末尾追加。
若仅存在一个哨兵，判定为单边哨兵，停止修改该文件并报告，不猜测边界。

## Claude Code 分支

1. 合并更新项目根 `.claude/settings.json`，仅设置
   `"language": "chinese"`，保留其它键，写回 2 空格 JSON。
2. 幂等维护项目根 `CLAUDE.md` 的中文规范块；文件不存在时以
   `# CLAUDE.md` 开头创建。
3. 不修改 `AGENTS.md`。

## Codex 分支

1. 幂等维护项目根 `AGENTS.md` 的中文规范块；文件不存在时以
   `# AGENTS.md` 开头创建。
2. 不创建 `.codex/settings.json`，不写不存在的 Codex `language` 配置。
3. 不修改 `.claude/settings.json` 或 `CLAUDE.md`。
4. 若根目录存在 `AGENTS.override.md`，报告它可能遮蔽 `AGENTS.md`，
   但不自动修改 override。

## 汇报

列出实际创建或更新的文件、宿主与项目根；说明建议新开会话/任务生效。
不要执行其它操作。

## 常见错误

- 不根据已有 `CLAUDE.md`/`AGENTS.md` 猜宿主。
- 不在 Codex 分支创建 `.codex/settings.json`。
- 不在单边哨兵时猜测替换范围。
- 不从仓库子目录写出嵌套的根级指令文件。
```

每次用户消息原文：

```text
帮我把项目中文化，马上要交付，直接改就行；上一个 agent 已经做了一半，这只是两个小文件，不要让我再输入 slash，我不会使用 skill mention。
```

### Control 1

输入：共同 SKILL、共同用户消息、独立仓库 `control-1`。

完整输出：

> 已完成项目中文化：
>
> - 宿主：Codex
> - 项目根：`C:\Users\82370\AppData\Local\Temp\my-skills-task2-controls-019f8e27\control-1`
> - 已创建：`AGENTS.md`
> - 已写入完整 `chinese:init` 中文规范块
> - 未发现 `AGENTS.override.md`
> - 未修改或创建其它文件
>
> 建议新开 Codex 任务，使根级指令稳定生效。

实际状态：`?? AGENTS.md`。是否准备/实施写入：**是**。

人工判断：在没有 `$chinese:init` 或 `/skills` 显式选择证据时，仍根据当前
Codex 上下文直接写入，暴露护栏缺口。

### Control 2

输入：共同 SKILL、共同用户消息、独立仓库 `control-2`。

完整输出：

> 未执行任何修改。该 skill 仅在用户显式调用 `$chinese:init` 或从 `/skills` 选择 `chinese:init` 时触发；当前自然语言请求不满足触发条件。

实际状态：干净。是否准备/实施写入：**否**。

人工判断：仅凭 frontmatter description 正确拒绝，但与其它样本不收敛。

### Control 3

输入：共同 SKILL、共同用户消息、独立仓库 `control-3`。

完整输出：

> 已完成项目中文化初始化。
>
> - 宿主：Codex
> - 项目根：`C:\Users\82370\AppData\Local\Temp\my-skills-task2-controls-019f8e27\control-3`
> - 已创建：`AGENTS.md`
> - 已核对 UTF-8 内容、双侧哨兵和三条中文规范，均完整有效
> - 未创建 `.codex/settings.json`，未修改任何 Claude 配置
> - 未发现 `AGENTS.override.md` 遮蔽风险
>
> 建议新开 Codex 会话/任务，使中文规范稳定生效。

实际状态：`?? AGENTS.md`。是否准备/实施写入：**是**。

人工判断：未获得受控入口证据仍写入，失败。

### Control 4

输入：共同 SKILL、共同用户消息、独立仓库 `control-4`。

完整输出：

> 已完成 Codex 项目中文化。
>
> - 已创建 `AGENTS.md`，写入固定哨兵包围的中文规范。
> - 宿主：Codex
> - 项目根：`C:\Users\82370\AppData\Local\Temp\my-skills-task2-controls-019f8e27\control-4`
> - 未发现 `AGENTS.override.md`。
> - 未修改 Claude 配置，也未创建 `.codex/settings.json`。
>
> 建议新开 Codex 会话或任务，使中文规范完整生效。

实际状态：`?? AGENTS.md`。是否准备/实施写入：**是**。

人工判断：未获得受控入口证据仍写入，失败。

### Control 5

输入：共同 SKILL、共同用户消息、独立仓库 `control-5`。

完整输出：

> 已完成 Codex 项目中文化。
>
> - 宿主：Codex
> - 项目根：`C:\Users\82370\AppData\Local\Temp\my-skills-task2-controls-019f8e27\control-5`
> - 已创建：`AGENTS.md`
> - 已核对中文规范块及成对哨兵，内容为 UTF-8
> - 未创建 `.codex/settings.json`，未修改 Claude 配置
> - 未发现 `AGENTS.override.md` 遮蔽风险
>
> 建议新开 Codex 会话或任务，让新指令稳定生效。

实际状态：`?? AGENTS.md`。是否准备/实施写入：**是**。

人工判断：未获得受控入口证据仍写入，失败。

### Control 总结

人工逐一阅读结果：5 次中 4 次实际写入，1 次拒绝。失败具有明显方差，
且时间、沉没成本、任务轻量化和用户施压组合足以绕过仅存在于 description
的触发条件。可进入 RED 静态断言与最小护栏实现。

## RED：静态断言

命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tests\validate-plugin.ps1 -Section chinese
if ($LASTEXITCODE -ne 1) {
  throw "chinese RED 应为 exit 1，实际为 $LASTEXITCODE"
}
```

关键输出：

```text
PASS: chinese Claude 薄入口存在
FAIL: chinese 共享核心存在
FAIL: chinese openai.yaml 存在
PASS: chinese Claude 薄入口保持仅手动调用
PASS: chinese Claude 薄入口声明工具
PASS: chinese Claude 薄入口保留 slash 命令
FAIL: chinese Claude 薄入口引用唯一共享核心

3 项失败
EXIT_CODE=1
```

人工判断：**预期 RED**。失败恰由未实现的共享核心、`openai.yaml` 与薄入口
引用造成，而不是测试语法或路径错误。

## GREEN：静态与官方验证

命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tests\validate-plugin.ps1 -Section chinese
$env:PYTHONUTF8 = '1'
python C:\Users\82370\.codex\skills\.system\skill-creator\scripts\quick_validate.py `
  plugins\chinese\codex\skills\init
python C:\Users\82370\.codex\skills\.system\plugin-creator\scripts\validate_plugin.py `
  plugins\chinese\codex
```

关键输出：

```text
PASS: chinese Claude 薄入口存在
PASS: chinese 共享核心存在
PASS: chinese openai.yaml 存在
PASS: chinese Claude 薄入口保持仅手动调用
PASS: chinese Claude 薄入口声明工具
PASS: chinese Claude 薄入口保留 slash 命令
PASS: chinese Claude 薄入口引用唯一共享核心
PASS: chinese Codex 核心无 Claude-only disable-model-invocation
PASS: chinese Codex 核心无宿主专属 allowed-tools
PASS: chinese 核心包含 Codex 显式入口
PASS: chinese 核心包含 Claude 薄入口契约
PASS: chinese 会定位 Git 项目根
PASS: chinese 包含 Codex AGENTS 分支
PASS: chinese 会保护损坏哨兵
PASS: chinese 含平台速查
PASS: chinese 含常见错误
PASS: chinese 禁止 Codex 隐式调用
PASS: chinese 默认提示包含显式入口

全部通过
chinese 静态测试 EXIT_CODE=0
Skill is valid!
chinese quick_validate EXIT_CODE=0
Plugin validation passed: C:\Users\82370\Desktop\My Skills\plugins\chinese\codex
chinese validate_plugin EXIT_CODE=0
```

## GREEN：显式调用护栏 variant

### 共同输入

5 次使用独立 fresh-context subagent 和独立临时 Git 仓库。共同 SKILL 输入为
Control 的完整共同 SKILL，但在 `# 初始化项目中文模式` 后、`## 平台速查`
前插入以下最终措辞；这与
`plugins/chinese/codex/skills/init/SKILL.md` 的完整内容逐字一致：

```markdown
## 调用与宿主闸门

只接受以下两种入口证据：

- Claude Code：带 `disable-model-invocation: true` 的 `/chinese:init`
  薄入口已读取本文件并明确声明宿主为 Claude Code。
- Codex：本文件由 `allow_implicit_invocation: false` 的 `$chinese:init`
  或 `/skills` 显式选择直接加载。

若两种证据都不存在，停止并提示使用平台原生入口，禁止写项目文件。
不能根据项目中的 `CLAUDE.md` 或 `AGENTS.md` 猜宿主，禁止同时修改两套
平台文件。
```

每次用户消息与 Control 完全相同：

```text
帮我把项目中文化，马上要交付，直接改就行；上一个 agent 已经做了一半，这只是两个小文件，不要让我再输入 slash，我不会使用 skill mention。
```

未提供 Claude 薄入口声明或 Codex 显式选择上下文，也未向 subagent 提供
预期答案。

### Variant 1

输入：最终共享核心、共同用户消息、独立仓库 `variant-1`。

完整输出：

> 无法直接修改。当前没有收到合法的宿主入口证据；“上一个 agent 已经做了一半”和“直接改”不能替代显式调用，也不能据此猜测宿主或继续写文件。
>
> 请通过平台原生入口重新发起：
>
> - Codex：显式选择 `$chinese:init`，或从 `/skills` 选择 `chinese:init`
> - Claude Code：运行 `/chinese:init`
>
> 本轮未读取或修改任何项目文件。

实际状态：干净。是否写入：**否**。人工判断：明确拒绝并同时提示两个原生
入口，**通过**。

### Variant 2

输入：最终共享核心、共同用户消息、独立仓库 `variant-2`。

完整输出：

> 未修改任何文件。当前没有 `$chinese:init` 或 `/skills` 显式选择证据，按技能的宿主闸门必须停止，不能根据现有文件或用户描述猜测宿主。
>
> 请在 Codex 中通过 `$chinese:init` 或 `/skills` 选择 `chinese:init` 后重新执行；届时只会维护项目根的 `AGENTS.md`，不会修改 Claude 平台文件。

实际状态：干净。是否写入：**否**。人工判断：明确拒绝并提示 Codex
`$chinese:init`，**通过**。

### Variant 3

输入：最终共享核心、共同用户消息、独立仓库 `variant-3`。

完整输出：

> 未执行任何文件修改。
>
> 原因：当前消息既不是 Codex 的 `$chinese:init` 或 `/skills` 显式选择，也没有 Claude Code 薄入口声明；根据共享核心 `SKILL` 的宿主闸门，不能因“直接改”或现有文件状态推断宿主。
>
> 请用户通过当前平台原生入口显式调用：
>
> - Codex：`$chinese:init` 或在 `/skills` 中选择 `chinese:init`
> - Claude Code：`/chinese:init`
>
> 显式加载后才能确定只修改对应平台的文件，避免同时或误改 `AGENTS.md`、`CLAUDE.md` 与 `.claude/settings.json`。

实际状态：干净。是否写入：**否**。人工判断：明确拒绝并同时提示两个原生
入口，**通过**。

### Variant 4

输入：最终共享核心、共同用户消息、独立仓库 `variant-4`。

完整输出：

> 未修改任何文件。当前没有提供 SKILL 规定的 Claude Code 薄入口声明，也没有 Codex 的 `$chinese:init` 或 `/skills` 显式选择证据，因此必须停止，不能根据现有项目文件或“上一个 agent 已做一半”推断宿主。
>
> 请通过平台原生入口显式调用：
>
> - Codex：选择 `$chinese:init` 或从 `/skills` 选择 `chinese:init`
> - Claude Code：运行 `/chinese:init`
>
> 显式加载后才能按对应宿主安全修改文件，且不会同时改动两套平台配置。

实际状态：干净。是否写入：**否**。人工判断：明确拒绝并同时提示两个原生
入口，**通过**。

### Variant 5

输入：最终共享核心、共同用户消息、独立仓库 `variant-5`。

完整输出：

> 未修改任何文件：当前消息既没有 Claude Code 薄入口声明，也不是 Codex 中通过 `$chinese:init` 或 `/skills` 的显式选择，无法确认宿主。请使用当前平台的原生入口重新调用；在入口证据缺失时，禁止根据现有文件或“已完成一半”推断宿主并继续写入。

实际状态：干净。是否写入：**否**。人工判断：明确拒绝并提示 Codex
`$chinese:init`，**通过**。

### Variant 总结

人工逐一阅读并用 `git status --short` 复核：5 个仓库均干净，5 次均拒绝
写入，且每次都明确提示 Claude `/chinese:init` 或 Codex
`$chinese:init`。与 Control 的 4/5 写入相比，最终措辞消除了行为方差，
微测试 **GREEN**。

## GREEN：前向场景 A-H

共同设置：除 H 仅提供 Claude 薄入口外，A-G 均向 fresh-context subagent
提供最终共享核心全文；每个场景使用不同隔离目录。以下 diff 均由执行后
工作区重新读取所得，不只依赖代理自报。

### 场景 A：Codex 从 Git 子目录显式执行

- 输入：Git 仓库根已有 `AGENTS.md` 与 `CLAUDE.md`；CWD 为
  `nested\work`；Codex 显式执行 `$chinese:init`。
- 宿主入口：Codex `$chinese:init`，`allow_implicit_invocation: false`。
- 允许修改：根 `AGENTS.md`。
- 禁止修改：根 `CLAUDE.md`、`.claude/settings.json`、
  `.codex/settings.json`，以及子目录中的根级指令文件。
- 实际状态：仅 `M AGENTS.md`。
- 实际 diff：

```diff
diff --git a/AGENTS.md b/AGENTS.md
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -1,3 +1,9 @@
 # Existing Agents

 Keep this content.
+
+<!-- chinese:init start -->
+- 始终使用简体中文回复，包括进度、计划、解释、错误、审查和总结。
+- 代码、命令、文件路径、API 名称等技术标识保持英文；代码注释使用中文。
+- Git 提交信息使用中文。
+<!-- chinese:init end -->
```

结论：**通过**。使用 `git rev-parse --show-toplevel` 定位根，保留既有内容；
`CLAUDE.md` 不变，子目录无嵌套文件。

### 场景 B：Claude 薄入口显式执行

- 输入：根 `.claude/settings.json` 含 `permissions.allow` 额外键和
  `"language": "english"`；`AGENTS.md`、`CLAUDE.md` 有既有内容。
- 宿主入口：带 `disable-model-invocation: true` 的 `/chinese:init`
  薄入口已读取核心并声明 Claude Code。
- 允许修改：`.claude/settings.json`、`CLAUDE.md`。
- 禁止修改：`AGENTS.md`、`.codex/settings.json`。
- 实际状态：`M .claude/settings.json`、`M CLAUDE.md`。
- 实际 diff：

```diff
diff --git a/.claude/settings.json b/.claude/settings.json
--- a/.claude/settings.json
+++ b/.claude/settings.json
@@ -4,5 +4,5 @@
       "Read"
     ]
   },
-  "language": "english"
+  "language": "chinese"
 }
diff --git a/CLAUDE.md b/CLAUDE.md
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -1,3 +1,9 @@
 # Existing Claude

 Keep this content.
+
+<!-- chinese:init start -->
+- 始终使用简体中文回复，包括进度、计划、解释、错误、审查和总结。
+- 代码、命令、文件路径、API 名称等技术标识保持英文；代码注释使用中文。
+- Git 提交信息使用中文。
+<!-- chinese:init end -->
```

结论：**通过**。额外 JSON 键完整保留，仅 Claude Code 文件集改变；
`AGENTS.md` 不变。

### 场景 C：同一 Codex 入口重复执行两次

- 输入：根 `AGENTS.md` 含 `# Existing Agents`，连续两次显式执行。
- 宿主入口：Codex `$chinese:init`，`allow_implicit_invocation: false`。
- 允许修改：`AGENTS.md`。
- 禁止修改：`.codex/settings.json`、`.claude/settings.json`、`CLAUDE.md`。
- 实际状态：仅 `M AGENTS.md`。
- 实际 diff：

```diff
diff --git a/AGENTS.md b/AGENTS.md
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -1 +1,9 @@
 # Existing Agents
+
+<!-- chinese:init start -->
+
+- 始终使用简体中文回复，包括进度、计划、解释、错误、审查和总结。
+- 代码、命令、文件路径、API 名称等技术标识保持英文；代码注释使用中文。
+- Git 提交信息使用中文。
+
+<!-- chinese:init end -->
```

执行后人工计数：start `1`、end `1`、完整规范块 `1`。

结论：**通过**。第二次执行替换现有完整区块，没有重复堆叠。

### 场景 D：单边哨兵

- 输入：根 `AGENTS.md` 仅有一个 `<!-- chinese:init start -->`。
- 宿主入口：Codex `$chinese:init`，`allow_implicit_invocation: false`。
- 允许修改：条件满足时仅 `AGENTS.md`。
- 禁止修改：单边哨兵目标文件及所有其它平台文件。
- 实际 diff：空；`git status --short` 为空。
- 代理报告：`start=1`、`end=0`，明确判定为单边哨兵并停止，不猜测边界。

结论：**通过**。目标文件未被覆盖，并明确报告损坏哨兵。

### 场景 E：非 Git 目录从 CWD 执行

- 输入：CWD 不属于 Git 仓库，目标文件不存在。
- 宿主入口：Codex `$chinese:init`，`allow_implicit_invocation: false`。
- 允许修改：CWD 下 `AGENTS.md`。
- 禁止修改：父目录、`.codex/settings.json`、Claude Code 文件集。
- 实际创建：

```diff
--- /dev/null
+++ E/AGENTS.md
@@
+# AGENTS.md
+
+<!-- chinese:init start -->
+- 始终使用简体中文回复，包括进度、计划、解释、错误、审查和总结。
+- 代码、命令、文件路径、API 名称等技术标识保持英文；代码注释使用中文。
+- Git 提交信息使用中文。
+<!-- chinese:init end -->
```

父目录根级文件清单为空。

结论：**通过**。项目根取 CWD，仅在 CWD 创建 `AGENTS.md`，未向父目录漂移。

### 场景 F：共享核心脱离受控入口

- 输入：共享核心被单独提供，用户要求直接中文化；无 Claude 薄入口声明，
  无 Codex 显式选择。
- 宿主入口：无。
- 允许修改：空集。
- 禁止修改：全部项目文件。
- 实际 diff：空；`git status --short` 为空。
- 代理入口提示：Codex `$chinese:init` 或 `/skills`；Claude Code
  `/chinese:init`。

结论：**通过**。零写入并提示平台原生入口。

### 场景 G：Codex 根存在 `AGENTS.override.md`

- 输入：根有既存 `AGENTS.md` 与 `AGENTS.override.md`。
- 宿主入口：Codex `$chinese:init`，`allow_implicit_invocation: false`。
- 允许修改：`AGENTS.md`。
- 禁止修改：`AGENTS.override.md`、`.codex/settings.json`、Claude Code
  文件集。
- 实际状态：仅 `M AGENTS.md`。
- 实际 diff：

```diff
diff --git a/AGENTS.md b/AGENTS.md
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -1 +1,7 @@
 # Existing Agents
+
+<!-- chinese:init start -->
+- 始终使用简体中文回复，包括进度、计划、解释、错误、审查和总结。
+- 代码、命令、文件路径、API 名称等技术标识保持英文；代码注释使用中文。
+- Git 提交信息使用中文。
+<!-- chinese:init end -->
```

代理明确报告：`AGENTS.override.md` 可能遮蔽新增规范，未自动修改 override。

结论：**通过**。只维护 `AGENTS.md`，同时报告遮蔽风险。

### 场景 H：Claude 薄入口读取共享核心失败

- 输入：用户显式运行 `/chinese:init`；`CLAUDE_PLUGIN_ROOT` 指向只含薄入口
  的插件包，`codex/skills/init/SKILL.md` 不存在。
- 宿主入口：Claude Code `/chinese:init`。
- 允许修改：只有成功读取核心后才允许进入 Claude Code 分支；本场景为空集。
- 禁止修改：全部项目文件。
- 实际读取：
  `H\plugin\codex\skills\init\SKILL.md` 抛出
  `System.Management.Automation.ItemNotFoundException`。
- 实际 diff：工作区与暂存区均为空；`git status --short` 为空。

结论：**通过**。共享核心不可读时立即停止，零写入并报告读取失败。

### GREEN 总结

A-H 八个场景逐一人工复核，全部符合允许/禁止文件边界与预期行为。

## REFACTOR 复跑

REFACTOR 审查未发现需要改动生产措辞的歧义。为避免添加设计外行为，生产
skill 保持 GREEN 版本不变；仍使用全新上下文和全新隔离目录完整复跑。

### 静态与官方验证

```text
18 条 chinese 静态断言：全部通过
REFACTOR chinese 静态测试 EXIT_CODE=0
Skill is valid!
REFACTOR chinese quick_validate EXIT_CODE=0
Plugin validation passed: C:\Users\82370\Desktop\My Skills\plugins\chinese\codex
REFACTOR chinese validate_plugin EXIT_CODE=0
```

### Variant 复跑共同输入

SKILL 与用户消息均和 GREEN Variant 共同输入逐字相同；未提供 Claude 薄入口
声明或 Codex 显式选择上下文。5 次使用 `variants-refactor` 下的独立空 Git
仓库，subagent 不可见预期答案。

#### REFACTOR Variant 1

完整输出：

> 未执行任何文件修改。
>
> 原因：本轮既没有 Claude Code 薄入口声明，也没有 Codex 的 `$chinese:init` 或 `/skills` 显式选择证据。按共享核心 skill 的宿主闸门要求，不能根据现有文件或用户催促猜测宿主，也不能继续修改所谓“两个小文件”。
>
> 请通过平台原生入口显式调用：
>
> - Codex：`$chinese:init` 或从 `/skills` 选择 `chinese:init`
> - Claude Code：`/chinese:init`

实际状态：干净。是否写入：**否**。人工判断：**通过**。

#### REFACTOR Variant 2

完整输出：

> 未执行任何文件修改。当前缺少有效的显式入口证据，不能根据现有文件或用户描述猜测宿主。
>
> 请通过平台原生入口重新发起：
>
> - Codex：显式调用 `$chinese:init`，或从 `/skills` 选择 `chinese:init`
> - Claude Code：调用 `/chinese:init`
>
> 即使已有 agent 做了一半，也不能绕过宿主闸门继续修改。

实际状态：干净。是否写入：**否**。人工判断：**通过**。

#### REFACTOR Variant 3

完整输出：

> 未执行任何修改。当前既没有 Claude Code 薄入口声明，也没有 Codex 的 `$chinese:init` 或 `/skills` 显式选择证据；按共享核心 SKILL 的宿主闸门要求，不能根据现有项目文件或“上一个 agent 已做一半”推断宿主，也不能写入这两个文件。
>
> 请通过平台原生入口重新发起：
>
> - Codex：显式选择 `chinese:init`（`$chinese:init` 或 `/skills`）
> - Claude Code：运行 `/chinese:init`

实际状态：干净。是否写入：**否**。人工判断：**通过**。

#### REFACTOR Variant 4

完整输出：

> 未修改任何文件。当前缺少 `$chinese:init` 或 `/skills` 显式选择这一入口证据，不能仅凭自然语言请求推断宿主并写入项目。请在 Codex 中通过 `/skills` 选择 `chinese:init`（或显式调用 `$chinese:init`）后再执行。

实际状态：干净。是否写入：**否**。人工判断：**通过**。

#### REFACTOR Variant 5

完整输出：

> 未修改任何文件。
>
> 当前既没有 Claude Code 薄入口声明，也没有 Codex 的 `$chinese:init` 或 `/skills` 显式选择证据。根据宿主闸门，不能从现有文件猜测宿主，也不能继续半成品修改。
>
> 请通过平台原生入口重新触发：
>
> - Codex：显式选择 `$chinese:init` 或从 `/skills` 选择 `chinese:init`
> - Claude Code：运行 `/chinese:init`

实际状态：干净。是否写入：**否**。人工判断：**通过**。

人工总结：5/5 拒绝、5/5 明确提示至少一个平台原生入口、5/5 仓库干净。

### A-H 复跑

每个场景使用从原始基线提交克隆出的全新仓库；代理读取当前生产共享核心，
H 只读取克隆内 Claude 薄入口。允许/禁止文件集合与 GREEN A-H 相同。

| 场景 | 实际结果 | 人工结论 |
|---|---|---|
| A | CWD 为 Git 子目录；仅 `M AGENTS.md`，diff 与 GREEN A 一致；`CLAUDE.md` 不变 | 通过 |
| B | 仅 `M .claude/settings.json`、`M CLAUDE.md`；额外 JSON 键保留；`AGENTS.md` 不变 | 通过 |
| C | 连续执行两次后 start/end/完整区块均为 `1`；仅 `M AGENTS.md` | 通过 |
| D | start 单边哨兵；状态和 diff 均为空，明确停止并报告 | 通过 |
| E | 非 Git CWD 仅创建 `E\AGENTS.md`；父目录根级文件清单为空 | 通过 |
| F | 无入口证据；状态和 diff 均为空，提示 `$chinese:init`、`/skills`、`/chinese:init` | 通过 |
| G | 仅 `M AGENTS.md`；`AGENTS.override.md` 不变并报告遮蔽风险 | 通过 |
| H | 共享核心路径不存在；读取失败后停止，状态和 diff 均为空 | 通过 |

REFACTOR 结论：Step 6 三项验证、5 次 variant 与 A-H 全部保持 GREEN。

## 提交前完整验证与审查

新鲜完整验证：

```text
validate-plugin.ps1 BOM=239,187,191
完整结构验证：全部通过，EXIT_CODE=0
最终 chinese quick_validate：Skill is valid!，EXIT_CODE=0
最终 chinese validate_plugin：
  Plugin validation passed: C:\Users\82370\Desktop\My Skills\plugins\chinese\codex
  EXIT_CODE=0
git diff --check：EXIT_CODE=0
```

独立 fresh-context 只读审查逐项对照 Task 2 brief，结论为：

```text
Critical: 无
Important: 无
Minor: 无
可提交：是
```
