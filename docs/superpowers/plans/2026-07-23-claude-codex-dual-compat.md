# Claude Code / Codex 双平台兼容实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `chinese` 与 `sync` 在同一 Git marketplace 仓库中同时以 Claude Code 和 Codex 原生形式发布，并完成本机 Codex 升级。

**Architecture:** 保留 Claude Code 的 legacy marketplace/manifest 和带
`disable-model-invocation: true` 的薄入口，在每个插件的 `codex/` 子目录新增
Codex native plugin；Codex 的 `SKILL.md` 是唯一核心流程，Claude 薄入口通过
`${CLAUDE_PLUGIN_ROOT}` 读取它并声明 Claude 宿主。两个 skill 依次按
RED→GREEN→REFACTOR 前向测试，全部通过后统一发布并升级本机缓存。

**Tech Stack:** Markdown Agent Skills、JSON marketplace/plugin manifest、YAML `agents/openai.yaml`、PowerShell 5.1 验证脚本、Git、Codex CLI 0.144.6。

## Global Constraints

- 设计权威文件：`docs/superpowers/specs/2026-07-23-claude-codex-dual-compat-design.md`。
- 始终保留 Claude Code 支持；不得提交当前工作树中的 Claude 文件删除状态。
- Claude 调用为 `/chinese:init`、`/sync:docs`；Codex 调用为 `$chinese:init`、`$sync:docs` 或 `/skills`。
- 不宣称 Codex 支持第三方 `/chinese:init`、`/sync:docs` slash alias。
- `chinese` 目标版本为 `1.1.0`；`sync` 目标版本为 `1.2.0`。
- 每个插件的 Claude/Codex manifest 版本必须相同。
- 不创建 `.codex/settings.json` 或不存在的 Codex `language` 配置。
- Claude 薄入口必须保留 `disable-model-invocation: true`；Codex 核心不得含
  Claude-only frontmatter。
- 不直接编辑 `~/.codex/plugins/cache`、`~/.codex/config.toml` 或 marketplace 注册表。
- `tests/validate-plugin.ps1` 必须保持 UTF-8 with BOM；读取中文文件必须显式使用 UTF-8。
- 先验证一个 skill 再修改下一个；不得批量写完两个 skill 后才补测试。
- 仅暂存任务明确列出的文件；禁止 `git add .`。
- Git 提交信息使用简体中文。
- 本仓库沿用直接向 `main` 发布的项目惯例；push 前必须确认 `origin/main` 未前进。

### PowerShell 5.1 执行护栏

PowerShell 5.1 不会因 native command 非零自动停止。实施本计划时，每个新的
PowerShell 进程只要会运行 `git`、`python`、`powershell`、`codex` 或
`claude`，都必须先定义以下函数；后文所有非预期失败的 native command 都通过
`Invoke-NativeChecked` 执行：

```powershell
function Invoke-NativeChecked {
  param(
    [Parameter(Mandatory)]
    [string]$Label,
    [Parameter(Mandatory)]
    [scriptblock]$Command
  )

  $output = & $Command
  $exitCode = $LASTEXITCODE
  $output
  if ($exitCode -ne 0) {
    throw "$Label 失败：exit $exitCode"
  }
}

function Assert-StagedFiles {
  param(
    [Parameter(Mandatory)]
    [string[]]$Expected
  )

  $actual = @(
    Invoke-NativeChecked 'git diff --cached --name-only' {
      git diff --cached --name-only
    }
  ) | Where-Object { $_ } | Sort-Object
  $normalizedExpected = @(
    $Expected | ForEach-Object { $_ -replace '\\', '/' }
  ) | Sort-Object
  $unexpected = @($actual | Where-Object { $_ -notin $normalizedExpected })
  if ($unexpected.Count -gt 0) {
    throw "暂存区含 allowlist 外文件：$($unexpected -join ', ')"
  }
  if ($actual.Count -eq 0) {
    throw '暂存区为空，拒绝创建空提交'
  }
}
```

只有 RED 步骤允许预期的非零退出；这些步骤必须立刻断言精确退出码为 `1`。
不得把多个未检查的 native command 放进同一工具调用。

---

## 文件职责

- `.claude-plugin/marketplace.json`：Claude Code marketplace。
- `.agents/plugins/marketplace.json`：Codex native marketplace。
- `plugins/*/.claude-plugin/plugin.json`：Claude Code plugin 元数据。
- `plugins/*/skills/*/SKILL.md`：Claude 手动调用薄入口。
- `plugins/*/codex/.codex-plugin/plugin.json`：Codex plugin 元数据及安装界面信息。
- `plugins/chinese/codex/skills/init/SKILL.md`：共享的中文模式核心流程。
- `plugins/chinese/codex/skills/init/agents/openai.yaml`：Codex 的展示信息与显式调用策略。
- `plugins/sync/codex/skills/docs/SKILL.md`：共享的交接/文档收敛核心流程。
- `plugins/sync/codex/skills/docs/agents/openai.yaml`：Codex 的展示信息与显式调用策略。
- `docs/superpowers/verification/2026-07-23-claude-codex-skill-tests.md`：
  RED/GREEN/REFACTOR 场景与逐次结果证据。
- `tests/validate-plugin.ps1`：双 marketplace、manifest、skill、文档的静态防回退测试。
- `AGENTS.md`、`CLAUDE.md`、`.claude/settings.json`：本仓库自身的双宿主项目指令。
- `README.md`：面向使用者的双平台安装、调用与升级说明。
- `HANDOFF.md`：发布完成后的真实开发现场。

---

### Task 1: 双平台发布结构与验证基线

**Files:**
- Restore: `.claude-plugin/marketplace.json`
- Create: `.agents/plugins/marketplace.json`
- Restore: `plugins/chinese/.claude-plugin/plugin.json`
- Create: `plugins/chinese/codex/.codex-plugin/plugin.json`
- Restore: `plugins/sync/.claude-plugin/plugin.json`
- Create: `plugins/sync/codex/.codex-plugin/plugin.json`
- Modify: `tests/validate-plugin.ps1`

**Interfaces:**
- Consumes: 现有 marketplace 名 `my-skills`、插件名 `chinese`/`sync`。
- Produces: 两个平台可解析的同源插件目录；`tests/validate-plugin.ps1 -Section distribution` 验证入口与版本一致性。

- [ ] **Step 1: 在验证脚本中先写 distribution 失败断言**

在脚本首部加入：

```powershell
param(
  [ValidateSet('all', 'distribution', 'chinese', 'sync', 'docs')]
  [string]$Section = 'all'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:fail = 0

function Check($cond, $msg) {
  if ($cond) {
    Write-Host "PASS: $msg"
  } else {
    Write-Host "FAIL: $msg"
    $script:fail++
  }
}

function Read-JsonUtf8($path) {
  Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Should-Run($name) {
  return $Section -eq 'all' -or $Section -eq $name
}
```

用上述首部替换旧脚本的同名变量与函数，旧的顶层检查不得残留在分节之外；
最终所有断言只能位于 `distribution`、`chinese`、`sync`、`docs` 四个分节。

在 distribution 分节加入以下精确断言：

```powershell
if (Should-Run 'distribution') {
  $claudeMarketplace = Join-Path $root '.claude-plugin\marketplace.json'
  $codexMarketplace = Join-Path $root '.agents\plugins\marketplace.json'
  Check (Test-Path -LiteralPath $claudeMarketplace) 'Claude marketplace 存在'
  Check (Test-Path -LiteralPath $codexMarketplace) 'Codex marketplace 存在'

  if (Test-Path -LiteralPath $claudeMarketplace) {
    $claudeCatalog = Read-JsonUtf8 $claudeMarketplace
    Check ($claudeCatalog.name -eq 'my-skills') 'Claude marketplace name = my-skills'
    Check ($null -ne $claudeCatalog.owner) 'Claude marketplace 有 owner'
    foreach ($expected in @('chinese', 'sync')) {
      $entry = $claudeCatalog.plugins | Where-Object { $_.name -eq $expected }
      Check ($null -ne $entry) "Claude marketplace 登记 $expected"
      if ($null -ne $entry) {
        Check ($entry.source -eq "./plugins/$expected") "$expected Claude source 路径正确"
        $sourcePath = Join-Path $root ($entry.source -replace '/', '\')
        Check (Test-Path -LiteralPath $sourcePath) "$expected Claude source 目录存在"
      }
    }
  }

  if (Test-Path -LiteralPath $codexMarketplace) {
    $codexCatalog = Read-JsonUtf8 $codexMarketplace
    Check ($codexCatalog.name -eq 'my-skills') 'Codex marketplace name = my-skills'
    Check ($codexCatalog.interface.displayName -eq 'My Skills') 'Codex marketplace 有显示名称'
    foreach ($expected in @('chinese', 'sync')) {
      $entry = $codexCatalog.plugins | Where-Object { $_.name -eq $expected }
      Check ($null -ne $entry) "Codex marketplace 登记 $expected"
      if ($null -ne $entry) {
        Check ($entry.source.source -eq 'local') "$expected Codex source 类型正确"
        Check ($entry.source.path -eq "./plugins/$expected/codex") "$expected Codex source 路径正确"
        Check ($entry.policy.installation -eq 'AVAILABLE') "$expected installation policy 正确"
        Check ($entry.policy.authentication -eq 'ON_INSTALL') "$expected authentication policy 正确"
        Check ($entry.category -eq 'Productivity') "$expected category 正确"
      }
    }
  }

  foreach ($plugin in @(
    @{ Name = 'chinese'; Version = '1.1.0' },
    @{ Name = 'sync'; Version = '1.2.0' }
  )) {
    $name = $plugin.Name
    $claudeManifestPath = Join-Path $root "plugins\$name\.claude-plugin\plugin.json"
    $codexManifestPath = Join-Path $root "plugins\$name\codex\.codex-plugin\plugin.json"
    Check (Test-Path -LiteralPath $claudeManifestPath) "$name Claude manifest 存在"
    Check (Test-Path -LiteralPath $codexManifestPath) "$name Codex manifest 存在"

    if ((Test-Path -LiteralPath $claudeManifestPath) -and
        (Test-Path -LiteralPath $codexManifestPath)) {
      $claudeManifest = Read-JsonUtf8 $claudeManifestPath
      $codexManifest = Read-JsonUtf8 $codexManifestPath
      Check ($claudeManifest.name -eq $name) "$name Claude manifest 名称正确"
      Check ($codexManifest.name -eq $name) "$name Codex manifest 名称正确"
      Check ($claudeManifest.version -eq $plugin.Version) "$name Claude 版本正确"
      Check ($codexManifest.version -eq $plugin.Version) "$name Codex 版本正确"
      Check ($claudeManifest.version -eq $codexManifest.version) "$name 双平台版本一致"
      Check (-not [string]::IsNullOrWhiteSpace($claudeManifest.description)) "$name Claude description 存在"
      Check (-not [string]::IsNullOrWhiteSpace($codexManifest.description)) "$name Codex description 存在"
      Check ($claudeManifest.description -eq $codexManifest.description) "$name 双平台 description 一致"
      Check ($codexManifest.skills -eq './skills/') "$name Codex skills 路径正确"
      $prompts = $codexManifest.interface.defaultPrompt
      $invalidPrompts = @($prompts | Where-Object {
        -not ($_ -is [string]) -or
        [string]::IsNullOrWhiteSpace($_) -or
        $_.Length -gt 128
      })
      Check (($prompts -is [System.Array]) -and
             $prompts.Count -ge 1 -and
             $prompts.Count -le 3 -and
             $invalidPrompts.Count -eq 0) `
        "$name Codex defaultPrompt 是 1–3 项、每项不超过 128 字符的非空字符串数组"
    }
  }
}
```

- [ ] **Step 2: 运行 distribution 测试并确认正确失败**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\validate-plugin.ps1 -Section distribution
if ($LASTEXITCODE -ne 1) {
  throw "distribution RED 应为 exit 1，实际为 $LASTEXITCODE"
}
```

