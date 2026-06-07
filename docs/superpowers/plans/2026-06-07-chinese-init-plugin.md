# chinese 插件 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `My-Skills` 仓库内建立一个可发布的 Claude Code 应用商店（marketplace），含一个 `chinese` 插件，提供 `/chinese:init` 命令把当前项目切换到中文输出模式。

**Architecture:** 仓库根作为 marketplace（`.claude-plugin/marketplace.json`），内含一个 plugin `chinese`（`plugins/chinese/`），plugin 内含一个 skill `init`（`plugins/chinese/skills/init/SKILL.md`）。skill 的逻辑用简体中文自然语言写在 SKILL.md 中，由模型在运行时执行：合并写入 `.claude/settings.json` 的 `language` 字段，并用哨兵标记在项目根 `CLAUDE.md` 写入「中文输出规范」（幂等）。

**Tech Stack:** Claude Code plugin/marketplace（JSON 清单 + Markdown skill）、Windows PowerShell 5.1（结构校验脚本）、git。

**对应 spec：** `docs/superpowers/specs/2026-06-07-chinese-init-plugin-design.md`

---

## 前置：确认 git 身份（一次性）

- [ ] **设置本仓库提交身份**

Run:
```
git -C "C:\Users\82370\Desktop\My Skills" config user.name "hangwenlei"
git -C "C:\Users\82370\Desktop\My Skills" config user.email "adrian_ipsaxu@mail.com"
```
之后各任务可直接用 `git commit`（无需每次 `-c`）。提交信息用简体中文，并以 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` 结尾。

---

## Task 1: 结构校验脚本（自动化验收测试）

**Files:**
- Create: `tests/validate-plugin.ps1`

- [ ] **Step 1: 写校验脚本（失败测试）**

创建 `tests/validate-plugin.ps1`，内容完整如下：

```powershell
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:fail = 0
function Check($cond, $msg) {
  if ($cond) { Write-Host "PASS: $msg" } else { Write-Host "FAIL: $msg"; $script:fail++ }
}

$mp = Join-Path $root '.claude-plugin\marketplace.json'
$pj = Join-Path $root 'plugins\chinese\.claude-plugin\plugin.json'
$sk = Join-Path $root 'plugins\chinese\skills\init\SKILL.md'
$rd = Join-Path $root 'README.md'

Check (Test-Path $mp) 'marketplace.json 存在'
Check (Test-Path $pj) 'plugin.json 存在'
Check (Test-Path $sk) 'SKILL.md 存在'
Check (Test-Path $rd) 'README.md 存在'

if (Test-Path $mp) {
  $m = Get-Content $mp -Raw | ConvertFrom-Json
  Check ($m.name -eq 'my-skills') 'marketplace name = my-skills'
  Check ($null -ne $m.owner) 'marketplace 有 owner'
  $cn = $m.plugins | Where-Object { $_.name -eq 'chinese' }
  Check ($null -ne $cn) 'marketplace 登记了 chinese 插件'
  if ($cn) {
    $srcPath = Join-Path $root ($cn.source -replace '/', '\')
    Check (Test-Path $srcPath) "chinese 插件 source 路径存在: $($cn.source)"
  }
}

if (Test-Path $pj) {
  $p = Get-Content $pj -Raw | ConvertFrom-Json
  Check ($p.name -eq 'chinese') 'plugin name = chinese'
  Check (-not [string]::IsNullOrWhiteSpace($p.description)) 'plugin 有 description'
}

if (Test-Path $sk) {
  $c = Get-Content $sk -Raw
  Check ($c -match '(?m)^name:\s*init\s*$') 'SKILL.md frontmatter name = init'
  Check ($c -match 'disable-model-invocation:\s*true') 'SKILL.md disable-model-invocation = true'
  Check ($c -match 'chinese:init start') 'SKILL.md 含哨兵标记'
}

if ($script:fail -gt 0) { Write-Host "`n$script:fail 项失败"; exit 1 }
else { Write-Host "`n全部通过"; exit 0 }
```

- [ ] **Step 2: 运行校验脚本，确认它失败**

Run: `powershell -ExecutionPolicy Bypass -File "tests\validate-plugin.ps1"`
Expected: 多条 `FAIL`（4 个文件都不存在），结尾打印失败项数，退出码 1。

- [ ] **Step 3: 提交**

```
git add tests/validate-plugin.ps1
git commit -m "test: 新增 chinese 插件结构校验脚本

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: marketplace.json

**Files:**
- Create: `.claude-plugin/marketplace.json`

- [ ] **Step 1: 创建 marketplace 清单**

创建 `.claude-plugin/marketplace.json`，内容完整如下：

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
    }
  ]
}
```

- [ ] **Step 2: 验证 JSON 合法且字段正确**

Run:
```
powershell -Command "$m = Get-Content '.claude-plugin\marketplace.json' -Raw | ConvertFrom-Json; if ($m.name -eq 'my-skills' -and ($m.plugins | Where-Object { $_.name -eq 'chinese' })) { 'OK' } else { throw 'bad' }"
```
Expected: 输出 `OK`（JSON 解析成功且含 chinese 插件登记）。

- [ ] **Step 3: 提交**

```
git add .claude-plugin/marketplace.json
git commit -m "feat: 新增 marketplace 清单并登记 chinese 插件

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: plugin.json

