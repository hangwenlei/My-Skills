# 开发现场交接（HANDOFF）

> 更新时间：2026-07-23

## 概览

`My-Skills` 是同时面向 Claude Code 与 Codex 发布的个人技能市场，仓库地址为
`https://github.com/hangwenlei/My-Skills`。双平台入口、共享 skill 核心和仓库级双宿主指令均已实现，静态验证已完成；当前仍处于发布前状态。

目标版本：

- `chinese`：`1.1.0`
- `sync`：`1.2.0`

## 已完成

- 建立 Claude 与 Codex 两套 marketplace 入口，两个平台共用同一个 Git 仓库。
- 为 `chinese` 和 `sync` 建立双平台 manifest 与共享 skill 核心，并保持 Claude 薄入口。
- `chinese` 已区分宿主行为：Claude 维护 `.claude/settings.json` 与 `CLAUDE.md`，Codex 只维护 `AGENTS.md`。
- `sync` 已区分宿主行为：Claude 在 `CLAUDE.md` 挂载 `@HANDOFF.md`，Codex 在 `AGENTS.md` 维护显式续接区块。
- 仓库根的 `.claude/settings.json`、`CLAUDE.md` 与 `AGENTS.md` 已恢复或收敛为双宿主指令。
- README 已覆盖 Claude Code 与 Codex 的安装、调用、升级、宿主差异和常见问题。
- 静态校验覆盖 distribution、chinese、sync 与 docs，各入口、版本、关键行为与用户文档均有断言。

## 进行中

- 等待将当前提交 push 到远端。
- 等待在本机 Codex 中升级 marketplace 与两个插件，然后新开任务验证加载。

## 下一步

1. 复核提交内容并执行 `git push`。
2. 在本机执行：

   ```text
   codex plugin marketplace upgrade my-skills
   codex plugin add chinese@my-skills
   codex plugin add sync@my-skills
   ```

3. 新开 Codex 任务，分别调用 `$chinese:init` 与 `$sync:docs` 做 runtime smoke。
4. 如需验证 Claude Code 发布包，更新 marketplace 与插件后运行 `/reload-plugins` 或重启客户端。

## 当前验证

已完成的静态验证命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\validate-plugin.ps1 -Section docs
powershell -NoProfile -ExecutionPolicy Bypass -File tests\validate-plugin.ps1 -Section all
```

预期均为 exit `0` 并输出“全部通过”。

## 风险与注意事项

- 当前验证以静态结构和关键文本断言为主；本机 Codex 升级与 runtime smoke 尚未执行，不能据此断言实际安装链路已经通过。
- 当前提交尚未 push，远端用户仍无法获得本轮双平台更新。
- `tests/validate-plugin.ps1` 必须保持 UTF-8 with BOM，以兼容 Windows PowerShell 5.1 的中文解析。
- Codex 升级后必须新开任务；现有任务不会自动加载新插件版本。
- `sync` 的跨文档更新仍是 propose-confirm，不自动提交，也不应改写日志型或时间线型文档。

## 重要文件

- `.claude-plugin/marketplace.json`：Claude marketplace。
- `.agents/plugins/marketplace.json`：Codex marketplace。
- `plugins/chinese/`：chinese 的 Claude 薄入口、Codex manifest 与共享核心。
- `plugins/sync/`：sync 的 Claude 薄入口、Codex manifest 与共享核心。
- `.claude/settings.json`、`CLAUDE.md`、`AGENTS.md`：本仓库双宿主指令。
- `tests/validate-plugin.ps1`：全量静态验证脚本。

## 常用命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\validate-plugin.ps1 -Section docs
powershell -NoProfile -ExecutionPolicy Bypass -File tests\validate-plugin.ps1 -Section all
git status --short
git diff --check
```