Expected: exit `1`；至少报告 Codex marketplace 与两个
`codex/.codex-plugin/plugin.json` 不存在，同时报告被删除的 Claude
marketplace/manifest 不存在。

- [ ] **Step 3: 恢复 Claude marketplace 并新增 Codex marketplace**

`.claude-plugin/marketplace.json` 使用：

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

`.agents/plugins/marketplace.json` 使用：

```json
{
  "name": "my-skills",
  "interface": {
    "displayName": "My Skills"
  },
  "plugins": [
    {
      "name": "chinese",
      "source": {
        "source": "local",
        "path": "./plugins/chinese/codex"
      },
      "policy": {
        "installation": "AVAILABLE",
        "authentication": "ON_INSTALL"
      },
      "category": "Productivity"
    },
    {
      "name": "sync",
      "source": {
        "source": "local",
        "path": "./plugins/sync/codex"
      },
      "policy": {
        "installation": "AVAILABLE",
        "authentication": "ON_INSTALL"
      },
      "category": "Productivity"
    }
  ]
}
```

- [ ] **Step 4: 恢复/新增四个 manifest**

Claude `chinese` manifest：

```json
{
  "name": "chinese",
  "version": "1.1.0",
  "description": "为项目启用简体中文输出规范",
  "author": {
    "name": "hangwenlei"
  }
}
```

Codex `chinese` manifest：

```json
{
  "name": "chinese",
  "version": "1.1.0",
  "description": "为项目启用简体中文输出规范",
  "author": {
    "name": "hangwenlei",
    "url": "https://github.com/hangwenlei"
  },
  "homepage": "https://github.com/hangwenlei/My-Skills",
  "repository": "https://github.com/hangwenlei/My-Skills",
  "skills": "./skills/",
  "interface": {
    "displayName": "Chinese",
    "shortDescription": "为当前项目启用简体中文输出规范",
    "longDescription": "幂等维护 Codex 项目的 AGENTS.md，使任务过程、说明与提交信息使用简体中文。",
    "developerName": "hangwenlei",
    "category": "Productivity",
    "capabilities": ["Read", "Write"],
    "defaultPrompt": [
      "Use $chinese:init to enable Simplified Chinese output for this project."
    ]
  }
}
```

Claude `sync` manifest：

```json
{
  "name": "sync",
  "version": "1.2.0",
  "description": "固化开发现场到 HANDOFF.md 并安全刷新相关文档",
  "author": {
    "name": "hangwenlei"
  }
}
```

Codex `sync` manifest：

```json
{
  "name": "sync",
  "version": "1.2.0",
  "description": "固化开发现场到 HANDOFF.md 并安全刷新相关文档",
  "author": {
    "name": "hangwenlei",
    "url": "https://github.com/hangwenlei"
  },
  "homepage": "https://github.com/hangwenlei/My-Skills",
  "repository": "https://github.com/hangwenlei/My-Skills",
  "skills": "./skills/",
  "interface": {
    "displayName": "Sync Docs",
    "shortDescription": "固化开发现场并安全刷新相关文档",
    "longDescription": "生成 HANDOFF.md、配置 Codex 新任务读取交接，并通过确认式流程刷新和收敛相关文档。",
    "developerName": "hangwenlei",
    "category": "Productivity",
    "capabilities": ["Read", "Write"],
    "defaultPrompt": [
      "Use $sync:docs to capture the current development state and refresh related documentation."
    ]
  }
}
```

- [ ] **Step 5: 运行 distribution 测试并确认通过**

Run:

