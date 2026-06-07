# My-Skills

hangwenlei 的个人 Claude Code 技能商店（marketplace）。

## chinese 插件

把当前项目一键切换到「中文输出模式」：让 Claude 始终用简体中文回复（覆盖过程说明、解释、commit 信息与交流），技术术语（API、token、commit 等）保持英文。

### 安装

```
/plugin marketplace add hangwenlei/My-Skills
/plugin install chinese@my-skills
```

### 使用

在任意项目目录运行：

```
/chinese:init
```

它会：
- 在 `.claude/settings.json` 写入 `"language": "chinese"`（保留其它已有配置）；
- 在项目根 `CLAUDE.md` 写入「中文输出规范」（用标记包裹，重复运行不会重复堆叠）。

### 更新

```
/plugin marketplace update my-skills
```

### 说明

命令带 `chinese:` 前缀是 Claude Code 插件机制决定的（插件命令强制带命名空间），无法去掉。
