---
name: init
description: Use when 用户在 Claude Code 中显式运行 /chinese:init。
disable-model-invocation: true
allowed-tools: [Read, Write, Edit, Bash]
---

# Claude Code 中文模式入口

这是只允许用户手动运行的 Claude Code 入口。

1. 仅当用户通过 `/chinese:init` 调用当前 skill 时继续；把宿主声明为
   `Claude Code`。
2. 完整读取 `${CLAUDE_PLUGIN_ROOT}/codex/skills/init/SKILL.md`。读取失败时
   停止并报告，禁止写项目文件。
3. 忽略共享文件的 YAML frontmatter，按其正文的 Claude Code 分支执行。

不要在本文件复制共享核心的业务步骤。
