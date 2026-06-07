# sync 插件 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `My-Skills` marketplace 内新增 `sync` 插件，提供 `/sync:docs` 命令：固化开发现场到 `HANDOFF.md`、在 `CLAUDE.md` 挂 `@HANDOFF.md` 自动加载，并 propose-confirm 刷新其它文档，支持新 session 无缝续接。

**Architecture:** 新插件 `plugins/sync/`，内含 skill `docs`（`skills/docs/SKILL.md`）。skill 逻辑用中文自然语言写在 SKILL.md，由模型运行时执行：读 git 状态与对话上下文 → 快照式重写 `HANDOFF.md` → 幂等地在 `CLAUDE.md` 加 `@HANDOFF.md` → 列清单等用户确认后刷新其它文档 → 汇报。

**Tech Stack:** Claude Code plugin/marketplace（JSON 清单 + Markdown skill）、Windows PowerShell 5.1（结构校验脚本）、git。

**对应 spec：** `docs/superpowers/specs/2026-06-07-sync-docs-plugin-design.md`

---

## 前置：确认 git 身份（若未设置）

- [ ] **确认本仓库提交身份已配置**

Run:
```
git -C "C:\Users\82370\Desktop\My Skills" config user.name
git -C "C:\Users\82370\Desktop\My Skills" config user.email
```
Expected: 分别输出 `hangwenlei` 与 `adrian_ipsaxu@mail.com`。若为空则执行：
```
git -C "C:\Users\82370\Desktop\My Skills" config user.name "hangwenlei"
git -C "C:\Users\82370\Desktop\My Skills" config user.email "adrian_ipsaxu@mail.com"
```
提交信息用简体中文，并以 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` 结尾。

---

## Task 1: 扩展结构校验脚本（自动化验收测试）

**Files:**
- Modify: `tests/validate-plugin.ps1`

- [ ] **Step 1: 用下述完整内容覆盖 `tests/validate-plugin.ps1`**

```powershell
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:fail = 0
function Check($cond, $msg) {
  if ($cond) { Write-Host "PASS: $msg" } else { Write-Host "FAIL: $msg"; $script:fail++ }
}

$mp = Join-Path $root '.claude-plugin\marketplace.json'
Check (Test-Path $mp) 'marketplace.json 存在'

# chinese 插件
$pj = Join-Path $root 'plugins\chinese\.claude-plugin\plugin.json'
$sk = Join-Path $root 'plugins\chinese\skills\init\SKILL.md'
Check (Test-Path $pj) 'chinese/plugin.json 存在'
Check (Test-Path $sk) 'chinese/SKILL.md 存在'

# sync 插件
$pj2 = Join-Path $root 'plugins\sync\.claude-plugin\plugin.json'
$sk2 = Join-Path $root 'plugins\sync\skills\docs\SKILL.md'
Check (Test-Path $pj2) 'sync/plugin.json 存在'
Check (Test-Path $sk2) 'sync/SKILL.md 存在'

$rd = Join-Path $root 'README.md'
Check (Test-Path $rd) 'README.md 存在'

