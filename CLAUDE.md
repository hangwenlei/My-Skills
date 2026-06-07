# CLAUDE.md

本文件为 Claude Code 在此项目工作时的指引。

## 项目说明

本目录是一个已发布的 Claude Code 应用商店（marketplace），仓库地址 https://github.com/hangwenlei/My-Skills ，用来存放并对外发布所开发的 skills。当前含两个插件：

- `chinese`（命令 `/chinese:init`）：把当前项目切换到中文输出模式。
- `sync`（命令 `/sync:docs`）：固化开发现场到 HANDOFF.md 并在 CLAUDE.md 挂自动加载，支持新 session 无缝续接。

## 语言与输出规范

- **始终使用简体中文回复**，包括任务过程中的所有输出：进度说明、计划与思路、工具调用前后的简短说明、错误分析、代码审查意见、最终总结。
- 代码、命令、文件路径、API 名称等技术标识保持英文原样；代码注释使用中文。
- Git 提交信息使用中文。

@HANDOFF.md