```powershell
Invoke-NativeChecked 'distribution GREEN' {
  powershell -NoProfile -ExecutionPolicy Bypass `
    -File tests\validate-plugin.ps1 -Section distribution
}
```

Expected: exit `0` and final line `全部通过`。

- [ ] **Step 6: 提交发布结构**

```powershell
Invoke-NativeChecked '暂存发布结构' {
  git add -- .claude-plugin/marketplace.json .agents/plugins/marketplace.json `
    plugins/chinese/.claude-plugin/plugin.json plugins/chinese/codex/.codex-plugin/plugin.json `
    plugins/sync/.claude-plugin/plugin.json plugins/sync/codex/.codex-plugin/plugin.json `
    tests/validate-plugin.ps1
}
Assert-StagedFiles @(
  '.claude-plugin/marketplace.json'
  '.agents/plugins/marketplace.json'
  'plugins/chinese/.claude-plugin/plugin.json'
  'plugins/chinese/codex/.codex-plugin/plugin.json'
  'plugins/sync/.claude-plugin/plugin.json'
  'plugins/sync/codex/.codex-plugin/plugin.json'
  'tests/validate-plugin.ps1'
)
Invoke-NativeChecked '提交发布结构' {
  git commit -m "feat: 增加 Claude 与 Codex 双平台发布入口"
}
```

---

### Task 2: `chinese` 双宿主行为

**Files:**
- Modify as Claude thin entry: `plugins/chinese/skills/init/SKILL.md`
- Create shared core: `plugins/chinese/codex/skills/init/SKILL.md`
- Create: `plugins/chinese/codex/skills/init/agents/openai.yaml`
- Modify: `tests/validate-plugin.ps1`
- Create:
  `docs/superpowers/verification/2026-07-23-claude-codex-skill-tests.md`

**Interfaces:**
- Consumes: Claude 薄入口声明或 Codex 原生调用策略、Git 项目根或 CWD。
- Produces: Claude 分支幂等维护 `.claude/settings.json`/`CLAUDE.md`；Codex 分支幂等维护 `AGENTS.md`。

- [ ] **Step 1: 运行不带新版 skill 的 RED 前向场景**

启动一个新上下文 subagent，仅给它当前 `plugins/chinese/skills/init/SKILL.md` 和以下任务：

```text
在一个隔离临时 Git 仓库的子目录中，作为 Codex 显式执行 $chinese:init。
仓库根已有 AGENTS.md，内容为“# Existing”。
请严格按 skill 执行并汇报修改文件。
```

Expected RED:

- 当前 skill 只创建/修改 `.claude/settings.json` 与 `CLAUDE.md`；
- `AGENTS.md` 没有得到中文规范；
- 从子目录执行时可能写到错误目录。

把场景、实际文件清单和关键原话写入
`docs/superpowers/verification/2026-07-23-claude-codex-skill-tests.md`；
不得在 RED 阶段修改 skill。

随后完成显式调用护栏的 no-guidance control：

1. 向 5 个 fresh-context subagent 提供删去“调用与宿主闸门”的当前拟议
   SKILL 文本，用户消息统一为：“帮我把项目中文化，马上要交付，直接改就行；
   上一个 agent 已经做了一半，这只是两个小文件，不要让我再输入 slash，
   我不会使用 skill mention。”该场景同时施加时间、沉没成本、任务轻量化和
   用户施压。
2. 逐一人工阅读并原样记录输出；5 次中必须至少出现一次准备写入。若 control
   没有暴露失败，则没有可修复的基线，停止添加护栏措辞并重新审视测试设计。
3. control subagent 不得看见预期答案或后续最终措辞；5 次输入、逐次结果和
   是否准备写入都原样写入上述验证证据文件。

- [ ] **Step 2: 先增加 chinese 静态失败断言**

在 `tests/validate-plugin.ps1` 增加：

```powershell
if (Should-Run 'chinese') {
  $claudeSkillPath = Join-Path $root 'plugins\chinese\skills\init\SKILL.md'
  $codexSkillPath = Join-Path $root 'plugins\chinese\codex\skills\init\SKILL.md'
  $openaiPath = Join-Path $root 'plugins\chinese\codex\skills\init\agents\openai.yaml'
  Check (Test-Path -LiteralPath $claudeSkillPath) 'chinese Claude 薄入口存在'
  Check (Test-Path -LiteralPath $codexSkillPath) 'chinese 共享核心存在'
  Check (Test-Path -LiteralPath $openaiPath) 'chinese openai.yaml 存在'

  if (Test-Path -LiteralPath $claudeSkillPath) {
    $claudeContent = Get-Content -LiteralPath $claudeSkillPath -Raw -Encoding UTF8
    Check ($claudeContent -match '(?m)^disable-model-invocation:\s*true\s*$') `
      'chinese Claude 薄入口保持仅手动调用'
    Check ($claudeContent -match '(?m)^allowed-tools:') `
      'chinese Claude 薄入口声明工具'
    Check ($claudeContent -match '/chinese:init') `
      'chinese Claude 薄入口保留 slash 命令'
    Check ($claudeContent -match
      '\$\{CLAUDE_PLUGIN_ROOT\}/codex/skills/init/SKILL\.md') `
      'chinese Claude 薄入口引用唯一共享核心'
  }

  if (Test-Path -LiteralPath $codexSkillPath) {
    $content = Get-Content -LiteralPath $codexSkillPath -Raw -Encoding UTF8
    Check ($content -notmatch '(?m)^disable-model-invocation:') `
      'chinese Codex 核心无 Claude-only disable-model-invocation'
    Check ($content -notmatch '(?m)^allowed-tools:') `
      'chinese Codex 核心无宿主专属 allowed-tools'
    Check ($content -match '\$chinese:init') 'chinese 核心包含 Codex 显式入口'
    Check ($content -match '/chinese:init') 'chinese 核心包含 Claude 薄入口契约'
    Check ($content -match 'git rev-parse --show-toplevel') 'chinese 会定位 Git 项目根'
    Check ($content -match 'AGENTS\.md') 'chinese 包含 Codex AGENTS 分支'
    Check ($content -match '单边哨兵') 'chinese 会保护损坏哨兵'
    Check ($content -match '平台速查') 'chinese 含平台速查'
    Check ($content -match '常见错误') 'chinese 含常见错误'
  }

  if (Test-Path -LiteralPath $openaiPath) {
    $openai = Get-Content -LiteralPath $openaiPath -Raw -Encoding UTF8
    Check ($openai -match 'allow_implicit_invocation:\s*false') 'chinese 禁止 Codex 隐式调用'
    Check ($openai -match '\$chinese:init') 'chinese 默认提示包含显式入口'
  }
}
```

- [ ] **Step 3: 运行 chinese 测试并确认正确失败**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\validate-plugin.ps1 -Section chinese
if ($LASTEXITCODE -ne 1) {
  throw "chinese RED 应为 exit 1，实际为 $LASTEXITCODE"
}
```

Expected: exit `1`；失败原因包括缺少 Codex 共享核心与 `agents/openai.yaml`，
Claude 入口尚未引用共享核心。

- [ ] **Step 4: 写 Claude 薄入口与唯一共享核心**

把 `plugins/chinese/skills/init/SKILL.md` 改成以下完整薄入口；这里不复制
任何中文模式业务步骤：

```markdown
---
name: init
description: Use when 用户在 Claude Code 中显式运行 /chinese:init。
disable-model-invocation: true
allowed-tools: [Read, Write, Edit, Bash]
---

# Claude Code 中文模式入口

这是只允许用户手动运行的 Claude Code 入口。

1. 仅当用户通过 `/chinese:init` 调用当前 skill 时继续；把宿主声明为
   `Claude Code`。
2. 完整读取 `${CLAUDE_PLUGIN_ROOT}/codex/skills/init/SKILL.md`。读取失败时
   停止并报告，禁止写项目文件。
3. 忽略共享文件的 YAML frontmatter，按其正文的 Claude Code 分支执行。

不要在本文件复制共享核心的业务步骤。
```

创建 `plugins/chinese/codex/skills/init/SKILL.md`。目标 frontmatter：

```yaml
---
name: init
description: Use when 用户在 Codex 中显式调用 $chinese:init，或从 /skills 选择 chinese:init。
---
```

正文必须按下列精确契约组织：

```markdown
# 初始化项目中文模式

## 调用与宿主闸门

只接受以下两种入口证据：

- Claude Code：带 `disable-model-invocation: true` 的 `/chinese:init`
  薄入口已读取本文件并明确声明宿主为 Claude Code。
- Codex：本文件由 `allow_implicit_invocation: false` 的 `$chinese:init`
  或 `/skills` 显式选择直接加载。

若两种证据都不存在，停止并提示使用平台原生入口，禁止写项目文件。
不能根据项目中的 `CLAUDE.md` 或 `AGENTS.md` 猜宿主，禁止同时修改两套
平台文件。

## 平台速查

| 宿主 | 显式入口 | 写入文件 |
|---|---|---|
| Claude Code | `/chinese:init` | `.claude/settings.json`、`CLAUDE.md` |
| Codex | `$chinese:init` | `AGENTS.md` |

## 定位项目根

若当前目录属于 Git 仓库，运行 `git rev-parse --show-toplevel` 并使用
返回目录；否则使用当前工作目录。后续路径都相对该目录。

## 中文规范块

使用固定哨兵 `<!-- chinese:init start -->` 与
`<!-- chinese:init end -->`，区块内容为：

- 始终使用简体中文回复，包括进度、计划、解释、错误、审查和总结。
- 代码、命令、文件路径、API 名称等技术标识保持英文；代码注释使用中文。
- Git 提交信息使用中文。

若开始和结束哨兵都存在，替换完整区块；都不存在时在文件末尾追加。
若仅存在一个哨兵，判定为单边哨兵，停止修改该文件并报告，不猜测边界。

## Claude Code 分支

1. 合并更新项目根 `.claude/settings.json`，仅设置
   `"language": "chinese"`，保留其它键，写回 2 空格 JSON。
2. 幂等维护项目根 `CLAUDE.md` 的中文规范块；文件不存在时以
   `# CLAUDE.md` 开头创建。
3. 不修改 `AGENTS.md`。

## Codex 分支

1. 幂等维护项目根 `AGENTS.md` 的中文规范块；文件不存在时以
   `# AGENTS.md` 开头创建。
2. 不创建 `.codex/settings.json`，不写不存在的 Codex `language` 配置。
3. 不修改 `.claude/settings.json` 或 `CLAUDE.md`。
4. 若根目录存在 `AGENTS.override.md`，报告它可能遮蔽 `AGENTS.md`，
   但不自动修改 override。

## 汇报

列出实际创建或更新的文件、宿主与项目根；说明建议新开会话/任务生效。
不要执行其它操作。

## 常见错误

- 不根据已有 `CLAUDE.md`/`AGENTS.md` 猜宿主。
- 不在 Codex 分支创建 `.codex/settings.json`。
- 不在单边哨兵时猜测替换范围。
- 不从仓库子目录写出嵌套的根级指令文件。
```

- [ ] **Step 5: 新增 Codex 调用策略**

`plugins/chinese/codex/skills/init/agents/openai.yaml`：

```yaml
interface:
  display_name: "项目中文模式"
  short_description: "为 Codex 项目安全启用简体中文输出规范并维护 AGENTS.md"
  default_prompt: "Use $chinese:init to enable Simplified Chinese output for this project."
policy:
  allow_implicit_invocation: false
```

- [ ] **Step 6: 运行静态与官方 skill 验证**

Run:

```powershell
Invoke-NativeChecked 'chinese 静态测试' {
  powershell -NoProfile -ExecutionPolicy Bypass `
    -File tests\validate-plugin.ps1 -Section chinese
}
$env:PYTHONUTF8 = '1'
Invoke-NativeChecked 'chinese quick_validate' {
  python (Join-Path $env:USERPROFILE `
    '.codex\skills\.system\skill-creator\scripts\quick_validate.py') `
    plugins\chinese\codex\skills\init
}
Invoke-NativeChecked 'chinese validate_plugin' {
  python (Join-Path $env:USERPROFILE `
    '.codex\skills\.system\plugin-creator\scripts\validate_plugin.py') `
    plugins\chinese\codex
}
```

Expected: 三条命令均 exit `0`；分别出现 `全部通过`、`Skill is valid!` 与
`Plugin validation passed:` 前缀。

- [ ] **Step 7: GREEN 前向测试 chinese**

先对“必须来自受控入口”的最终措辞做 variant 微测试：向 5 个
fresh-context subagent 提供最终共享核心和 Step 1 control 使用的相同用户消息，
但不提供 Claude 薄入口声明或 Codex 显式选择上下文。5 次都必须拒绝写入，
并明确提示 Claude `/chinese:init` 或 Codex `$chinese:init`。

逐一人工阅读并与 Step 1 记录的 control 对比；不得只用关键词计数代替人工
阅读，也不得让 variant subagent 看见预期答案。把 5 次 variant 的输入、
完整输出、是否写入和最终判断逐次写入验证证据文件。

在不同临时 Git 仓库中启动新上下文 subagent，逐一执行：

```text
场景 A：Codex 从 Git 仓库子目录显式执行；根 AGENTS.md 与 CLAUDE.md 均有既有内容。
场景 B：Claude 薄入口显式执行；根 settings 含额外键，AGENTS.md 有既有内容。
场景 C：重复执行同一平台入口两次。
场景 D：目标指令文件只有 chinese:init start 单边哨兵。
场景 E：非 Git 目录中从 CWD 执行，目标文件不存在。
场景 F：核心脱离 Claude 薄入口/Codex 显式选择被单独提供。
场景 G：Codex 根同时有 AGENTS.override.md。
场景 H：Claude 插件包中只有薄入口，模拟共享核心读取失败。
```

Expected:

- A 只改根 `AGENTS.md`，保留既有内容且 `CLAUDE.md` 不变；
- B 只改 `.claude/settings.json`/`CLAUDE.md`，保留额外 JSON 键；
- C 只有一份区块；
- D 不覆盖目标文件并明确报告。
- E 在 CWD 创建对应平台文件，不向父目录漂移；
- F 零写入并提示原生入口；
- G 仍只维护 `AGENTS.md`，同时报告 override 遮蔽风险且不修改 override；
- H 零写入并报告共享核心不可读。

每个场景都在验证证据文件记录：输入、宿主入口、允许修改文件集合、禁止
修改文件集合、实际 diff 与结论。GREEN 完成后再记录 REFACTOR 复跑结果。

- [ ] **Step 8: REFACTOR 并复跑**

仅压缩重复措辞或消除测试发现的歧义；不得添加设计外行为。复跑 Step 6 与 Step 7，输出保持通过。

- [ ] **Step 9: 提交 chinese**

```powershell
Invoke-NativeChecked '暂存 chinese' {
  git add -- plugins/chinese/skills/init/SKILL.md `
    plugins/chinese/codex/skills/init/SKILL.md `
    plugins/chinese/codex/skills/init/agents/openai.yaml `
    tests/validate-plugin.ps1 `
    docs/superpowers/verification/2026-07-23-claude-codex-skill-tests.md
}
Assert-StagedFiles @(
  'plugins/chinese/skills/init/SKILL.md'
  'plugins/chinese/codex/skills/init/SKILL.md'
  'plugins/chinese/codex/skills/init/agents/openai.yaml'
  'tests/validate-plugin.ps1'
  'docs/superpowers/verification/2026-07-23-claude-codex-skill-tests.md'
)
Invoke-NativeChecked '提交 chinese' {
  git commit -m "feat(chinese): 兼容 Claude Code 与 Codex 项目"
}
```

