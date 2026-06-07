# 设计文档：`chinese` 插件（命令 `/chinese:init`）

- 日期：2026-06-07
- 状态：已确认，待制定实现计划
- 仓库：https://github.com/hangwenlei/My-Skills.git

## 1. 背景与目标

希望在 Claude Code 中用一个命令，把**当前打开的项目**一键切换到「中文输出模式」：让 AI 始终用简体中文回复，覆盖所有过程说明、解释、commit 信息、与用户的交流；技术术语（API、token、commit 等）保持英文。

目标命令：在任意项目目录运行该命令即可完成初始化，并且这个能力要**能发布给其他人安装使用**。

### 调研结论（决定方案的关键事实）

1. `.claude/settings.json` 支持官方的 `language` 字段（如 `{"language": "chinese"}`），可让 Claude 用指定自然语言回复。
2. 让某个项目「始终用中文」的可靠机制是 **settings.json 的 `language` 字段（强制）+ CLAUDE.md 项目指令（写明规范）** 双管齐下。CLAUDE.md 查找位置包括项目根 `./CLAUDE.md` 与 `.claude/CLAUDE.md`，本方案统一写项目根 `CLAUDE.md`（最常见、最可见）。
3. 要在「任意目录」都能用某个斜杠命令，需做成用户级 skill 或通过 plugin 分发。旧版 `commands/` 已并入 skill。
4. **plugin 里的命令强制带命名空间**，格式恒为 `/<plugin名>:<skill名>`，无法去掉前缀。裸命令 `/init-chinese` 只有 standalone skill（不可发布）才能实现。

## 2. 关键决策

| 决策点 | 结论 | 理由 / 被否方案 |
|--------|------|----------------|
| 写入范围 | **同时写** `settings.json` 的 `language` 与 `CLAUDE.md` 的中文规范 | 双保险：language 字段强制语言；CLAUDE.md 写明「术语保持英文、commit 用中文」等细化规范。否决「只写其一」。 |
| 分发路线 | **只做可发布的应用商店**（marketplace + plugin） | 用户要发布给别人用。自己换机也走同一套，单一维护点。否决「只做用户级 skill」「附本地 install 脚本」。 |
| 命令形式 | **`/chinese:init`**（plugin 名 `chinese`、skill 名 `init`） | plugin 命令强制带命名空间，做不出裸 `/init-chinese`；`/chinese:init` 念起来最简洁，且 `chinese` 风格便于以后扩展其它语言/功能。否决 `/init:chinese`（`init` 名太通用）、`/init-chinese:init-chinese`（冗余难看）。 |
| 命令参数 | **零参数**（仅 `/chinese:init`） | YAGNI。否决 `/chinese:init <额外说明>` 形式，保持最简。 |
| 模型自动触发 | **关闭**（`disable-model-invocation: true`） | 这是显式初始化动作，只应在用户手动输入命令时运行，避免模型自作主张。 |

## 3. 架构与目录结构

`My-Skills` 仓库本身作为 marketplace，内含一个 plugin `chinese`，plugin 内含一个 skill `init`。

```
My-Skills/
├── .claude-plugin/
│   └── marketplace.json          # 商店清单：name=my-skills，登记 chinese 插件
├── plugins/
│   └── chinese/                  # plugin
│       ├── .claude-plugin/
│       │   └── plugin.json        # 插件说明书
│       └── skills/
│           └── init/
│               └── SKILL.md       # skill 本体（核心逻辑）
├── README.md                     # 安装 + 使用说明（面向使用者）
├── CLAUDE.md                     # （已存在）本仓库开发指引
└── docs/superpowers/specs/       # 设计文档（本文件所在）
```

> 用户最初设想的「Init Chinese Language 目录」在标准可发布结构里落地为 `plugins/chinese/`（目录名避免空格，对工具友好）。

## 4. 运行时行为（`/chinese:init` 核心逻辑）

skill 被触发后，对**当前工作目录所在项目**依次执行，全程用简体中文向用户汇报：

### 步骤 1：更新 `.claude/settings.json`
- 若 `.claude/settings.json` 存在：读取并解析 JSON，合并/设置 `"language": "chinese"`，**保留其余所有已有配置**，写回。
- 若不存在：创建 `.claude/settings.json`，写入 `{ "language": "chinese" }`（Write 会自动创建 `.claude/` 目录）。

### 步骤 2：更新项目根 `CLAUDE.md`
用一对哨兵标记包裹中文规范块，保证幂等：
```
<!-- chinese:init start -->
...中文输出规范...
<!-- chinese:init end -->
```
- `CLAUDE.md` 不存在 → 新建文件并写入规范块（带标题）。
- 存在但无标记块 → 在文件**末尾追加**规范块，不改动用户原有内容。
- 存在且已有标记块 → **仅替换两标记之间的内容**，不重复堆叠（支持重复运行）。

