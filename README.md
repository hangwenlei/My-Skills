# My-Skills

hangwenlei 的个人 Claude Code 技能商店（marketplace）。

## chinese 插件

把当前项目一键切换到「中文输出模式」：让 Claude 始终用简体中文回复（覆盖过程说明、解释、commit 信息与交流），技术术语（API、token、commit 等）保持英文。

### 安装

> ⚠️ `/plugin` 命令**只在 Claude Code CLI（终端版）里可用**。桌面/GUI 客户端通常没有这个命令——请在**终端**里安装。

在 Claude Code CLI 终端运行：

```
/plugin marketplace add hangwenlei/My-Skills
/plugin install chinese@my-skills
```

**GUI 客户端也能用**：CLI 与 GUI 客户端共用同一个 `~/.claude/` 目录，插件信息写在 `~/.claude/plugins/` 注册表里。所以在 CLI 装好后，**重启一下 GUI 客户端**，它就会加载这个插件，`/chinese:init` 在两边都能用。

### 使用

在任意项目目录运行：

```
/chinese:init
```

它会：
- 在 `.claude/settings.json` 写入 `"language": "chinese"`（保留其它已有配置）；
- 在项目根 `CLAUDE.md` 写入「中文输出规范」（用标记包裹，重复运行不会重复堆叠）。

### 更新

在 Claude Code CLI 终端运行：

```
/plugin marketplace update my-skills
```

### 常见问题

- **命令为什么带 `chinese:` 前缀？** 这是 Claude Code 插件机制决定的——插件命令强制带命名空间（`/<插件名>:<skill名>`），无法去掉。
- **GUI 客户端的「Directory」搜索框搜不到本插件？** 属正常。那个目录只展示官方精选（Anthropic & Partners）内容，不索引个人 GitHub 仓库。安装请走上面的 CLI 方式；装好后 `/chinese:init` 命令照常生效，不依赖该目录。

## sync 插件

开发到一半想停下来时，运行 `/sync:docs`：把当前开发现场固化进 `HANDOFF.md`，并在 `CLAUDE.md` 挂一行 `@HANDOFF.md` 自动加载；之后新开 session、导入本项目文件夹即可无缝续接。同时它会先列出「建议更新的文档清单」，经你确认后再刷新 README、设计文档等。

### 安装

在 Claude Code CLI 终端运行：

```
/plugin marketplace add hangwenlei/My-Skills
/plugin install sync@my-skills
```

（与 chinese 插件相同：`/plugin` 仅 CLI 可用；CLI 与 GUI 客户端共用 `~/.claude/`，CLI 装好后重启 GUI 客户端即生效。）

### 使用

在项目目录运行：

```
/sync:docs
```

它会：
- 快照式重写项目根 `HANDOFF.md`（概览/已完成/进行中/下一步/关键决策/重要文件/坑/常用命令）；
- 幂等地在 `CLAUDE.md` 加 `@HANDOFF.md`，让新 session 自动加载；
- 列出建议更新的其它文档，经你确认后再改；
- 不自动 commit——改完用 `git diff` 复核后自行提交。
