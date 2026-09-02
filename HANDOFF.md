<!-- sync:docs schema=2 -->
# 开发现场交接（HANDOFF）

## 概览

`My-Skills` 是同时面向 Claude Code 与 Codex 发布的个人技能市场，仓库
`https://github.com/hangwenlei/My-Skills`，含 `chinese`（1.1.0）与 `sync`（2.0.0）
两个插件。`sync` 2.0 于 2026-09-01 完成分层交接改造并 fast-forward 合并到 `main`，
`main` 与 `origin/main` 同为 `3bdfa37`。

本文件为 2.0 三层布局中的**稳定层**：只记跨分支成立的慢变事实。执行状态见
`.handoff/` 下与当前分支对应的现场文件；并行线看板在 common dir 的 `sync/lines/`。

## 🚀 运行现状

- 发布渠道：GitHub 仓库即 marketplace。Claude Code 用 `/plugin marketplace add
  hangwenlei/My-Skills` 后 `/plugin install <name>@my-skills`；Codex 用
  `codex plugin marketplace add hangwenlei/My-Skills` 后 `codex plugin add <name>@my-skills`。
- 本机 Claude Code：`sync@my-skills` 已升级到 2.0.0（user scope，enabled），
  需重启 Claude Code 才加载新版；`chinese@my-skills` 1.1.0。
- 本机 Codex：`sync` 仍为 1.2.0，待 `codex plugin marketplace upgrade my-skills` 后
  `codex plugin add sync@my-skills`；升级后需新开任务。
- 无部署服务、无端口、无外部依赖。

## 🔑 配置项清单

本项目不需要任何环境变量、密钥或外部服务凭据。

## 📁 重要文件

- `.claude-plugin/marketplace.json`：Claude marketplace 清单。
- `.agents/plugins/marketplace.json`：Codex native marketplace 清单。
- `plugins/chinese/`：chinese 的 Claude 薄入口、Codex manifest 与共享核心。
- `plugins/sync/`：sync 的 Claude 薄入口、Codex manifest 与共享核心
  （`codex/skills/docs/SKILL.md` 为 2.0 全部业务指令）。
- `README.md`：双平台安装、调用、升级、sync 2.0 三层说明与 1.x 迁移指引。
- `AGENTS.md`：Codex 中文输出与续接规则。
- `CLAUDE.md`、`.claude/settings.json`：Claude Code 中文输出与续接配置。
- `tests/validate-plugin.ps1`：结构、文本契约、安全闸门与版本的静态验证。
- `tests/gc-scenarios.ps1`：设计依赖的 git 行为事实、两个算法参考实现、以及在
  真实仓库上验证淘汰判据裁决的场景测试。
- `docs/superpowers/specs/2026-09-01-sync-v2-layered-handoff-design.md`：sync 2.0
  设计与全部实测事实（T1–T14）、已知限制。
- `docs/superpowers/specs/2026-07-23-claude-codex-dual-compat-design.md`：双平台
  兼容设计与安全契约。

## 🧠 长期决策与理由

- Claude 与 Codex 共用一个 Git 仓库但各自保留原生 marketplace 清单，不把一个平台
  的安装约定伪装成另一个平台的格式。
- 薄入口只声明宿主并读取共享核心，避免双份实现漂移；Codex 第三方 skill 用
  `$name:skill` 或 `/skills`，不虚构同名 slash alias。
- `sync` 2.0 把单文件交接拆为稳定层 / 分支现场 / 协同看板三层：分支现场文件名携带
  分支哈希使并行分支互不冲突；稳定层不设全局时间戳，新鲜度交给 `git blame`；
  看板每线一文件放 common dir，因单文件并发写实测会丢数据。
- 孤儿回收以「分支是否还存在」（`git branch -a`）为主判据、`--merged` 为次、时间
  判据兜底：单靠 `--merged` 在 squash merge 与 delete-on-merge 下全部失效。
- 休眠删除必须双条件（进入休眠超 30 天且分支仍无活动）并有退出休眠规则，否则
  重新活跃的分支会在第 30 天被误删。
- `sync` 默认只读安全元数据；raw diff 或测试输出必须在同一本地调用内脱敏后才返回，
  过滤失败时不回显原始内容。
- `sync` 不执行 `git commit`，也不读写 Claude 的 auto memory 目录。

## ⚠️ 注意事项 / 坑

- `tests/*.ps1` 必须是 UTF-8 with BOM；`SKILL.md` 以 YAML frontmatter 开头，
  **绝不能加 BOM**。补 BOM 只能用 ReadAllBytes → TrimStart(U+FEFF) → WriteAllText
  的方式，不能 `Get-Content -Raw`（会按代码页 936 解码毁掉中文）。
- 主干探测禁用 `git config init.defaultBranch`（实测其值与真实主干不符）。
- 分支现场文件名的哈希必须用命令算（`sha1sum` / `shasum` / PowerShell SHA1），
  禁止心算；macOS 无 `sha1sum`。
- 取当前分支名用 `git branch --show-current`，输出为空即游离 HEAD；不用
  `rev-parse --abbrev-ref HEAD`（游离时输出字面量 `HEAD`）。
- 2.0.1 待修：tier 2 传给 `git branch -a --merged <主干>` 的主干名无解析规则，
  本地无同名 `main` 时 exit 128 静默失效（安全侧，不删）。见设计 §10 第 6 条。
- 现有测试只证明「文本没退化」，skill 本身从未被测试驱动执行过；场景测试验证的
  是判据的 PowerShell 重写在真实仓库上的裁决。
- `.claude/worktrees/dazzling-hodgkin-9b4121` 是陈旧的 worktree 注册（目录已不存在，
  git 标记 prunable），属宿主管理。

## ▶️ 常用命令

- `powershell -NoProfile -ExecutionPolicy Bypass -File tests/validate-plugin.ps1`：
  全量静态验证（`-Section sync|docs|chinese|distribution` 可分节）。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tests/gc-scenarios.ps1`：
  git 行为契约与场景测试（`-Section env|algo|scenario`）。
- `claude plugin marketplace update my-skills` 后 `claude plugin update sync@my-skills`：
  升级本机 Claude 插件。
- `codex plugin marketplace upgrade my-skills` 后 `codex plugin add sync@my-skills`：
  升级本机 Codex 插件。
- `git status --short`、`git diff --check`：检查工作树与补丁格式。
