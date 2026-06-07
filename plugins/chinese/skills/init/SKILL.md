---
name: init
description: 把当前项目切换到中文输出模式——写入 settings.json 的 language 配置并在 CLAUDE.md 追加中文输出规范。仅在用户手动运行 /chinese:init 时执行。
disable-model-invocation: true
allowed-tools: Read, Write, Edit
---

# 初始化项目中文模式

当用户运行 `/chinese:init` 时，把**当前工作目录所在的项目**切换到「中文输出模式」。严格按下面三步执行，全程用简体中文向用户汇报你做了什么。

## 步骤 1：写入 `.claude/settings.json`

目标：让该文件包含 `"language": "chinese"`，同时不破坏任何已有配置。

1. 尝试读取当前工作目录下的 `.claude/settings.json`。
2. 如果文件存在：解析其中的 JSON，把键 `language` 设为 `"chinese"`（已存在则覆盖该键），**保留其余所有键不变**，然后写回，保持 2 空格缩进。
3. 如果文件不存在：创建 `.claude/settings.json`，写入：

   ```json
   {
     "language": "chinese"
   }
   ```

   （用 Write 工具写文件会自动创建 `.claude/` 目录。）

## 步骤 2：写入项目根目录的 `CLAUDE.md`

目标：在 `CLAUDE.md` 中写入「中文输出规范」，用哨兵标记包裹以支持重复运行不重复堆叠。

规范块的固定内容（含首尾标记）如下，称为 **BLOCK**：

```
<!-- chinese:init start -->
## 语言与输出规范

- **始终使用简体中文回复**，包括任务过程中的所有输出：进度说明、计划与思路、工具调用前后的简短说明、错误分析、代码审查意见、最终总结。
- 代码、命令、文件路径、API 名称等技术标识保持英文原样（如 API、token、commit）；代码注释使用中文。
- Git 提交信息使用中文。
<!-- chinese:init end -->
```

操作：
1. 尝试读取当前工作目录下的 `CLAUDE.md`。
2. 如果文件不存在：创建 `CLAUDE.md`，内容为 `# CLAUDE.md` + 一个空行 + BLOCK。
3. 如果文件存在且同时包含 `<!-- chinese:init start -->` 与 `<!-- chinese:init end -->`：用 BLOCK **替换**这两个标记（含标记本身）之间的全部内容，其余内容一字不改。
4. 如果文件存在但不包含上述标记：在文件**末尾**追加一个空行 + BLOCK，原有内容一字不改。

## 步骤 3：向用户汇报

用简体中文简要说明：
- 创建/更新了 `.claude/settings.json`（已设置 `language: chinese`）；
- 创建/更新了 `CLAUDE.md`（已写入中文输出规范）；
- 提示：中文模式已开启，建议在新会话中生效；技术术语（API、token、commit 等）仍保持英文。

不要执行任何与上述无关的操作。