**Files:**
- Create: `plugins/chinese/.claude-plugin/plugin.json`

- [ ] **Step 1: 创建插件清单**

创建 `plugins/chinese/.claude-plugin/plugin.json`，内容完整如下：

```json
{
  "name": "chinese",
  "version": "1.0.0",
  "description": "把当前项目切换到中文输出模式：写入 settings.json 的 language 配置并在 CLAUDE.md 写明中文输出规范",
  "author": {
    "name": "hangwenlei"
  }
}
```

- [ ] **Step 2: 验证 JSON 合法且字段正确**

Run:
```
powershell -Command "$p = Get-Content 'plugins\chinese\.claude-plugin\plugin.json' -Raw | ConvertFrom-Json; if ($p.name -eq 'chinese' -and $p.description) { 'OK' } else { throw 'bad' }"
```
Expected: 输出 `OK`。

- [ ] **Step 3: 提交**

```
git add plugins/chinese/.claude-plugin/plugin.json
git commit -m "feat: 新增 chinese 插件清单 plugin.json

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: SKILL.md（skill 本体）

**Files:**
- Create: `plugins/chinese/skills/init/SKILL.md`

- [ ] **Step 1: 创建 SKILL.md**

创建 `plugins/chinese/skills/init/SKILL.md`，内容完整如下：

````markdown
---
name: init
description: 把当前项目切换到中文输出模式——写入 settings.json 的 language 配置并在 CLAUDE.md 追加中文输出规范。仅在用户手动运行 /chinese:init 时执行。
disable-model-invocation: true
allowed-tools: Read, Write, Edit
---

# 初始化项目中文模式

当用户运行 `/chinese:init` 时，把**当前工作目录所在的项目**切换到「中文输出模式」。严格按下面三步执行，全程用简体中文向用户汇报你做了什么。

## 步骤 1：写入 `.claude/settings.json`

目标：让该文件包含 `"language": "chinese"`，同时不破坏任何已有配置。

1. 尝试读取当前工作目录下的 `.claude/settings.json`。
2. 如果文件存在：解析其中的 JSON，把键 `language` 设为 `"chinese"`（已存在则覆盖该键），**保留其余所有键不变**，然后写回，保持 2 空格缩进。
3. 如果文件不存在：创建 `.claude/settings.json`，写入：

   ```json
   {
     "language": "chinese"
   }
   ```

   （用 Write 工具写文件会自动创建 `.claude/` 目录。）

## 步骤 2：写入项目根目录的 `CLAUDE.md`

目标：在 `CLAUDE.md` 中写入「中文输出规范」，用哨兵标记包裹以支持重复运行不重复堆叠。

规范块的固定内容（含首尾标记）如下，称为 **BLOCK**：

```
<!-- chinese:init start -->
## 语言与输出规范

