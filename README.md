# My-Skills

hangwenlei 的个人技能市场（marketplace），同时面向 Claude Code 与 Codex 发布。两套平台入口共用同一个 Git 仓库：
https://github.com/hangwenlei/My-Skills 。

## Claude Code

> ⚠️ `/plugin` 命令**只在 Claude Code CLI（终端版）里可用**。桌面/GUI 客户端通常没有这个命令，请在终端安装。

安装：

```text
/plugin marketplace add hangwenlei/My-Skills
/plugin install chinese@my-skills
/plugin install sync@my-skills
```

调用：`/chinese:init`、`/sync:docs`

更新：

```text
claude plugin marketplace update my-skills
claude plugin update chinese@my-skills
claude plugin update sync@my-skills
```

只刷新商店清单不会升级已安装插件；需要继续运行对应的 `claude plugin update`。更新后，在 Claude Code 里运行 `/reload-plugins` 或重启客户端。

**GUI 客户端也能用**：Claude Code CLI 与 GUI 客户端共用同一个 `~/.claude/` 目录，插件信息写在 `~/.claude/plugins/` 注册表里。用 CLI 安装后，重启 GUI 客户端即可加载插件。

## Codex

安装：

```text
codex plugin marketplace add hangwenlei/My-Skills
codex plugin add chinese@my-skills
codex plugin add sync@my-skills
```

调用：`$chinese:init`、`$sync:docs`，或 `/skills`

更新：

```text
codex plugin marketplace upgrade my-skills
codex plugin add chinese@my-skills
codex plugin add sync@my-skills
```

升级后需新开 Codex 任务，已打开的任务不会自动加载新版本。

Codex 不支持第三方同名 slash alias，因此不要把 Claude 的 `/chinese:init`、`/sync:docs` 当作 Codex 调用方式。Codex 中请使用 `$chinese:init`、`$sync:docs`，或从 `/skills` 选择。

## chinese 插件

把当前项目一键切换到“中文输出模式”：让宿主始终用简体中文回复，包括过程说明、解释、Git 提交信息与交流；API、token、commit 等技术术语保持英文。

运行对应平台的调用命令后：

- Claude Code：在 `.claude/settings.json` 写入 `"language": "chinese"`（保留其它已有配置），并在项目根 `CLAUDE.md` 写入带哨兵的中文输出规范；
- Codex：只维护项目根 `AGENTS.md` 中带哨兵的中文输出规范，不修改 `.claude/settings.json` 或 `CLAUDE.md`；
- 重复运行会更新既有哨兵区块，不会重复堆叠。

## sync 插件

开发到一半想停下来时，运行对应平台的调用命令：它会把当前开发现场固化进 `HANDOFF.md`，供后续新任务续接；同时先列出建议更新的文档清单，经你确认后再刷新 README、设计文档等。

它会：

- 快照式重写项目根 `HANDOFF.md`，涵盖概览、已完成、进行中、下一步、关键决策、重要文件、风险和常用命令；
- Claude Code：幂等地在 `CLAUDE.md` 加入裸 `@HANDOFF.md`，让新 session 自动加载；
- Codex：维护 `AGENTS.md` 中的续接哨兵区块，要求新任务显式读取 `HANDOFF.md`，而不是使用裸 `@HANDOFF.md`；
- 列出建议更新或收敛的其它文档，包含跨文档去重；日志型或时间线型内容自动跳过；
- 只在你确认后修改建议项，并遵守不丢信息、受众边界与权威出处等护栏；
- 不自动 commit，改完后请用 `git diff` 复核并自行提交。

## 常见问题

- **Claude 命令为什么带 `chinese:` 或 `sync:` 前缀？** 这是 Claude Code 插件机制决定的：第三方插件命令带命名空间（`/<插件名>:<skill名>`）。
- **为什么 Codex 不使用相同的 slash 命令？** Codex 不支持第三方同名 slash alias；请使用 `$chinese:init`、`$sync:docs` 或 `/skills`。
- **GUI 客户端的 `Directory` 搜不到本插件？** 属正常。该目录只展示官方精选（Anthropic & Partners）内容，不索引个人 GitHub 仓库。请用 Claude Code CLI 安装；安装后重启 GUI 客户端即可使用。
