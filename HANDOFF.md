# 开发现场交接（HANDOFF）

> 更新时间：2026-06-10

## 概览
`My-Skills` 是 hangwenlei 的个人 Claude Code 技能商店（marketplace），已发布到 `https://github.com/hangwenlei/My-Skills`。含两个插件：`chinese`（`/chinese:init`）与 `sync`（`/sync:docs`），均已发布启用。本轮给 `sync` 增强了**跨文档去重**能力并发布到 **1.1.0**。工作树干净、与 `origin/main` 同步。

## ✅ 已完成
- `chinese` 插件：`/chinese:init` 把项目切中文模式（写 `.claude/settings.json` 的 `language` + `CLAUDE.md` 哨兵区块）。
- `sync` 插件基础能力：`/sync:docs` 生成 `HANDOFF.md` + 在 `CLAUDE.md` 挂 `@HANDOFF.md` 自动加载 + propose-confirm 刷新其它文档。
- **本轮 sync 去重增强（已发布 1.1.0）**：
  - 步骤 4 跨文档去重——4.0 日志/时间线型一律跳过；4.1 只比对本次改动牵连的文档（不全项目扫描）；4.2 标 `过时`/`可收敛`/`可合并`；4.4 三护栏（不丢信息 / 受众边界 / 权威出处）；仍 propose-confirm。
  - 步骤 2 HANDOFF 自身「同一事实只写一条」。
  - `tests/validate-plugin.ps1` 加 4 条防回退断言（共 26 项全过）；`README.md` 同步描述；`plugin.json` bump 1.0.0→1.1.0。
- 设计与计划：`docs/superpowers/specs/2026-06-10-sync-dedup-design.md`、`docs/superpowers/plans/2026-06-10-sync-dedup.md`。
- 已 `git push` 到 `origin/main`；客户端已 `claude plugin update sync@my-skills` 升级到 1.1.0 生效。

## 🔄 进行中
- 无未提交开发；本次 `/sync:docs` 生成的 `HANDOFF.md` 改动待复核提交。

## ⏭️ 下一步
- 去重功能手动验收（计划 Task 4 的 6 场景：超集合并 / 重复收敛 / 日志型跳过 / 受众边界 / 不确认不改 / HANDOFF 自身去重）尚未正式跑。
- 如需扩展：按相同结构在 `plugins/<新名>/` 加插件，并在 `marketplace.json` 登记、扩展校验脚本。

## 🧠 关键决策与理由
- 去重取向：跨文档收敛为主、聚焦本次改动不做全项目扫描、标记+确认不自动改、日志型不碰、护栏保证不丢信息——即主流 DRY/SSOT 但不做「大手术」。否决「超集自动合并」「全项目 SSOT 重构」。
- `README` 只做概览、不复述 `SKILL` 的全部护栏，完整规则留在 `SKILL` 单一权威出处（SSOT）。
- 本项目直接在 `main` 提交并 push 发布（个人项目惯例）。
- 插件命令强制带命名空间（`/chinese:init`、`/sync:docs`）；续接靠 `HANDOFF.md` + `CLAUDE.md` 的 `@HANDOFF.md`；不自动 commit。

## 📁 重要文件
- `.claude-plugin/marketplace.json`：商店清单（登记 chinese、sync）。
- `plugins/chinese/skills/init/SKILL.md`：chinese 逻辑。
- `plugins/sync/skills/docs/SKILL.md`：sync 逻辑（含去重步骤 4 / 步骤 2）。
- `plugins/sync/.claude-plugin/plugin.json`：sync 插件清单（现 `1.1.0`）。
- `tests/validate-plugin.ps1`：结构校验脚本（26 项）。
- `docs/superpowers/specs/`、`docs/superpowers/plans/`：设计与实现计划（含 2026-06-10 去重）。

## ⚠️ 注意事项 / 坑
- `.ps1` 必须存为 **UTF-8 with BOM**；读取含中文的 JSON/MD 须带 `-Encoding UTF8`。
- 不要让 agent 直接写 `~/.claude/`（沙箱 + 自我修改护栏）；插件安装/升级由用户在 CLI 完成。
- **插件发新版后客户端升级**：先 bump `plugin.json` 的 `version`（同版本号会被判「已最新」跳过），再 `claude plugin marketplace update my-skills`（只刷新清单），**然后 `claude plugin update <plugin>@my-skills`**（才升级已装插件、在 `cache/.../  <版本号>/` 新建目录），最后 `/reload-plugins` 或重启。只跑 `marketplace update` 不会升级已装插件。
- `git push` 别加 `2>&1`（PS 5.1 会把 git 的 stderr 进度当 `NativeCommandError` 包装，误报失败）。
- 嵌套 `powershell -Command "..."` 会让外层先展开 `$` 变量——直接跑命令即可。

## ▶️ 常用命令
- `powershell -ExecutionPolicy Bypass -File tests\validate-plugin.ps1`：跑结构校验。
- `claude plugin marketplace update my-skills`：刷新商店清单。
- `claude plugin update <plugin>@my-skills`：升级已安装插件到新版。
- `claude plugin install <plugin>@my-skills`：首次安装插件。
- `git push origin main`：发布。
