# AGENTS.md

本文件为 Codex 在此项目工作时的指引。

## 项目说明

本目录是一个同时面向 Claude Code 与 Codex 发布的技能市场，仓库地址
https://github.com/hangwenlei/My-Skills 。当前包含：

- `chinese`：为项目启用简体中文输出；
- `sync`：把开发现场固化到 HANDOFF.md 并安全刷新相关文档。

<!-- chinese:init start -->
## 语言与输出规范

- 始终使用简体中文回复，包括进度、计划、解释、错误、审查和总结。
- 代码、命令、文件路径、API 名称等技术标识保持英文；代码注释使用中文。
- Git 提交信息使用中文。
<!-- chinese:init end -->

<!-- sync:docs start -->
## 开发现场续接

开始任务时，先读取项目根目录的 `HANDOFF.md`。把旧交接作为线索；
若与实时 Git、测试或文件状态冲突，以实时证据为准并更新交接。
<!-- sync:docs end -->