if (Test-Path $mp) {
  $m = Get-Content $mp -Raw -Encoding UTF8 | ConvertFrom-Json
  Check ($m.name -eq 'my-skills') 'marketplace name = my-skills'
  Check ($null -ne $m.owner) 'marketplace 有 owner'
  foreach ($pn in @('chinese','sync')) {
    $cn = $m.plugins | Where-Object { $_.name -eq $pn }
    Check ($null -ne $cn) "marketplace 登记了 $pn 插件"
    if ($cn) {
      $srcPath = Join-Path $root ($cn.source -replace '/', '\')
      Check (Test-Path $srcPath) "$pn 插件 source 路径存在: $($cn.source)"
    }
  }
}

if (Test-Path $pj) {
  $p = Get-Content $pj -Raw -Encoding UTF8 | ConvertFrom-Json
  Check ($p.name -eq 'chinese') 'chinese plugin name = chinese'
  Check (-not [string]::IsNullOrWhiteSpace($p.description)) 'chinese plugin 有 description'
}
if (Test-Path $pj2) {
  $p2 = Get-Content $pj2 -Raw -Encoding UTF8 | ConvertFrom-Json
  Check ($p2.name -eq 'sync') 'sync plugin name = sync'
  Check (-not [string]::IsNullOrWhiteSpace($p2.description)) 'sync plugin 有 description'
}

if (Test-Path $sk) {
  $c = Get-Content $sk -Raw -Encoding UTF8
  Check ($c -match '(?m)^name:\s*init\s*$') 'chinese SKILL.md name = init'
  Check ($c -match 'disable-model-invocation:\s*true') 'chinese SKILL.md disable-model-invocation = true'
  Check ($c -match 'chinese:init start') 'chinese SKILL.md 含哨兵标记'
}
if (Test-Path $sk2) {
  $c2 = Get-Content $sk2 -Raw -Encoding UTF8
  Check ($c2 -match '(?m)^name:\s*docs\s*$') 'sync SKILL.md name = docs'
  Check ($c2 -match 'disable-model-invocation:\s*true') 'sync SKILL.md disable-model-invocation = true'
  Check ($c2 -match 'HANDOFF\.md') 'sync SKILL.md 提及 HANDOFF.md'
}

if ($script:fail -gt 0) { Write-Host "`n$script:fail 项失败"; exit 1 }
else { Write-Host "`n全部通过"; exit 0 }
```

- [ ] **Step 2: 重新转存为 UTF-8 with BOM（关键，否则 PS 5.1 中文乱码）**

Run:
```
$p='tests\validate-plugin.ps1'; $t=Get-Content -Raw -Encoding UTF8 $p; [System.IO.File]::WriteAllText((Resolve-Path $p), $t, (New-Object System.Text.UTF8Encoding $true))
```
Expected: 无输出（成功）。

- [ ] **Step 3: 运行校验脚本，确认它失败**

Run: `powershell -ExecutionPolicy Bypass -File "tests\validate-plugin.ps1"`
Expected: chinese 相关项 `PASS`，但 `sync/plugin.json 存在`、`sync/SKILL.md 存在`、`marketplace 登记了 sync 插件` 等 `FAIL`，结尾打印失败项数，退出码 1。

- [ ] **Step 4: 提交**

```
git add tests/validate-plugin.ps1
git commit -m "test: 校验脚本扩展覆盖 sync 插件

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: marketplace.json 增加 sync 条目

**Files:**
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: 用下述完整内容覆盖 `.claude-plugin/marketplace.json`**

```json
{
  "name": "my-skills",
  "owner": {
    "name": "hangwenlei"
  },
  "description": "hangwenlei 的个人 Claude Code 技能商店",
  "plugins": [
    {
      "name": "chinese",
      "source": "./plugins/chinese",
      "description": "把当前项目切换到中文输出模式"
    },
    {
      "name": "sync",
      "source": "./plugins/sync",
      "description": "固化开发现场到 HANDOFF.md 并刷新文档，支持新 session 无缝续接"
    }
  ]
}
```

- [ ] **Step 2: 验证 JSON 合法且含两个插件**

Run（直接在 PowerShell 里执行，勿再套 `powershell -Command`）:
```
$m = Get-Content '.claude-plugin\marketplace.json' -Raw -Encoding UTF8 | ConvertFrom-Json; if (($m.plugins | Where-Object { $_.name -eq 'chinese' }) -and ($m.plugins | Where-Object { $_.name -eq 'sync' })) { 'OK' } else { throw 'bad' }
```
Expected: 输出 `OK`。

- [ ] **Step 3: 提交**

```
git add .claude-plugin/marketplace.json
git commit -m "feat: marketplace 登记 sync 插件

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: sync 插件清单 plugin.json

**Files:**
- Create: `plugins/sync/.claude-plugin/plugin.json`

- [ ] **Step 1: 创建 `plugins/sync/.claude-plugin/plugin.json`**

```json
{
  "name": "sync",
  "version": "1.0.0",
  "description": "把当前开发现场固化进 HANDOFF.md 并挂到 CLAUDE.md 自动加载，同时按确认刷新其它文档，便于新 session 无缝续接",
  "author": {
    "name": "hangwenlei"
  }
}
```

- [ ] **Step 2: 验证 JSON 合法且字段正确**

Run:
```
$p = Get-Content 'plugins\sync\.claude-plugin\plugin.json' -Raw -Encoding UTF8 | ConvertFrom-Json; if ($p.name -eq 'sync' -and $p.description) { 'OK' } else { throw 'bad' }
```
Expected: 输出 `OK`。

- [ ] **Step 3: 提交**

```
git add plugins/sync/.claude-plugin/plugin.json
git commit -m "feat: 新增 sync 插件清单 plugin.json

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: SKILL.md（skill 本体）

**Files:**
- Create: `plugins/sync/skills/docs/SKILL.md`

- [ ] **Step 1: 创建 `plugins/sync/skills/docs/SKILL.md`，内容完整如下**

````markdown
---
name: docs
description: 固化当前开发现场到 HANDOFF.md、在 CLAUDE.md 挂 @HANDOFF.md 自动加载，并按 propose-confirm 刷新其它文档。仅在用户手动运行 /sync:docs 时执行。
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Bash
---

# 同步开发现场与文档

当用户运行 `/sync:docs` 时，把**当前工作目录所在项目**的开发现场固化进文档，使新 session 能无缝续接。严格按下面五步执行，全程用简体中文向用户汇报。

## 步骤 1：收集现场状态

运行并阅读以下命令的输出（用环境可用的 shell 执行 git；Windows 上用 PowerShell 亦可）：
- `git status`
- `git diff`（未暂存改动）与 `git diff --staged`（已暂存改动）
- `git log --oneline -15`（最近提交）

再读取项目根已存在的 `HANDOFF.md`（若有），并结合**当前对话上下文**（本 session 做了什么、关键决策、下一步打算）。

若当前目录不是 git 仓库：跳过 git 部分，仅依据对话上下文与现有文件生成 HANDOFF.md。

## 步骤 2：生成/更新项目根 `HANDOFF.md`（快照式整体重写）

**整体重写**该文件（不是追加），按下列固定结构组织。顶部写一行 `> 更新时间：<当前日期时间>`。某节确无内容时可省略该节。

```
# 开发现场交接（HANDOFF）

> 更新时间：<当前日期时间>

## 概览
<一句话：项目在做什么、当前处于哪个阶段>

## ✅ 已完成
- <具体条目，尽量带文件路径>

## 🔄 进行中
- <正在做的事；为什么卡住或待决策>

## ⏭️ 下一步
- <新 session 第一件应该做的事>

## 🧠 关键决策与理由
- <为什么选 X 不选 Y>

## 📁 重要文件
- `<路径>`：<作用>

## ⚠️ 注意事项 / 坑
- <易踩的坑、约束>

## ▶️ 常用命令
- `<命令>`：<用途>
```

内容要具体、可执行，避免空话套话。

## 步骤 3：挂自动加载（编辑 `CLAUDE.md`）

目的：让新 session 启动时自动把 HANDOFF.md 读入上下文。

1. 读取项目根 `CLAUDE.md`。
2. 若文件存在且已包含独占一行的 `@HANDOFF.md`：不做改动（幂等）。
3. 若文件存在但不含该行：在文件末尾追加一个空行 + 一行 `@HANDOFF.md`，原有内容一字不改。
4. 若文件不存在：创建 `CLAUDE.md`，内容为 `# CLAUDE.md` + 一个空行 + 一行 `@HANDOFF.md`。

## 步骤 4：刷新其它文档（先确认后改）

1. 基于步骤 1 的改动，扫描项目里**其它可能过时的文档**（如 README、设计/计划文档等手写 Markdown）。
2. 向用户**列出一张建议清单**，每项包含：文档路径、为什么需要更新、拟改要点。
3. **停下来等待用户确认**，让用户选择更新哪些（可全选、选部分、或都不改）。
4. **仅对用户确认的文档执行更新**；未确认的一律不改。
5. 本步骤不要执行 git commit。

## 步骤 5：向用户汇报

用简体中文总结：
- 创建/更新了哪些文件（HANDOFF.md、CLAUDE.md、以及已确认刷新的文档）；
- 提示用户用 `git diff` 复核改动、自行决定是否 commit；
- 说明：新 session 导入本项目后会自动加载 CLAUDE.md → 连带读入 HANDOFF.md，从而无缝续接。

不要执行任何与上述无关的操作。
````

- [ ] **Step 2: 验证 frontmatter 与关键内容**

Run:
```
$c = Get-Content 'plugins\sync\skills\docs\SKILL.md' -Raw -Encoding UTF8; if (($c -match '(?m)^name:\s*docs\s*$') -and ($c -match 'disable-model-invocation:\s*true') -and ($c -match 'HANDOFF\.md') -and ($c -match '@HANDOFF\.md')) { 'OK' } else { throw 'bad' }
```
Expected: 输出 `OK`。

- [ ] **Step 3: 提交**

```
git add plugins/sync/skills/docs/SKILL.md
git commit -m "feat: 新增 docs skill，实现 /sync:docs 逻辑

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: README 增补 sync 说明并跑通完整校验

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 在 `README.md` 的「chinese 插件」小节之后、`### 安装` 之前没有冲突的位置，追加下述「sync 插件」小节**

在 `README.md` 末尾追加以下内容：

````markdown

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
````

- [ ] **Step 2: 运行完整校验脚本，确认全部通过**

Run: `powershell -ExecutionPolicy Bypass -File "tests\validate-plugin.ps1"`
Expected: 所有项 `PASS`，结尾打印 `全部通过`，退出码 0。

- [ ] **Step 3: 提交**

```
git add README.md
git commit -m "docs: README 增补 sync 插件安装与使用说明

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: 功能性验证（临时 git 项目手动实测）

> SKILL.md 行为由模型执行，无法脚本单测；在临时 git 项目里按 SKILL.md 步骤亲自执行，验证产物与幂等。

**Files:**
- 临时验证目录（用完即删，不进仓库）

- [ ] **Step 1: 准备一个有未提交改动的临时 git 项目**

Run:
```
$base = "$env:TEMP\sync-docs-test"
Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $base | Out-Null
Set-Location $base
git init -b main | Out-Null
"# 演示项目`n`n这是一个用于验证 /sync:docs 的演示项目。" | Out-File -Encoding utf8 "$base\README.md"
git add -A; git -c user.name=t -c user.email=t@t commit -m "init" | Out-Null
"console.log('work in progress')" | Out-File -Encoding utf8 "$base\app.js"
Write-Host "BASE=$base ; 已有未提交新文件 app.js"
git -C $base status --short
```
Expected: 打印 BASE 路径；`git status` 显示 `?? app.js`（一个未提交改动）。

- [ ] **Step 2: 按 SKILL.md 步骤 1-3 执行：读 git 状态 → 写 `HANDOFF.md` → 在 `CLAUDE.md` 加 `@HANDOFF.md`**

按 SKILL.md：在 `$env:TEMP\sync-docs-test` 下用 Write 工具创建 `HANDOFF.md`（按模板，含「## 概览」「## ⏭️ 下一步」等节、含「> 更新时间：」），并创建 `CLAUDE.md`（内容为 `# CLAUDE.md` + 空行 + `@HANDOFF.md`，因为该目录原本无 CLAUDE.md）。

- [ ] **Step 3: 核对产物**

Run:
```
$d = "$env:TEMP\sync-docs-test"
"HANDOFF 含更新时间: " + ((Get-Content "$d\HANDOFF.md" -Raw -Encoding UTF8) -match '更新时间')
"HANDOFF 含下一步: " + ((Get-Content "$d\HANDOFF.md" -Raw -Encoding UTF8) -match '下一步')
"CLAUDE 含 @HANDOFF.md: " + ((Get-Content "$d\CLAUDE.md" -Raw -Encoding UTF8) -match '(?m)^@HANDOFF\.md\s*$')
```
Expected: 三行均为 `True`。

- [ ] **Step 4: 幂等验证——再执行一次步骤 3（CLAUDE.md 已含 `@HANDOFF.md`，应不重复添加）**

按 SKILL.md 步骤 3 的判定：CLAUDE.md 已含 `@HANDOFF.md`，故不改动 CLAUDE.md；HANDOFF.md 为整体重写。核对：
```
$d = "$env:TEMP\sync-docs-test"
"@HANDOFF.md 出现次数: " + ([regex]::Matches((Get-Content "$d\CLAUDE.md" -Raw -Encoding UTF8), '@HANDOFF\.md')).Count
```
Expected: `1`（未重复堆叠）。

- [ ] **Step 5: 清理临时目录**

Run:
```
Set-Location "C:\Users\82370\Desktop\My Skills"
Remove-Item "$env:TEMP\sync-docs-test" -Recurse -Force
```
Expected: 无输出（清理完成）。

> 若任一项不符预期：调整 `plugins/sync/skills/docs/SKILL.md` 对应步骤措辞使其更明确，重跑该项直到通过；修订后重新提交 SKILL.md。

---

## Task 7: 本地加载验证（可选但推荐）

- [ ] **Step 1: 本地把仓库当 marketplace 加载，检查无报错**

在 Claude Code CLI 运行：
```
/plugin marketplace add C:\Users\82370\Desktop\My Skills
/plugin
```
Expected: `/plugin` 菜单无该插件报错；Discover/Installed 中能看到 `sync` 插件。

> 用本地路径验证清单结构能被正确解析，避免发布后才发现问题。

---

## 发布（等用户确认后再做）

全部任务通过后，`git push origin main`。安装方式：`/plugin marketplace add hangwenlei/My-Skills` + `/plugin install sync@my-skills`。**push 由用户确认后执行。**

---

## Self-Review（计划对照 spec 自查）

- **Spec 覆盖：** §4 目录结构→Task 2/3/4；§5 五步逻辑→Task 4 SKILL.md；§6.1 marketplace 更新→Task 2；§6.2 plugin.json→Task 3；§6.3 SKILL.md→Task 4；§7 README→Task 5；§8 测试→Task 1（结构）+ Task 6（功能/幂等）；§9 安装说明→Task 5 README；全部有对应任务。
- **占位符：** 无 TBD/TODO；所有文件内容、命令、期望输出均完整给出。
- **命名/类型一致：** plugin 名 `sync`、skill 名 `docs`、命令 `/sync:docs`、source `./plugins/sync`、自动加载行 `@HANDOFF.md`、交接文件 `HANDOFF.md` 在校验脚本、清单、SKILL.md、README 中保持一致。
- **编码：** Task 1 已显式包含「改 .ps1 后重新转存 UTF-8 with BOM」步骤；所有读取含中文文件处均带 `-Encoding UTF8`。
