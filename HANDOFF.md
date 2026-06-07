# 开发现场交接（HANDOFF）

> 更新时间：2026-06-07

## 概览
`My-Skills` 是 hangwenlei 的个人 Claude Code 技能商店（marketplace），已发布到公开仓库 `https://github.com/hangwenlei/My-Skills`。当前含两个插件：`chinese`（`/chinese:init`）与 `sync`（`/sync:docs`），均已实现、验证、发布并通过 CLI 安装启用。工作树干净、与 `origin/main` 同步。

## ✅ 已完成
- `chinese` 插件：`/chinese:init` 把项目切中文模式（写 `.claude/settings.json` 的 `language` + `CLAUDE.md` 哨兵区块）。文件：`plugins/chinese/skills/init/SKILL.md`。
- `sync` 插件：`/sync:docs` 生成 `HANDOFF.md` + 在 `CLAUDE.md` 挂 `@HANDOFF.md` + propose-confirm 刷新其它文档。文件：`plugins/sync/skills/docs/SKILL.md`。
- marketplace 清单登记两插件：`.claude-plugin/marketplace.json`。
- 结构校验脚本（22 项全过）：`tests/validate-plugin.ps1`。
- 设计与实现文档：`docs/superpowers/specs/` 与 `docs/superpowers/plans/`（各两套）。
- 已 `git push` 到 `origin/main`；两插件已用 `claude plugin install ...@my-skills` 安装、状态 enabled。

## 🔄 进行中
- 无未提交改动（本次 `/sync:docs` 生成的 `HANDOFF.md` 与 `CLAUDE.md` 改动待复核提交）。

## ⏭️ 下一步
- 重启客户端后实测 `/chinese:init` 与 `/sync:docs` 的真实效果。
- 如需扩展：按相同结构在 `plugins/<新名>/` 添加新插件，并在 `marketplace.json` 登记、扩展校验脚本。

## 🧠 关键决策与理由
- 仓库本身即 marketplace；每个 skill 打包成独立 plugin 放 `plugins/<名>/`。
- 插件命令强制带命名空间，故为 `/chinese:init`、`/sync:docs`（无法做裸命令）。
- 安装走 Claude Code CLI（`claude plugin ...`）；GUI 客户端无 `/plugin`，但与 CLI 共用 `~/.claude/`，CLI 装好后重启客户端即生效。
- `sync` 续接靠 `HANDOFF.md` + `CLAUDE.md` 的 `@HANDOFF.md` 自动加载；刷新其它文档走 propose-confirm；不自动 commit。

## 📁 重要文件
- `.claude-plugin/marketplace.json`：商店清单（登记 chinese、sync）。
- `plugins/chinese/skills/init/SKILL.md`：chinese 逻辑。
- `plugins/sync/skills/docs/SKILL.md`：sync 逻辑。
- `tests/validate-plugin.ps1`：结构校验脚本。
- `docs/superpowers/specs/`、`docs/superpowers/plans/`：设计与实现计划。

## ⚠️ 注意事项 / 坑
- `.ps1` 必须存为 **UTF-8 with BOM**，否则 PS 5.1 按 GBK 读取中文乱码报错；读取含中文的 JSON/MD 必须带 `-Encoding UTF8`。
- 不要让 agent 直接写 `~/.claude/`（沙箱保护 + 自我修改护栏）；插件安装由用户/CLI 完成。
- 嵌套 `powershell -Command "..."` 会让外层先展开 `$` 变量——在 PowerShell 里直接跑命令即可。

## ▶️ 常用命令
- `powershell -ExecutionPolicy Bypass -File tests\validate-plugin.ps1`：跑结构校验。
- `claude plugin marketplace update my-skills`：拉取商店最新。
- `claude plugin install <plugin>@my-skills`：安装插件。
- `git push origin main`：发布。
