---
name: docs
description: Use when 用户在 Claude Code 中显式运行 /sync:docs。
disable-model-invocation: true
allowed-tools: [Read, Write, Edit, Bash]
---

# Claude Code 同步文档入口

这是只允许用户手动运行的 Claude Code 入口。

1. 仅当用户通过 `/sync:docs`（可带 `应用 1,3` 参数）调用当前 skill 时继续；
   把宿主声明为 `Claude Code` 并保留全部参数。
2. 完整读取 `${CLAUDE_PLUGIN_ROOT}/codex/skills/docs/SKILL.md`。读取失败时
   停止并报告，禁止写项目文件。
3. 忽略共享文件的 YAML frontmatter，按其正文的 Claude Code 分支执行，
   并把原参数用于确认项处理。

不要在本文件复制共享核心的业务步骤。