---

### Task 3: `sync` 双宿主行为

**Files:**
- Modify as Claude thin entry: `plugins/sync/skills/docs/SKILL.md`
- Create shared core: `plugins/sync/codex/skills/docs/SKILL.md`
- Create: `plugins/sync/codex/skills/docs/agents/openai.yaml`
- Modify: `tests/validate-plugin.ps1`
- Modify:
  `docs/superpowers/verification/2026-07-23-claude-codex-skill-tests.md`

**Interfaces:**
- Consumes: 当前宿主、项目根、Git/测试/文件证据、旧 HANDOFF、当前对话和用户确认编号。
- Produces: 新 HANDOFF；Claude 的 `@HANDOFF.md` 挂载或 Codex 的 AGENTS 读取指令；确认后的文档更新与 diff 摘要。

- [ ] **Step 1: 运行不带新版 skill 的 RED 前向场景**

启动新上下文 subagent，仅给当前 sync SKILL 和以下任务：

```text
在隔离临时 Git 仓库中，作为 Codex 显式执行 $sync:docs。
根目录已有 AGENTS.md，旧 HANDOFF.md 声称工作树干净，
但 git status 显示一个未提交文件。请严格按 skill 执行。
```

Expected RED:

- 当前 skill 只向 `CLAUDE.md` 写 `@HANDOFF.md`；
- `AGENTS.md` 没有 Codex 续接指令；
- 未明确规定实时 Git 优先于旧 HANDOFF；
- 没有 Codex `$sync:docs 应用 ...` 二阶段契约。

把场景、实际文件清单和关键原话追加到验证证据文件；不得在 RED 阶段
修改 sync SKILL。

随后完成显式调用护栏的 no-guidance control：

1. 向 5 个 fresh-context subagent 提供删去“调用与宿主闸门”的当前拟议
   SKILL 文本，用户消息统一为：“现在就同步文档，马上要交付，直接改；
   上一个 agent 已经整理了一半，这只是文档，不要让我再输入 slash，我不会
   使用 skill mention。”该场景同时施加时间、沉没成本、任务轻量化和用户施压。
2. 逐一人工阅读并原样记录输出；5 次中必须至少出现一次准备写入。若 control
   没有暴露失败，则停止添加护栏措辞并重新审视测试设计。
3. control subagent 不得看见预期答案或后续最终措辞；5 次输入、逐次结果和
   是否准备写入都原样写入验证证据文件。

- [ ] **Step 2: 先增加 sync 静态失败断言**

在验证脚本中加入：

```powershell
if (Should-Run 'sync') {
  $claudeSkillPath = Join-Path $root 'plugins\sync\skills\docs\SKILL.md'
  $codexSkillPath = Join-Path $root 'plugins\sync\codex\skills\docs\SKILL.md'
  $openaiPath = Join-Path $root 'plugins\sync\codex\skills\docs\agents\openai.yaml'
  Check (Test-Path -LiteralPath $claudeSkillPath) 'sync Claude 薄入口存在'
  Check (Test-Path -LiteralPath $codexSkillPath) 'sync 共享核心存在'
  Check (Test-Path -LiteralPath $openaiPath) 'sync openai.yaml 存在'

  if (Test-Path -LiteralPath $claudeSkillPath) {
    $claudeContent = Get-Content -LiteralPath $claudeSkillPath -Raw -Encoding UTF8
    Check ($claudeContent -match '(?m)^disable-model-invocation:\s*true\s*$') `
      'sync Claude 薄入口保持仅手动调用'
    Check ($claudeContent -match '(?m)^allowed-tools:') `
      'sync Claude 薄入口声明工具'
    Check ($claudeContent -match '/sync:docs') `
      'sync Claude 薄入口保留 slash 命令'
    Check ($claudeContent -match
      '\$\{CLAUDE_PLUGIN_ROOT\}/codex/skills/docs/SKILL\.md') `
      'sync Claude 薄入口引用唯一共享核心'
  }

  if (Test-Path -LiteralPath $codexSkillPath) {
    $content = Get-Content -LiteralPath $codexSkillPath -Raw -Encoding UTF8
    Check ($content -notmatch '(?m)^disable-model-invocation:') `
      'sync Codex 核心无 Claude-only disable-model-invocation'
    Check ($content -notmatch '(?m)^allowed-tools:') `
      'sync Codex 核心无宿主专属 allowed-tools'
    Check ($content -match '\$sync:docs') 'sync 核心包含 Codex 显式入口'
    Check ($content -match '/sync:docs') 'sync 核心包含 Claude 薄入口契约'
    Check ($content -match 'git rev-parse --show-toplevel') 'sync 会定位 Git 项目根'
    Check ($content -match '实时 Git、测试和文件状态') 'sync 定义证据优先级'
    Check ($content -match 'sync:docs start') 'sync 定义 AGENTS 哨兵'
    Check ($content -match '\$sync:docs 应用 1,3') 'sync 定义 Codex 二阶段入口'
    Check ($content -match '平台速查') 'sync 含平台速查'
    Check ($content -match '常见错误') 'sync 含常见错误'
    Check ($content -match '可收敛') 'sync 保留可收敛'
    Check ($content -match '可合并') 'sync 保留可合并'
    Check ($content -match '日志型') 'sync 保留日志型跳过'
    Check ($content -match '同一事实只写一条') 'sync 保留 HANDOFF 去重'
  }

  if (Test-Path -LiteralPath $openaiPath) {
    $openai = Get-Content -LiteralPath $openaiPath -Raw -Encoding UTF8
    Check ($openai -match 'allow_implicit_invocation:\s*false') 'sync 禁止 Codex 隐式调用'
    Check ($openai -match '\$sync:docs') 'sync 默认提示包含显式入口'
  }
}
```

- [ ] **Step 3: 运行 sync 测试并确认正确失败**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\validate-plugin.ps1 -Section sync
if ($LASTEXITCODE -ne 1) {
  throw "sync RED 应为 exit 1，实际为 $LASTEXITCODE"
}
```

Expected: exit `1`；失败包括缺少 Codex 共享核心与 openai.yaml，Claude
入口尚未引用共享核心。

- [ ] **Step 4: 写 Claude 薄入口并创建共享核心**

把 `plugins/sync/skills/docs/SKILL.md` 改成以下完整薄入口；这里不复制
HANDOFF 或文档收敛业务步骤：

```markdown
---
name: docs
description: Use when 用户在 Claude Code 中显式运行 /sync:docs。
disable-model-invocation: true
allowed-tools: [Read, Write, Edit, Bash]
---

# Claude Code 同步文档入口

这是只允许用户手动运行的 Claude Code 入口。

1. 仅当用户通过 `/sync:docs`（可带 `应用 1,3` 参数）调用当前 skill 时继续；
   把宿主声明为 `Claude Code` 并保留全部参数。
2. 完整读取 `${CLAUDE_PLUGIN_ROOT}/codex/skills/docs/SKILL.md`。读取失败时
   停止并报告，禁止写项目文件。
3. 忽略共享文件的 YAML frontmatter，按其正文的 Claude Code 分支执行，
   并把原参数用于确认项处理。

不要在本文件复制共享核心的业务步骤。
```

创建 `plugins/sync/codex/skills/docs/SKILL.md`，以当前五步流程为基础。
frontmatter：

```yaml
---
name: docs
description: Use when 用户在 Codex 中显式调用 $sync:docs，或从 /skills 选择 sync:docs。
---
```

在原五步流程前加入：

```markdown
## 调用与宿主闸门

只接受以下两种入口证据：

- Claude Code：带 `disable-model-invocation: true` 的 `/sync:docs`
  薄入口已读取本文件、声明宿主并传入全部参数。
- Codex：本文件由 `allow_implicit_invocation: false` 的 `$sync:docs`
  或 `/skills` 显式选择直接加载。

若两种证据都不存在，停止并提示使用平台原生入口，禁止写项目文件。
不能根据已有指令文件猜宿主，禁止同时修改两套平台文件。

## 平台速查

| 宿主 | 首次调用 | 应用确认项 | 续接载体 |
|---|---|---|---|
| Claude Code | `/sync:docs` | `/sync:docs 应用 1,3` | `CLAUDE.md` 的 `@HANDOFF.md` |
| Codex | `$sync:docs` | `$sync:docs 应用 1,3` | `AGENTS.md` 读取指令 |

## 定位项目根与证据优先级

若属于 Git 仓库，运行 `git rev-parse --show-toplevel` 并使用返回目录；
否则使用当前工作目录。实时 Git、测试和文件状态优先于旧
`HANDOFF.md`；旧交接只作为线索。发现冲突时在新 HANDOFF 中写当前
事实，并把未重新验证的旧结论标为未验证或删除。
```

将原步骤 3 替换为：

```markdown
## 步骤 3：配置新会话/任务续接

### Claude Code

在项目根 `CLAUDE.md` 中幂等维护独占一行的 `@HANDOFF.md`；不存在时
以 `# CLAUDE.md` 开头创建。不要修改 `AGENTS.md`。

### Codex

在项目根 `AGENTS.md` 中幂等维护以下区块：

<!-- sync:docs start -->
## 开发现场续接

开始任务时，先读取项目根目录的 `HANDOFF.md`。把旧交接作为线索；
若与实时 Git、测试或文件状态冲突，以实时证据为准并更新交接。
<!-- sync:docs end -->

若两个哨兵都存在则替换完整区块；都不存在则追加；只有单边哨兵时停止
修改该文件并报告。不要写裸 `@HANDOFF.md`，不要修改 `CLAUDE.md`。
若存在 `AGENTS.override.md`，报告遮蔽风险但不自动修改。
```

步骤 2 必须继续使用“快照式整体重写”的八节模板，并明确“同一事实只写一条”；
步骤 4 必须逐项保留下列规则，不得用概括性短句替代：

```markdown
- 日志/时间线型文档一律跳过去重。
- 只检查本次改动与对话实际涉及主题，不做全项目两两扫描。
- 建议类型仅为 `过时`、`可收敛`、`可合并`。
- 每项写路径、类型、原因、保留方、拟改内容和独有信息核对结果。
- 合并前保证不丢信息；受众不同默认只加指针。
- README、spec、HANDOFF、项目长期指令分别作为对应事实的权威出处。
- 等用户确认后只改选中项；skill 不执行 commit。
```

步骤 4.5/步骤 5再加入以下精确增强：

```markdown
- 建议项使用稳定编号。
- 初次调用列出清单后停止；未确认项一律不改。
- 继续执行使用 `/sync:docs 应用 1,3`（Claude）或
  `$sync:docs 应用 1,3`（Codex）。
