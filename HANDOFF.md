# 开发现场交接（HANDOFF）

> 更新时间：2026-07-24

## 概览

`My-Skills` 是同时面向 Claude Code 与 Codex 发布的个人技能市场，仓库地址为
`https://github.com/hangwenlei/My-Skills`。双平台入口、共享 skill 核心、
静态验证、远端发布、本机 Codex 升级及新进程运行时 smoke 均已完成。

已发布并在本机验证的版本：

- `chinese`：`1.1.0`
- `sync`：`1.2.0`

本轮功能发布提交为
`68c6d0e23ef7aad2f32710133a2af2a284e07ce5`。

## 已完成

- 同一 Git 仓库已同时发布 Claude 与 Codex marketplace，功能提交已
  fast-forward 推送到 `origin/main`，未使用 force push。
- 本机 `my-skills` Codex marketplace 已刷新到已发布 revision。
- 本机 `chinese@my-skills` `1.1.0` 与 `sync@my-skills` `1.2.0` 均为
  installed、enabled，source 分别指向各自的 `plugins\chinese\codex` 与
  `plugins\sync\codex`。
- native marketplace catalog、安装 receipt、插件 cache manifest 与共享
  skill 内容均已做程序化断言。
- 在两个互相隔离的临时 Git 仓库中，分别连续两次运行新的
  `codex exec --ephemeral --sandbox workspace-write` 进程：
  - `$chinese:init` 两次均 exit `0`；只生成 Codex 侧 `AGENTS.md`，中文哨兵
    唯一，重复调用未产生重复区块，也未生成 `.claude` 或 `CLAUDE.md`。
  - `$sync:docs` 两次均 exit `0`；生成 `HANDOFF.md` 与只含唯一续接哨兵的
    `AGENTS.md`，重复调用保持续接区块幂等，也未生成 `CLAUDE.md`。
- smoke 产物通过严格 UTF-8、文件集合、哨兵顺序和宿主隔离断言后，临时目录
  已在系统 Temp 路径及全树无 reparse point 校验后清理。

## 进行中

- 无 Codex 发布或运行时验证事项。
- 本机未安装 Claude CLI，因此 Claude runtime smoke 未执行；Claude 兼容性
  目前只有仓库静态校验和发布包结构证据，不能表述为本机实测通过。

## 下一步

1. 日常使用时新开 Codex 任务，再调用 `$chinese:init` 或 `$sync:docs`；
   已打开的旧任务不会热加载刚升级的 skill。
2. 若需要完成 Claude 实机验证，先安装 Claude CLI，再升级 marketplace 与插件，
   分别用 `/chinese:init`、`/sync:docs` 在隔离测试项目中执行 runtime smoke。

## 当前验证

发布前静态验证：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\validate-plugin.ps1 -Section docs
powershell -NoProfile -ExecutionPolicy Bypass -File tests\validate-plugin.ps1 -Section all
git diff --check
```

三项均 exit `0`；两组插件校验均输出“全部通过”。

本机 Codex 安装与运行时验证：

```powershell
codex plugin marketplace upgrade my-skills --json
codex plugin add chinese@my-skills --json
codex plugin add sync@my-skills --json
codex plugin list --json
codex exec --ephemeral --sandbox workspace-write --cd <isolated-repo> '$chinese:init'
codex exec --ephemeral --sandbox workspace-write --cd <isolated-repo> '$sync:docs'
```

marketplace upgrade 无错误，两个插件版本、启用状态、native source、receipt 与
cache 内容断言均通过；两个 skill 各使用全新进程连续运行两次，四次均 exit `0`。

## 风险与注意事项

- 当前已打开的 Codex 任务不会热加载新版插件；必须新开任务使用已升级版本。
- Claude CLI 未安装且 Claude runtime smoke 未执行，不得把静态双平台兼容描述
  为 Claude 本机运行时验证通过。
- `tests/validate-plugin.ps1` 必须保持 UTF-8 with BOM，以兼容 Windows
  PowerShell 5.1 的中文解析。
- `sync` 的跨文档更新仍是 propose-confirm，不自动提交，也不应改写日志型或
  时间线型文档。

## 重要文件

- `.claude-plugin/marketplace.json`：Claude marketplace。
- `.agents/plugins/marketplace.json`：Codex native marketplace。
- `plugins/chinese/`：chinese 的 Claude 薄入口、Codex manifest 与共享核心。
- `plugins/sync/`：sync 的 Claude 薄入口、Codex manifest 与共享核心。
- `.claude/settings.json`、`CLAUDE.md`、`AGENTS.md`：本仓库双宿主指令。
- `tests/validate-plugin.ps1`：全量静态验证脚本。

## 常用命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\validate-plugin.ps1 -Section docs
powershell -NoProfile -ExecutionPolicy Bypass -File tests\validate-plugin.ps1 -Section all
codex plugin marketplace upgrade my-skills --json
codex plugin list --json
git status --short
git diff --check
```