- **始终使用简体中文回复**，包括任务过程中的所有输出：进度说明、计划与思路、工具调用前后的简短说明、错误分析、代码审查意见、最终总结。
- 代码、命令、文件路径、API 名称等技术标识保持英文原样（如 API、token、commit）；代码注释使用中文。
- Git 提交信息使用中文。
<!-- chinese:init end -->
```

操作：
1. 尝试读取当前工作目录下的 `CLAUDE.md`。
2. 如果文件不存在：创建 `CLAUDE.md`，内容为 `# CLAUDE.md` + 一个空行 + BLOCK。
3. 如果文件存在且同时包含 `<!-- chinese:init start -->` 与 `<!-- chinese:init end -->`：用 BLOCK **替换**这两个标记（含标记本身）之间的全部内容，其余内容一字不改。
4. 如果文件存在但不包含上述标记：在文件**末尾**追加一个空行 + BLOCK，原有内容一字不改。

## 步骤 3：向用户汇报

用简体中文简要说明：
- 创建/更新了 `.claude/settings.json`（已设置 `language: chinese`）；
- 创建/更新了 `CLAUDE.md`（已写入中文输出规范）；
- 提示：中文模式已开启，建议在新会话中生效；技术术语（API、token、commit 等）仍保持英文。

不要执行任何与上述无关的操作。
````

- [ ] **Step 2: 验证 frontmatter 正确**

Run:
```
powershell -Command "$c = Get-Content 'plugins\chinese\skills\init\SKILL.md' -Raw; if (($c -match '(?m)^name:\s*init\s*$') -and ($c -match 'disable-model-invocation:\s*true') -and ($c -match 'chinese:init start')) { 'OK' } else { throw 'bad' }"
```
Expected: 输出 `OK`。

- [ ] **Step 3: 提交**

```
git add plugins/chinese/skills/init/SKILL.md
git commit -m "feat: 新增 init skill，实现 /chinese:init 逻辑

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: README.md 并跑通完整校验

**Files:**
- Create: `README.md`

- [ ] **Step 1: 创建 README**

创建 `README.md`，内容完整如下：

````markdown
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
````

- [ ] **Step 2: 运行完整校验脚本，确认全部通过**

Run: `powershell -ExecutionPolicy Bypass -File "tests\validate-plugin.ps1"`
Expected: 所有项 `PASS`，结尾打印 `全部通过`，退出码 0。

- [ ] **Step 3: 提交**

```
git add README.md
git commit -m "docs: 新增 README 安装与使用说明

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: 功能性验证（临时目录手动实测）

> SKILL.md 的运行时行为由模型执行，无法用脚本单测；按 spec §8 在临时目录手动验证四个场景。**注意：要在一个会话里实际 `/chinese:init` 才能触发；本任务用脚本预置目录状态并在 init 后核对结果。**

**Files:**
- 临时验证目录（用完即删，不进仓库）

- [ ] **Step 1: 准备四个测试场景目录**

Run:
```
$base = "$env:TEMP\chinese-init-test"
Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$base\empty" | Out-Null
New-Item -ItemType Directory -Force "$base\has-settings\.claude" | Out-Null
'{ "theme": "dark" }' | Out-File -Encoding utf8 "$base\has-settings\.claude\settings.json"
New-Item -ItemType Directory -Force "$base\has-claudemd" | Out-Null
"# 原有项目说明`n`n这段不能被破坏。" | Out-File -Encoding utf8 "$base\has-claudemd\CLAUDE.md"
Write-Host "测试目录已就绪: $base"
```
Expected: 打印测试目录路径；其中 `empty/` 空、`has-settings/` 已有含 `theme` 的 settings.json、`has-claudemd/` 已有 CLAUDE.md。