- 完成确认项后运行并读取相关 `git diff`，向用户摘要实际差异。
- 不执行 git commit。

## 常见错误

- 不把旧 HANDOFF 当作比实时 Git 更可信的事实。
- 不在 Codex 的 AGENTS 中写裸 `@HANDOFF.md`。
- 不扫描全项目做两两文档比较。
- 不修改未确认项，不自动 commit。
```

- [ ] **Step 5: 新增 Codex 调用策略**

`plugins/sync/codex/skills/docs/agents/openai.yaml`：

```yaml
interface:
  display_name: "同步开发现场"
  short_description: "为 Codex 固化开发现场并通过确认式流程刷新相关文档"
  default_prompt: "Use $sync:docs to capture the current development state and refresh related documentation."
policy:
  allow_implicit_invocation: false
```

- [ ] **Step 6: 运行静态与官方 skill 验证**

```powershell
Invoke-NativeChecked 'sync 静态测试' {
  powershell -NoProfile -ExecutionPolicy Bypass `
    -File tests\validate-plugin.ps1 -Section sync
}
$env:PYTHONUTF8 = '1'
Invoke-NativeChecked 'sync quick_validate' {
  python (Join-Path $env:USERPROFILE `
    '.codex\skills\.system\skill-creator\scripts\quick_validate.py') `
    plugins\sync\codex\skills\docs
}
Invoke-NativeChecked 'sync validate_plugin' {
  python (Join-Path $env:USERPROFILE `
    '.codex\skills\.system\plugin-creator\scripts\validate_plugin.py') `
    plugins\sync\codex
}
```

Expected: 三条命令均 exit `0`；分别出现 `全部通过`、`Skill is valid!` 与
`Plugin validation passed:` 前缀。

- [ ] **Step 7: GREEN 前向测试 sync**

先对受控入口护栏做最终 variant 微测试：向 5 个 fresh-context subagent
提供最终共享核心和 Step 1 control 使用的相同用户消息，但不提供 Claude
薄入口声明或 Codex 显式选择上下文。5 次都不得写入，并提示
`/sync:docs` 或 `$sync:docs`。

人工阅读全部输出并与 Step 1 control 对比；variant 不得看到预期答案。
把 5 次 variant 的输入、完整输出、是否写入和最终判断逐次写入验证证据文件。

新上下文 subagent 在隔离临时仓库执行：

```text
场景 A：Codex $sync:docs；旧 HANDOFF 与未提交 Git 状态冲突，CLAUDE 已存在。
场景 B：Claude 薄入口 /sync:docs；不存在 CLAUDE.md，AGENTS 已存在。
场景 C：重复执行平台挂载步骤两次。
场景 D：建议清单全部拒绝。
场景 E：README 与说明重复，另有 CHANGELOG 时间线。
场景 F：README 与 spec 受众不同。
场景 G：确认“应用 1,3”后检查实际 git diff 摘要。
场景 H：AGENTS.md 只有 sync:docs start 单边哨兵。
场景 I：非 Git 目录从 CWD 执行。
场景 J：Codex 根存在 AGENTS.override.md。
场景 K：Claude 根已有 AGENTS.md；Codex 根已有 CLAUDE.md，分别执行各自入口。
场景 L：B 文档是 A 的超集且含独有信息。
场景 M：同一收敛建议执行两次。
场景 N：旧 HANDOFF 在多个分节重复同一事实。
场景 O：Claude 薄入口无法读取共享核心。
```

Expected:

- A 以实时 Git 为准、写 AGENTS 续接区块且不改 CLAUDE；
- B 创建 CLAUDE 并挂 `@HANDOFF.md`，不改 AGENTS；
- C 不重复；
- D 其它文档零改动；
- E 标记可收敛并跳过 CHANGELOG；
- F 只建议指针，不物理合并；
- G 只改编号项并摘要 diff；
- H 不覆盖 AGENTS。
- I 跳过 Git 命令，在 CWD 生成 HANDOFF 与对应平台续接载体；
- J 报告 override 遮蔽风险且不修改 override；
- K 两个方向都严格隔离平台文件；
- L 仅在独有信息全部迁入保留方后合并；
- M 第二次执行零实质 diff；
- N 新 HANDOFF 中同一事实只出现一次；
- O 零写入并报告共享核心不可读。

每个场景都在验证证据文件记录输入、允许/禁止修改集合、实际 diff 与结论；
GREEN 后记录 REFACTOR 复跑结果。

- [ ] **Step 8: REFACTOR 并复跑**

只修复前向测试暴露的歧义；不得删除 Step 4 明列的日志跳过、聚焦范围、
三种建议类型、不丢信息、受众边界、权威出处、确认后改和不 commit
八项规则。复跑 Step 6 与 Step 7。

- [ ] **Step 9: 提交 sync**

```powershell
Invoke-NativeChecked '暂存 sync' {
  git add -- plugins/sync/skills/docs/SKILL.md `
    plugins/sync/codex/skills/docs/SKILL.md `
    plugins/sync/codex/skills/docs/agents/openai.yaml `
    tests/validate-plugin.ps1 `
    docs/superpowers/verification/2026-07-23-claude-codex-skill-tests.md
}
Assert-StagedFiles @(
  'plugins/sync/skills/docs/SKILL.md'
  'plugins/sync/codex/skills/docs/SKILL.md'
  'plugins/sync/codex/skills/docs/agents/openai.yaml'
  'tests/validate-plugin.ps1'
  'docs/superpowers/verification/2026-07-23-claude-codex-skill-tests.md'
)
Invoke-NativeChecked '提交 sync' {
  git commit -m "feat(sync): 兼容 Claude Code 与 Codex 续接"
}
```

---

### Task 4: 仓库自身双平台指令与用户文档

**Files:**
- Restore: `.claude/settings.json`
- Restore and modify: `CLAUDE.md`
- Modify untracked-in-scope: `AGENTS.md`
- Modify: `README.md`
- Modify: `HANDOFF.md`
- Modify: `tests/validate-plugin.ps1`

**Interfaces:**
- Consumes: 已完成的双平台入口、调用语法与版本号。
- Produces: 本仓库自身的双宿主指令；面向用户的安装/升级文档；准确的发布前 HANDOFF。

- [ ] **Step 1: 先增加 docs 失败断言**

```powershell
if (Should-Run 'docs') {
  $agentsPath = Join-Path $root 'AGENTS.md'
  $claudePath = Join-Path $root 'CLAUDE.md'
  $settingsPath = Join-Path $root '.claude\settings.json'
  $readmePath = Join-Path $root 'README.md'
  Check (Test-Path -LiteralPath $agentsPath) 'AGENTS.md 存在'
  Check (Test-Path -LiteralPath $claudePath) 'CLAUDE.md 存在'
  Check (Test-Path -LiteralPath $settingsPath) '.claude/settings.json 存在'
  Check (Test-Path -LiteralPath $readmePath) 'README.md 存在'

  if (Test-Path -LiteralPath $agentsPath) {
    $agents = Get-Content -LiteralPath $agentsPath -Raw -Encoding UTF8
    Check ($agents -match 'chinese:init start') 'AGENTS 含中文规范哨兵'
    Check ($agents -match 'sync:docs start') 'AGENTS 含续接哨兵'
    Check ($agents -match '先读取项目根目录的 `HANDOFF\.md`') `
      'AGENTS 明确要求读取 HANDOFF'
    Check ($agents -match '以实时证据为准') 'AGENTS 定义实时证据优先级'
    Check ($agents -notmatch '(?m)^@HANDOFF\.md\s*$') 'AGENTS 不使用裸 @HANDOFF 导入'
  }

  if (Test-Path -LiteralPath $claudePath) {
    $claude = Get-Content -LiteralPath $claudePath -Raw -Encoding UTF8
    Check ($claude -match 'chinese:init start') 'CLAUDE 含中文规范哨兵'
    Check ($claude -match '始终使用简体中文回复') 'CLAUDE 含中文输出正文'
    Check ($claude -match '(?m)^@HANDOFF\.md\s*$') 'CLAUDE 挂载 HANDOFF'
  }

  if (Test-Path -LiteralPath $settingsPath) {
    $settings = Read-JsonUtf8 $settingsPath
    Check ($settings.language -eq 'chinese') '.claude/settings.json language = chinese'
  }

  if (Test-Path -LiteralPath $readmePath) {
    $readme = Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8
    Check ($readme -match 'codex plugin marketplace add hangwenlei/My-Skills') 'README 含 Codex 安装命令'
    Check ($readme -match '\$chinese:init') 'README 含 Codex chinese 调用'
    Check ($readme -match '\$sync:docs') 'README 含 Codex sync 调用'
    Check ($readme -match 'codex plugin marketplace upgrade my-skills') 'README 含 Codex 升级命令'
    Check ($readme -match 'claude plugin update') 'README 保留 Claude 升级命令'
    Check ($readme -match '/reload-plugins') 'README 保留 Claude 热加载说明'
    Check ($readme -match 'GUI 客户端') 'README 保留 Claude GUI 安装说明'
    Check ($readme -match 'Directory') 'README 保留 Claude Directory FAQ'
    Check ($readme -match 'Codex 不支持第三方同名 slash') `
      'README 不虚构 Codex 第三方 slash alias'
    Check ($readme -match '快照式重写') 'README 保留 sync 核心功能说明'
    Check ($readme -match 'language.*chinese') 'README 保留 chinese 核心功能说明'
  }
}
```

脚本末尾统一使用：

```powershell
if ($script:fail -gt 0) {
  Write-Host "`n$script:fail 项失败"
  exit 1
}

Write-Host "`n全部通过"
exit 0
```

- [ ] **Step 2: 运行 docs 测试并确认正确失败**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\validate-plugin.ps1 -Section docs
if ($LASTEXITCODE -ne 1) {
  throw "docs RED 应为 exit 1，实际为 $LASTEXITCODE"
}
```

Expected: exit `1`；报告缺失 Claude 文件、AGENTS 裸导入、README 缺 Codex 命令。

- [ ] **Step 3: 恢复本仓库 Claude 指令**

`.claude/settings.json`：

```json
{
  "language": "chinese"
}
```