### 步骤 3：汇报
用简体中文总结：改动了哪些文件、各自做了什么、以及「中文模式已开启，新会话即生效」之类的提示。

## 5. 写入的「中文输出规范」内容模板

```markdown
## 语言与输出规范

- **始终使用简体中文回复**，包括任务过程中的所有输出：进度说明、计划与思路、
  工具调用前后的简短说明、错误分析、代码审查意见、最终总结。
- 代码、命令、文件路径、API 名称等技术标识保持英文原样（如 API、token、commit）；
  代码注释使用中文。
- Git 提交信息使用中文。
```

## 6. 三个配置文件的内容

### 6.1 `.claude-plugin/marketplace.json`
```json
{
  "name": "my-skills",
  "owner": { "name": "hangwenlei" },
  "description": "hangwenlei 的个人 Claude Code 技能商店",
  "plugins": [
    {
      "name": "chinese",
      "source": "./plugins/chinese",
      "description": "把当前项目切换到中文输出模式"
    }
  ]
}
```

### 6.2 `plugins/chinese/.claude-plugin/plugin.json`
```json
{
  "name": "chinese",
  "version": "1.0.0",
  "description": "把当前项目切换到中文输出模式：写入 settings.json 的 language 配置并在 CLAUDE.md 写明中文输出规范",
  "author": { "name": "hangwenlei" }
}
```

### 6.3 `plugins/chinese/skills/init/SKILL.md`（frontmatter 要点）
```yaml
---
name: init
description: 把当前项目切换到中文输出模式——写入 settings.json 的 language 配置并在 CLAUDE.md 追加中文输出规范。仅在用户手动运行 /chinese:init 时执行。
disable-model-invocation: true
allowed-tools: Read, Write, Edit
---
```
正文：用中文写明第 4 节的三步逻辑 + 第 5 节的规范模板，指示模型在运行时按步骤操作并用中文汇报。

## 7. README 要点（面向使用者）
- 插件简介与效果说明
- 安装：
  ```
  /plugin marketplace add hangwenlei/My-Skills
  /plugin install chinese@my-skills
  ```
- 使用：`/chinese:init`
- 更新：`/plugin marketplace update my-skills`
- 说明：命令带命名空间前缀（`chinese:`）是 Claude Code 插件机制决定的，无法去掉。

## 8. 测试与验证
实现后在一个**临时空目录**中实测（不污染真实项目）：
1. 空目录运行 → 正确创建 `.claude/settings.json`（含 `language: chinese`）与 `CLAUDE.md`（含带标记的规范块）。
2. 在已有 `settings.json`（含其它键）的目录运行 → 其它键保留，新增 `language`。
3. 在已有内容的 `CLAUDE.md` 目录运行 → 原内容保留，规范块追加在末尾。
4. **重复运行**两次 → settings.json 不出现重复键、CLAUDE.md 规范块不重复堆叠（验证幂等）。

## 9. 发布与更新流程
- 提交所有文件到本仓库。
- `git push` 到 `origin`（**等用户确认后再执行 push**）。
- 用户/他人通过 `/plugin marketplace add hangwenlei/My-Skills` + `/plugin install chinese@my-skills` 安装。
- 仓库需为公开仓库，他人才能一键添加。

## 10. 非目标（YAGNI）
- 不做命令参数（零参数）。
- 不做 standalone 用户级 skill / install.ps1（不追求裸 `/init-chinese`）。
- 不做多语言通用化（当前只做简体中文；未来可在 `chinese` 商店里另加插件扩展）。

## 11. 兼容性说明
即便某些 Claude Code 版本未实现 `settings.json` 的 `language` 字段，`CLAUDE.md` 中的规范仍能约束输出语言，二者构成双保险。

## 12. 安装与环境说明（实现后补充）

- **`/plugin` 命令仅在 Claude Code CLI（终端版）可用**；桌面/GUI 客户端通常没有该命令，其「Directory」只展示官方精选内容、不索引个人 GitHub 仓库。因此本插件的安装统一在 **CLI 终端**完成：`/plugin marketplace add hangwenlei/My-Skills` + `/plugin install chinese@my-skills`。
- **CLI 与 GUI 客户端共用同一个 `~/.claude/` 目录**：插件注册信息写在 `~/.claude/plugins/`（`known_marketplaces.json`、`installed_plugins.json`、`marketplaces/`、`cache/`）。所以在 CLI 装好后，**重启 GUI 客户端即可加载**，`/chinese:init` 两端通用。
- **不要让 agent 直接写 `~/.claude/`**：往 `~/.claude/skills/` 写 SKILL.md 会触发「自我修改」权限护栏被拒；改 `~/.claude/plugins/` 注册表会被沙箱保护拦截。安装应由用户在自己的 CLI 中以正常用户操作完成，而非由 agent 代写配置目录。
- **发布即推送**：仓库设为 public 后，已验证可匿名访问与匿名克隆（即 `/plugin marketplace add` 所做的动作），结构校验全通过。