- [ ] **Step 2: 场景 1（空目录）— 在 `%TEMP%\chinese-init-test\empty` 运行 `/chinese:init`，核对结果**

核对：
```
$d = "$env:TEMP\chinese-init-test\empty"
(Get-Content "$d\.claude\settings.json" -Raw | ConvertFrom-Json).language   # 期望: chinese
Select-String -Path "$d\CLAUDE.md" -Pattern 'chinese:init start','语言与输出规范' | Select-Object -ExpandProperty Line
```
Expected: `language` 为 `chinese`；CLAUDE.md 含哨兵标记与「语言与输出规范」。

- [ ] **Step 3: 场景 2（已有 settings.json）— 在 `has-settings` 运行 `/chinese:init`，核对原有键保留**

核对：
```
$s = Get-Content "$env:TEMP\chinese-init-test\has-settings\.claude\settings.json" -Raw | ConvertFrom-Json
"$($s.theme) / $($s.language)"   # 期望: dark / chinese
```
Expected: 输出 `dark / chinese`（原有 `theme` 保留，新增 `language`）。

- [ ] **Step 4: 场景 3（已有 CLAUDE.md）— 在 `has-claudemd` 运行 `/chinese:init`，核对原内容保留**

核对：
```
$c = Get-Content "$env:TEMP\chinese-init-test\has-claudemd\CLAUDE.md" -Raw
($c -match '这段不能被破坏') -and ($c -match 'chinese:init start')   # 期望: True
```
Expected: `True`（原有内容保留，且规范块已追加）。

- [ ] **Step 5: 场景 4（幂等）— 在 `has-claudemd` 再次运行一次 `/chinese:init`，核对不重复堆叠**

核对：
```
$c = Get-Content "$env:TEMP\chinese-init-test\has-claudemd\CLAUDE.md" -Raw
([regex]::Matches($c, 'chinese:init start')).Count   # 期望: 1
```
Expected: `1`（标记块只出现一次，未重复堆叠）。

- [ ] **Step 6: 清理临时目录**

Run: `Remove-Item "$env:TEMP\chinese-init-test" -Recurse -Force`
Expected: 无输出（清理完成）。

> 若任一场景不符合预期：调整 `plugins/chinese/skills/init/SKILL.md` 中对应步骤的措辞使其更明确，重跑该场景，直到四个场景全部通过；修订后重新提交 SKILL.md。

---

## Task 7: 本地加载验证（可选但推荐）

- [ ] **Step 1: 本地把仓库当 marketplace 加载，检查无报错**

在 Claude Code 中运行：
```
/plugin marketplace add C:\Users\82370\Desktop\My Skills
/plugin
```
检查 `/plugin` 菜单的 Errors 标签无该插件报错，Discover/Installed 中能看到 `chinese` 插件。
Expected: 无加载错误，`chinese` 插件可见。

> 这一步用本地路径验证清单结构能被 Claude Code 正确解析，避免发布后他人安装才发现 JSON/结构问题。

---

## 发布（等用户确认后再做）

全部任务通过后，`git push origin main` 推送到 GitHub。仓库需公开他人方可 `/plugin marketplace add hangwenlei/My-Skills`。**push 由用户确认后执行，不在自动实现范围内。**

---

## Self-Review（计划对照 spec 自查）

- **Spec 覆盖：** §3 目录结构→Task 2/3/4；§4 运行时行为→Task 4 SKILL.md 三步；§5 规范模板→Task 4 BLOCK；§6 三个配置文件→Task 2/3/4；§7 README→Task 5；§8 测试四场景→Task 6；§9 发布→「发布」小节。全部有对应任务。
- **占位符：** 无 TBD/TODO；所有文件内容、命令、期望输出均完整给出。
- **类型/命名一致：** 哨兵标记统一为 `<!-- chinese:init start -->` / `<!-- chinese:init end -->`；plugin 名 `chinese`、skill 名 `init`、marketplace 名 `my-skills`、source `./plugins/chinese` 在校验脚本、清单、SKILL.md、README 中一致。