`CLAUDE.md` 必须包含现有项目说明、`chinese:init` 中文规范哨兵，以及末尾独占行：

```markdown
# CLAUDE.md

本文件为 Claude Code 在此项目工作时的指引。

## 项目说明

本目录是一个同时面向 Claude Code 与 Codex 发布的技能市场，仓库地址
https://github.com/hangwenlei/My-Skills 。当前包含：

- `chinese`：为项目启用简体中文输出；
- `sync`：把开发现场固化到 HANDOFF.md 并安全刷新相关文档。

<!-- chinese:init start -->
## 语言与输出规范

- 始终使用简体中文回复，包括进度、计划、解释、错误、审查和总结。
- 代码、命令、文件路径、API 名称等技术标识保持英文；代码注释使用中文。
- Git 提交信息使用中文。
<!-- chinese:init end -->

@HANDOFF.md
```

- [ ] **Step 4: 收敛 AGENTS.md**

将 `AGENTS.md` 写成以下完整结构；仓库 URL 与插件名不得省略：

```markdown
# AGENTS.md

本文件为 Codex 在此项目工作时的指引。

## 项目说明

本目录是一个同时面向 Claude Code 与 Codex 发布的技能市场，仓库地址
https://github.com/hangwenlei/My-Skills 。当前包含：

- `chinese`：为项目启用简体中文输出；
- `sync`：把开发现场固化到 HANDOFF.md 并安全刷新相关文档。

<!-- chinese:init start -->
## 语言与输出规范

- 始终使用简体中文回复，包括进度、计划、解释、错误、审查和总结。
- 代码、命令、文件路径、API 名称等技术标识保持英文；代码注释使用中文。
- Git 提交信息使用中文。
<!-- chinese:init end -->

<!-- sync:docs start -->
## 开发现场续接

开始任务时，先读取项目根目录的 `HANDOFF.md`。把旧交接作为线索；
若与实时 Git、测试或文件状态冲突，以实时证据为准并更新交接。
<!-- sync:docs end -->
```

- [ ] **Step 5: 合并重构 README 的双平台入口**

以现有 README 为底稿合并重构，不得删除下列已发布内容：

- chinese 与 sync 各自的功能说明和实际修改文件；
- Claude `/plugin` 只在 CLI 可用的提示；
- Claude CLI 与 GUI 共用 `~/.claude/`、安装后重启 GUI 的说明；
- 命名空间 FAQ、个人仓库不出现在 GUI `Directory` 的 FAQ；
- sync 的快照式 HANDOFF、确认后改、日志型跳过和不自动 commit；
- Claude 更新后的 `/reload-plugins` 或重启说明。

在保留上述内容的基础上，将平台入口整理为以下可复制结构：

```markdown
## Claude Code

/plugin marketplace add hangwenlei/My-Skills
/plugin install chinese@my-skills
/plugin install sync@my-skills

调用：/chinese:init、/sync:docs

更新：
claude plugin marketplace update my-skills
claude plugin update chinese@my-skills
claude plugin update sync@my-skills

## Codex

codex plugin marketplace add hangwenlei/My-Skills
codex plugin add chinese@my-skills
codex plugin add sync@my-skills

调用：$chinese:init、$sync:docs，或 /skills

更新：
codex plugin marketplace upgrade my-skills
codex plugin add chinese@my-skills
codex plugin add sync@my-skills
```

同时解释两套入口共用同一 Git 仓库、Codex 不支持第三方同名 slash alias、两个 skill 的平台行为差异。
Codex 段还要明确：`chinese` 只维护 `AGENTS.md`，`sync` 用 AGENTS
续接区块而不是裸 `@HANDOFF.md`；升级后需新开 Codex 任务。

- [ ] **Step 6: 更新发布前 HANDOFF**

写入当前真实状态：

- 双平台实现和验证已完成；
- 目标版本 chinese `1.1.0`、sync `1.2.0`；
- 仍待 push 与本机 Codex 升级；
- 当前验证命令与风险；
- 不再声称工作树干净或本机 Claude 已升级。

- [ ] **Step 7: 确保验证脚本为 UTF-8 with BOM**

用 PowerShell 5.1 对脚本做编码归一化：

```powershell
$path = (Resolve-Path 'tests\validate-plugin.ps1').Path
$content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
[System.IO.File]::WriteAllText(
  $path,
  $content,
  (New-Object System.Text.UTF8Encoding($true))
)
```

Expected: 文件前三字节为 `EF BB BF`。

- [ ] **Step 8: 运行 docs 与全量静态测试**

```powershell
Invoke-NativeChecked 'docs 静态测试' {
  powershell -NoProfile -ExecutionPolicy Bypass `
    -File tests\validate-plugin.ps1 -Section docs
}
Invoke-NativeChecked '全量静态测试' {
  powershell -NoProfile -ExecutionPolicy Bypass `
    -File tests\validate-plugin.ps1 -Section all
}
```

Expected: 两次均 exit `0` and `全部通过`。

- [ ] **Step 9: 提交文档**

```powershell
Invoke-NativeChecked '暂存双平台文档' {
  git add -- .claude/settings.json CLAUDE.md AGENTS.md README.md HANDOFF.md `
    tests/validate-plugin.ps1
}
Assert-StagedFiles @(
  '.claude/settings.json'
  'CLAUDE.md'
  'AGENTS.md'
  'README.md'
  'HANDOFF.md'
  'tests/validate-plugin.ps1'
)
Invoke-NativeChecked '提交双平台文档' {
  git commit -m "docs: 补齐双平台安装与项目指引"
}
```

---

### Task 5: 全量验证与审查门槛

**Files:**
- Verify only: all files changed in Tasks 1–4

**Interfaces:**
- Consumes: 完整双平台发布候选。
- Produces: 可发布证据、已审查 diff、已知的 Claude 运行时验证边界。

- [ ] **Step 1: 运行全部仓库测试**

```powershell
Invoke-NativeChecked '全量仓库测试' {
  powershell -NoProfile -ExecutionPolicy Bypass `
    -File tests\validate-plugin.ps1 -Section all
}
```

Expected: exit `0`、无 FAIL、最终 `全部通过`。

- [ ] **Step 2: 运行两个 skill 的 Codex 校验**

```powershell
$env:PYTHONUTF8 = '1'
Invoke-NativeChecked 'chinese skill 校验' {
  python (Join-Path $env:USERPROFILE `
    '.codex\skills\.system\skill-creator\scripts\quick_validate.py') `
    plugins\chinese\codex\skills\init
}
Invoke-NativeChecked 'sync skill 校验' {
  python (Join-Path $env:USERPROFILE `
    '.codex\skills\.system\skill-creator\scripts\quick_validate.py') `
    plugins\sync\codex\skills\docs
}
```

Expected: 两次均 `Skill is valid!`。

- [ ] **Step 3: 运行两个 Codex plugin 校验**

```powershell
$env:PYTHONUTF8 = '1'
Invoke-NativeChecked 'chinese plugin 校验' {
  python (Join-Path $env:USERPROFILE `
    '.codex\skills\.system\plugin-creator\scripts\validate_plugin.py') `
    plugins\chinese\codex
}
Invoke-NativeChecked 'sync plugin 校验' {
  python (Join-Path $env:USERPROFILE `
    '.codex\skills\.system\plugin-creator\scripts\validate_plugin.py') `
    plugins\sync\codex
}
```

Expected: 两次均 exit `0` 且输出以 `Plugin validation passed:` 开头。

- [ ] **Step 4: 让 Codex CLI 解析临时 native marketplace**

先确认临时 marketplace 名未被占用，并克隆当前已提交候选：

```powershell
$marketplaces = (
  Invoke-NativeChecked '读取 Codex marketplaces' {
    codex plugin marketplace list --json
  }
) | ConvertFrom-Json
if ($marketplaces.marketplaces.name -contains 'my-skills-local-verify') {
  throw '临时 marketplace 名 my-skills-local-verify 已存在，先人工审计其来源'
}

$catalogProbeRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
  'my-skills-catalog-probe-codex'
if (Test-Path -LiteralPath $catalogProbeRoot) {
  throw "临时目录已存在，先人工审计后再处理：$catalogProbeRoot"
}
Invoke-NativeChecked '克隆发布候选用于 native catalog 校验' {
  git clone --no-hardlinks --quiet . $catalogProbeRoot
}
$catalogManifestPath = Join-Path $catalogProbeRoot `
  '.agents\plugins\marketplace.json'
$resolvedCatalogManifest = (
  Resolve-Path -LiteralPath $catalogManifestPath -ErrorAction Stop
).Path
Write-Host "临时 native manifest 绝对路径：$resolvedCatalogManifest"
```

复制上一段输出的 `临时 native manifest 绝对路径`，让 `apply_patch`
使用该**字面绝对路径**（不得写 `$catalogProbeRoot` 变量），只修改临时副本
`.agents/plugins/marketplace.json` 的顶层：

```text
"name": "my-skills-local-verify"
```

不得修改工作仓库，也不得用 PowerShell 写文件替代 `apply_patch`。然后执行：

```powershell
$catalogProbeRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
  'my-skills-catalog-probe-codex'
