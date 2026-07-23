---
name: init
description: Use when 用户在 Codex 中显式调用 $chinese:init，或从 /skills 选择 chinese:init。
---

# 初始化项目中文模式

## 调用与宿主闸门

只接受以下两种入口证据：

- Claude Code：带 `disable-model-invocation: true` 的 `/chinese:init`
  薄入口已读取本文件并明确声明宿主为 Claude Code。
- Codex：本文件由 `allow_implicit_invocation: false` 的 `$chinese:init`
  或 `/skills` 显式选择直接加载。

若两种证据都不存在，停止并提示使用平台原生入口，禁止写项目文件。
不能根据项目中的 `CLAUDE.md` 或 `AGENTS.md` 猜宿主，禁止同时修改两套
平台文件。

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

先精确统计开始和结束哨兵并检查位置。只有在开始哨兵和结束哨兵各恰好
出现一次，且开始哨兵位于结束哨兵之前时，才替换完整区块。两者都未出现时
在文件末尾追加。其它情况，包括单边、重复或逆序哨兵，均停止修改该文件并
报告，不猜测边界。

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