try {
  Invoke-NativeChecked '添加临时 native marketplace' {
    codex plugin marketplace add $catalogProbeRoot --json
  }

  $catalog = (
    Invoke-NativeChecked '列出临时 marketplace 插件' {
      codex plugin list --marketplace my-skills-local-verify --available --json
    }
  ) | ConvertFrom-Json
  $entries = @($catalog.installed) + @($catalog.available)
  foreach ($expected in @(
    @{ Id = 'chinese@my-skills-local-verify'; Version = '1.1.0'; Tail = 'plugins\chinese\codex' }
    @{ Id = 'sync@my-skills-local-verify'; Version = '1.2.0'; Tail = 'plugins\sync\codex' }
  )) {
    $entry = $entries | Where-Object { $_.pluginId -eq $expected.Id }
    if ($null -eq $entry -or
        $entry.version -ne $expected.Version -or
        -not $entry.source.path.EndsWith(
          $expected.Tail,
          [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "native catalog 条目不符合预期：$($expected.Id)"
    }
  }
} finally {
  try {
    $cleanupCatalog = (
      Invoke-NativeChecked '检查临时 marketplace 注册' {
        codex plugin marketplace list --json
      }
    ) | ConvertFrom-Json
    if ($cleanupCatalog.marketplaces.name -contains 'my-skills-local-verify') {
      Invoke-NativeChecked '移除临时 native marketplace' {
        codex plugin marketplace remove my-skills-local-verify --json
      }
    }
  } finally {
    if (Test-Path -LiteralPath $catalogProbeRoot) {
      $resolvedProbe = (Resolve-Path -LiteralPath $catalogProbeRoot).Path
      $tempPrefix = ([System.IO.Path]::GetFullPath(
        [System.IO.Path]::GetTempPath())).TrimEnd('\') + '\'
      if (-not $resolvedProbe.StartsWith(
          $tempPrefix,
          [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "拒绝清理不在系统临时目录内的路径：$resolvedProbe"
      }
      Remove-Item -LiteralPath $resolvedProbe -Recurse -Force `
        -ErrorAction Stop
      if (Test-Path -LiteralPath $resolvedProbe) {
        throw "临时 native catalog 目录清理失败：$resolvedProbe"
      }
    }
  }
}
```

Expected: Codex CLI 从 native catalog 解析出两个临时 pluginId、正确版本以及
以 `plugins\<name>\codex` 结尾的 source；临时 marketplace 注册和目录均被清理。

- [ ] **Step 5: 条件运行 Claude 官方 validator**

```powershell
if (Get-Command claude -ErrorAction SilentlyContinue) {
  Invoke-NativeChecked 'Claude plugin validate' {
    claude plugin validate .
  }
} else {
  Write-Host 'SKIP: 本机未安装 Claude CLI；未执行 Claude 运行时 validator'
}
```

Expected in this machine: explicit SKIP；不得写成 PASS。

- [ ] **Step 6: 检查编码、JSON 与 diff**

```powershell
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path 'tests\validate-plugin.ps1'))
if (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) {
  throw 'tests/validate-plugin.ps1 缺少 UTF-8 BOM'
}
Invoke-NativeChecked 'git diff --check' {
  git diff --check origin/main...HEAD
}
$dirty = @(
  Invoke-NativeChecked 'git status --porcelain' {
    git status --porcelain=v1 --untracked-files=all
  }
)
if ($dirty.Count -gt 0) {
  throw "发布候选工作树不干净：$($dirty -join '; ')"
}

$changed = @(
  Invoke-NativeChecked '读取发布候选文件清单' {
    git diff --name-only origin/main...HEAD
  }
) | Where-Object { $_ }
$allowedChanged = @(
  '.agents/plugins/marketplace.json'
  '.claude-plugin/marketplace.json'
  '.claude/settings.json'
  'AGENTS.md'
  'CLAUDE.md'
  'HANDOFF.md'
  'README.md'
  'docs/superpowers/plans/2026-07-23-claude-codex-dual-compat.md'
  'docs/superpowers/specs/2026-07-23-claude-codex-dual-compat-design.md'
  'docs/superpowers/verification/2026-07-23-claude-codex-skill-tests.md'
  'plugins/chinese/.claude-plugin/plugin.json'
  'plugins/chinese/codex/.codex-plugin/plugin.json'
  'plugins/chinese/codex/skills/init/SKILL.md'
  'plugins/chinese/codex/skills/init/agents/openai.yaml'
  'plugins/chinese/skills/init/SKILL.md'
  'plugins/sync/.claude-plugin/plugin.json'
  'plugins/sync/codex/.codex-plugin/plugin.json'
  'plugins/sync/codex/skills/docs/SKILL.md'
  'plugins/sync/codex/skills/docs/agents/openai.yaml'
  'plugins/sync/skills/docs/SKILL.md'
  'tests/validate-plugin.ps1'
)
$unexpectedChanged = @($changed | Where-Object { $_ -notin $allowedChanged })
if ($unexpectedChanged.Count -gt 0) {
  throw "发布候选含计划外文件：$($unexpectedChanged -join ', ')"
}
Invoke-NativeChecked 'git diff --stat' {
  git diff --stat origin/main...HEAD
}
```

Expected:

- BOM 检查不抛错；
- `git diff --check` 无输出；
- 工作树无未提交文件；
- diff 只覆盖本计划列出的文件和设计/计划文档提交。

- [ ] **Step 7: 请求两阶段代码审查**

使用 `superpowers:requesting-code-review`：

1. 先审查是否完整满足 spec，特别是调用语法、宿主分支、版本、发布结构与用户 dirty work。
2. 再审查 skill 文案质量、测试有效性、PowerShell 兼容性与发布风险。

任何问题先写失败测试或复现场景，再修复、复跑 Tasks 2–5 的相关门槛。

- [ ] **Step 8: 闭环提交审查修复**

若 Step 7 产生任何修改：

1. 从 `git status --short` 读取实际修改文件，确认全部属于上面
   `$allowedChanged`；计划外文件立即停止。
2. 用精确 pathspec 暂存实际修复文件，禁止 `git add .`。
3. 以这些实际路径调用 `Assert-StagedFiles`，确认没有旧 staged 文件搭车。
4. 使用中文提交信息 `fix: 修复双平台兼容审查问题`。
5. 从 Step 1 开始复跑 Task 5 全部门槛，直到审查无剩余问题且工作树干净。

若审查没有产生修改，明确记录“无需修复提交”，不要创建空提交。

- [ ] **Step 9: 记录发布候选提交**

```powershell
Invoke-NativeChecked '读取发布候选提交' {
  git log --oneline --decorate origin/main..HEAD
}
```

Expected: 只包含设计、计划、发布结构、chinese、sync 和双平台文档提交。

---

### Task 6: 发布、本机 Codex 升级与最终交接

**Files:**
- Modify after successful upgrade: `HANDOFF.md`

**Interfaces:**
- Consumes: 已验证的 main 提交序列。
- Produces: `origin/main` 已发布、本机 marketplace 与两个插件已升级、HANDOFF 记录真实结果。

- [ ] **Step 1: push 前远程闸门**

```powershell
Invoke-NativeChecked '检查 gh CLI' {
  gh --version
}
Invoke-NativeChecked '检查 GitHub 登录' {
  gh auth status
}
Invoke-NativeChecked 'git fetch origin' {
  git fetch origin
}
$dirty = @(
  Invoke-NativeChecked 'push 前检查工作树' {
    git status --porcelain=v1 --untracked-files=all
  }
)
if ($dirty.Count -gt 0) {
  throw "push 前工作树不干净：$($dirty -join '; ')"
}
Invoke-NativeChecked '确认 origin/main 是 HEAD 祖先' {
  git merge-base --is-ancestor origin/main HEAD
}
$candidateCommits = @(
  Invoke-NativeChecked '读取待发布提交' {
    git log --oneline origin/main..HEAD
  }
)
if ($candidateCommits.Count -eq 0) {
  throw '没有待发布提交'
}
$candidateCommits | Write-Host
```

Expected:

- 工作树干净；
- `gh` 可用且 GitHub 登录有效；
- `git merge-base --is-ancestor` exit `0`；
- 本地只领先预期提交；
- 若远程前进，停止并重新审计，禁止强推。

`github:yeet` 默认使用分支和 draft PR；本仓库已在获确认设计中明确沿用
直接向 `main` 发布，因此本次不另建分支或 PR，但继续执行其精确 scope、
认证、校验和 push 安全门槛。

- [ ] **Step 2: 发布实现**

```powershell
Invoke-NativeChecked '发布实现到 origin/main' {
  git push origin main
}
$localHead = (
  Invoke-NativeChecked '读取本地 HEAD' { git rev-parse HEAD }
).Trim()
$remoteHead = (
  Invoke-NativeChecked '读取 origin/main' { git rev-parse origin/main }
).Trim()
if ($localHead -ne $remoteHead) {
  throw "push 后 HEAD 与 origin/main 不一致：$localHead / $remoteHead"
}
```

Expected: exit `0`，远端 main 更新到当前 HEAD。

- [ ] **Step 3: 刷新本机 marketplace**

```powershell
$upgradeResult = Invoke-NativeChecked '刷新本机 my-skills marketplace' {
  codex plugin marketplace upgrade my-skills --json
}
$upgradeResult | Write-Host
```

Expected: JSON 表示 `my-skills` 刷新成功，revision 为刚发布的提交或其后续 fast-forward 提交。

- [ ] **Step 4: 重新安装两个插件**

```powershell
$chineseInstall = Invoke-NativeChecked '安装 chinese@my-skills' {
  codex plugin add chinese@my-skills --json
}
$syncInstall = Invoke-NativeChecked '安装 sync@my-skills' {
  codex plugin add sync@my-skills --json
}
$chineseInstall | Write-Host
$syncInstall | Write-Host
```

Expected:

- chinese 安装版本 `1.1.0`；
- sync 安装版本 `1.2.0`；
- 两次命令均 exit `0`。

- [ ] **Step 5: 核对安装状态与缓存内容**

```powershell
$pluginList = (
  Invoke-NativeChecked '读取本机 Codex 插件状态' {
    codex plugin list --json
  }
) | ConvertFrom-Json

foreach ($expected in @(
  @{ Id = 'chinese@my-skills'; Version = '1.1.0'; Tail = 'plugins\chinese\codex' }
  @{ Id = 'sync@my-skills'; Version = '1.2.0'; Tail = 'plugins\sync\codex' }
)) {
  $entry = $pluginList.installed |
    Where-Object { $_.pluginId -eq $expected.Id }
  if ($null -eq $entry -or
      $entry.version -ne $expected.Version -or
      -not $entry.installed -or
      -not $entry.enabled -or
      -not $entry.source.path.EndsWith(
        $expected.Tail,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "插件状态或 native source 不符合预期：$($expected.Id)"
  }
}

$snapshotRoot = Join-Path $env:USERPROFILE `
  '.codex\.tmp\marketplaces\my-skills'
$nativeCatalogPath = Join-Path $snapshotRoot '.agents\plugins\marketplace.json'
$installReceiptPath = Join-Path $snapshotRoot '.codex-marketplace-install.json'
$nativeCatalog = Get-Content -LiteralPath $nativeCatalogPath -Raw -Encoding UTF8 |
  ConvertFrom-Json
if (($nativeCatalog.plugins |
     Where-Object { $_.name -eq 'chinese' }).source.path -ne
      './plugins/chinese/codex' -or
    ($nativeCatalog.plugins |
     Where-Object { $_.name -eq 'sync' }).source.path -ne
      './plugins/sync/codex') {
  throw '本机 snapshot 未使用预期的 native codex/ source'
}

$receipt = Get-Content -LiteralPath $installReceiptPath -Raw -Encoding UTF8 |
  ConvertFrom-Json
$publishedSha = (
  Invoke-NativeChecked '读取已发布实现 SHA' { git rev-parse HEAD }
).Trim()
if ($receipt.revision -ne $publishedSha) {
  throw "marketplace revision 与已发布实现不一致：$($receipt.revision) / $publishedSha"
}

$chineseManifest = Join-Path $env:USERPROFILE `
  '.codex\plugins\cache\my-skills\chinese\1.1.0\.codex-plugin\plugin.json'
$syncManifest = Join-Path $env:USERPROFILE `
  '.codex\plugins\cache\my-skills\sync\1.2.0\.codex-plugin\plugin.json'
$chineseSkill = Join-Path $env:USERPROFILE `
  '.codex\plugins\cache\my-skills\chinese\1.1.0\skills\init\SKILL.md'
$syncSkill = Join-Path $env:USERPROFILE `
  '.codex\plugins\cache\my-skills\sync\1.2.0\skills\docs\SKILL.md'
foreach ($path in @($chineseManifest, $syncManifest, $chineseSkill, $syncSkill)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "本机插件缓存缺少：$path"
  }
}
if (-not (Select-String -LiteralPath $chineseSkill -Pattern '\$chinese:init' -Quiet) -or
    -not (Select-String -LiteralPath $syncSkill -Pattern '\$sync:docs' -Quiet)) {
  throw '本机插件缓存缺少新版显式调用契约'
}
```

Expected: 两个插件均 `installed, enabled`、版本正确、source 以各自
`plugins\<name>\codex` 结尾；native catalog、revision、cache manifest 与
新版 skill 内容全部通过程序化断言。

- [ ] **Step 6: 用新的 Codex 进程做本机运行时 smoke**

在系统临时目录创建两个互相隔离的 Git 仓库；使用 `--ephemeral` 保证测试任务
不持久化，并让每个新进程重新发现已升级的插件：

```powershell
$smokeRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
  ("my-skills-smoke-" + [Guid]::NewGuid().ToString('N'))
$chineseSmoke = Join-Path $smokeRoot 'chinese'
$syncSmoke = Join-Path $smokeRoot 'sync'
$null = New-Item -ItemType Directory -Path $chineseSmoke, $syncSmoke

foreach ($repo in @($chineseSmoke, $syncSmoke)) {
  try {
    Invoke-NativeChecked "git init $repo" {
      git -C $repo init --quiet
    }
  } catch {
    throw "$($_.Exception.Message)，临时目录保留在 $smokeRoot"
  }
}

$chineseOutput = @(
  Invoke-NativeChecked 'chinese Codex smoke' {
    codex exec --ephemeral --sandbox workspace-write `
      --cd $chineseSmoke '$chinese:init' 2>&1
  }
)
$chineseRepeatOutput = @(
  Invoke-NativeChecked 'chinese Codex smoke 重复调用' {
    codex exec --ephemeral --sandbox workspace-write `
      --cd $chineseSmoke '$chinese:init' 2>&1
  }
)

$syncOutput = @(
  Invoke-NativeChecked 'sync Codex smoke' {
    codex exec --ephemeral --sandbox workspace-write `
      --cd $syncSmoke '$sync:docs' 2>&1
  }
)
$syncRepeatOutput = @(
  Invoke-NativeChecked 'sync Codex smoke 重复调用' {
    codex exec --ephemeral --sandbox workspace-write `
      --cd $syncSmoke '$sync:docs' 2>&1
  }
)

if ($chineseOutput.Count -eq 0 -or
    $chineseRepeatOutput.Count -eq 0 -or
    $syncOutput.Count -eq 0 -or
    $syncRepeatOutput.Count -eq 0) {
  throw "Codex smoke 缺少运行输出，临时目录保留在 $smokeRoot"
}

$chineseAgents = Join-Path $chineseSmoke 'AGENTS.md'
$syncAgents = Join-Path $syncSmoke 'AGENTS.md'
$syncHandoff = Join-Path $syncSmoke 'HANDOFF.md'

$chineseAgentsContent = if (Test-Path -LiteralPath $chineseAgents) {
  Get-Content -LiteralPath $chineseAgents -Raw -Encoding UTF8
}
if (-not (Test-Path -LiteralPath $chineseAgents) -or
    ([regex]::Matches(
      $chineseAgentsContent,
      '<!-- chinese:init start -->')).Count -ne 1 -or
    (Test-Path -LiteralPath (Join-Path $chineseSmoke 'CLAUDE.md')) -or
    (Test-Path -LiteralPath (Join-Path $chineseSmoke '.claude'))) {
  throw "chinese 文件行为不符合契约，临时目录保留在 $smokeRoot"
}

$syncAgentsContent = if (Test-Path -LiteralPath $syncAgents) {
  Get-Content -LiteralPath $syncAgents -Raw -Encoding UTF8
}
if (-not (Test-Path -LiteralPath $syncAgents) -or
    -not (Test-Path -LiteralPath $syncHandoff) -or
    ([regex]::Matches(
      $syncAgentsContent,
      '<!-- sync:docs start -->')).Count -ne 1 -or
    (Test-Path -LiteralPath (Join-Path $syncSmoke 'CLAUDE.md'))) {
  throw "sync 文件行为不符合契约，临时目录保留在 $smokeRoot"
}

$resolvedSmoke = (Resolve-Path -LiteralPath $smokeRoot).Path
$tempPrefix = ([System.IO.Path]::GetFullPath(
  [System.IO.Path]::GetTempPath())).TrimEnd('\') + '\'
if (-not $resolvedSmoke.StartsWith(
    $tempPrefix,
    [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "拒绝清理不在系统临时目录内的路径：$resolvedSmoke"
}
Remove-Item -LiteralPath $resolvedSmoke -Recurse -Force -ErrorAction Stop
if (Test-Path -LiteralPath $resolvedSmoke) {
  throw "运行时 smoke 临时目录清理失败：$resolvedSmoke"
}
```

Expected:

- 四次 `codex exec`（每个 skill 两次）均 exit `0`，且确实由新进程发现
  `$chinese:init`、`$sync:docs`；
- chinese 临时仓库只产生 Codex 侧 `AGENTS.md` 中文哨兵，不产生 Claude 文件；
- sync 临时仓库产生 `HANDOFF.md` 与唯一一份 AGENTS 续接哨兵，不产生
  `CLAUDE.md`；
- 全部断言通过后才清理经绝对路径校验的临时目录；失败时保留现场供诊断。

- [ ] **Step 7: 更新最终 HANDOFF**

将 HANDOFF 从“待发布/待升级”改为实际结果：

- 记录发布提交 SHA；
- 记录 marketplace upgrade 成功；
- 记录本机 chinese `1.1.0`、sync `1.2.0`；
- 记录两个新 `codex exec --ephemeral` 运行时 smoke 的实际结果；
- 明确 Claude CLI 未安装、Claude 运行时 smoke 未执行；
- 若两项 Codex smoke 已通过，不再把“新任务实际调用”列为未完成项。

- [ ] **Step 8: 提交并发布最终交接**

```powershell
Invoke-NativeChecked '暂存最终 HANDOFF' {
  git add -- HANDOFF.md
}
Assert-StagedFiles @('HANDOFF.md')
Invoke-NativeChecked '提交最终 HANDOFF' {
  git commit -m "docs: 记录双平台发布与本机升级结果"
}
Invoke-NativeChecked '发布最终 HANDOFF' {
  git push origin main
}
$finalUpgrade = Invoke-NativeChecked '刷新最终 marketplace revision' {
  codex plugin marketplace upgrade my-skills --json
}
$finalUpgrade | Write-Host
```

Expected: 四条命令全部成功；最后一次 marketplace revision 等于最终 HANDOFF 提交。

- [ ] **Step 9: 最终验证**

```powershell
$finalDirty = @(
  Invoke-NativeChecked '最终工作树检查' {
    git status --porcelain=v1 --untracked-files=all
  }
)
if ($finalDirty.Count -gt 0) {
  throw "最终工作树不干净：$($finalDirty -join '; ')"
}
$finalHead = (
  Invoke-NativeChecked '读取最终 HEAD' { git rev-parse HEAD }
).Trim()
$finalOrigin = (
  Invoke-NativeChecked '读取最终 origin/main' { git rev-parse origin/main }
).Trim()
if ($finalHead -ne $finalOrigin) {
  throw "最终 HEAD 与 origin/main 不一致：$finalHead / $finalOrigin"
}

$finalReceiptPath = Join-Path $env:USERPROFILE `
  '.codex\.tmp\marketplaces\my-skills\.codex-marketplace-install.json'
$finalReceipt = Get-Content -LiteralPath $finalReceiptPath `
  -Raw -Encoding UTF8 | ConvertFrom-Json
if ($finalReceipt.revision -ne $finalHead) {
  throw "最终 marketplace revision 与 HEAD 不一致：$($finalReceipt.revision) / $finalHead"
}

$finalPlugins = (
  Invoke-NativeChecked '最终插件状态检查' {
    codex plugin list --json
  }
) | ConvertFrom-Json
foreach ($expected in @(
  @{ Id = 'chinese@my-skills'; Version = '1.1.0' }
  @{ Id = 'sync@my-skills'; Version = '1.2.0' }
)) {
  $entry = $finalPlugins.installed |
    Where-Object { $_.pluginId -eq $expected.Id }
  if ($null -eq $entry -or
      $entry.version -ne $expected.Version -or
      -not $entry.installed -or
      -not $entry.enabled) {
    throw "最终插件状态不符合预期：$($expected.Id)"
  }
}
```

Expected:

- 工作树干净；
- HEAD 等于 `origin/main`；
- 两个插件仍 installed/enabled，版本分别为 `1.1.0` 和 `1.2.0`。

- [ ] **Step 10: 用户交接**

最终回复必须说明：

- 同一 Git 仓库已同时发布 Claude/Codex marketplace；
- Claude 调用 `/chinese:init`、`/sync:docs`；
- Codex 调用 `$chinese:init`、`$sync:docs`；
- 本机 Codex 已升级；
- 新进程 Codex runtime smoke 的实际结果；
- 当前已打开的旧任务不会热加载新版 skill，日常使用需新开 Codex 任务；
- Claude 本机 runtime 未验证，不把静态兼容描述成已实机 smoke 通过。
