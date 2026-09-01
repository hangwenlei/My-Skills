# sync 2.0 分层交接实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `sync` 插件从 1.2.0 升级到 2.0.0，将单文件 `HANDOFF.md` 拆为稳定层、分支现场与协同看板三层，取消两阶段确认，并引入三级信息淘汰机制。

**Architecture:** 本插件的「实现」主体是自然语言 `SKILL.md` 指令文本，唯一的可执行代码是 PowerShell 测试脚本。因此采用「测试先行定义契约」的方式：先用 `tests/gc-scenarios.ps1` 锁定设计所依赖的 git 行为与两个算法的参考实现，再用 `tests/validate-plugin.ps1` 的新断言定义 2.0 的文本契约，最后逐块改写 `SKILL.md` 使断言转绿。

**Tech Stack:** Markdown（SKILL.md 指令）、JSON（插件与市场清单）、Windows PowerShell 5.1（测试）、git 2.31+

**设计依据:** `docs/superpowers/specs/2026-09-01-sync-v2-layered-handoff-design.md`

## Global Constraints

以下约束适用于每一个任务，不再逐条重复。

- **语言**：全部输出与文档使用简体中文；代码、命令、文件路径、API 名称保持英文；代码注释使用中文；Git 提交信息使用中文。
- **测试脚本编码**：`tests/*.ps1` 必须保存为 **UTF-8 with BOM**，否则 Windows PowerShell 5.1 解析中文会乱码。
- **文档可移植性**：`docs/` 下的计划与验证文档**不得包含**任何形如 `X:\Users\` 或 `X:/Users/` 的机器用户路径，也不得包含机器用户名数字片段。`tests/validate-plugin.ps1` 的 `docs` section 会强制检查。测试脚本一律使用 `$env:TEMP`。
- **PowerShell 5.1 兼容**：禁止使用 `&&`、`||`、三元运算符、`??`、`?.`；禁止对原生 exe 使用 `2>&1`；多行字符串使用 here-string 且结束符 `'@` 顶格。
- **主干探测**：禁止使用 `git config init.defaultBranch` 判定主干分支（实测其值为 `master` 而真实主干为 `main`）。
- **文件名哈希**：一律对**完整分支名的 UTF-8 字节**做 SHA-1，取前 6 位十六进制小写，不得依赖平台默认编码。
- **时间判据**：一律取文件内记录的 ISO 8601 时间戳，**禁止使用文件 mtime**。
- **skill 行为边界**：`sync` 永不执行 `git commit`；敏感信息闸门（默认只读安全元数据、raw 证据须同一本地调用内脱敏、失败时 fail closed）完整保留。
- **版本**：`sync` 两处 `plugin.json` 的 `version` 同步为 `2.0.0`；`chinese` 不动。

## 文件结构

| 文件 | 动作 | 职责 |
|---|---|---|
| `tests/gc-scenarios.ps1` | 创建 | 多 worktree 场景搭建、9 条 git 行为契约断言、两个算法参考实现 |
| `tests/validate-plugin.ps1` | 修改 | 移除被 2.0 打破的旧断言，新增 2.0 文本契约断言 |
| `plugins/sync/codex/skills/docs/SKILL.md` | 修改 | 共享核心，2.0 全部业务指令（主体工作量） |
| `plugins/sync/skills/docs/SKILL.md` | 修改 | Claude 薄入口，同步参数说明 |
| `plugins/sync/.claude-plugin/plugin.json` | 修改 | 版本与描述 |
| `plugins/sync/codex/.codex-plugin/plugin.json` | 修改 | 版本与描述 |
| `plugins/sync/codex/skills/docs/agents/openai.yaml` | 修改 | 去掉「确认式流程」措辞 |
| `.claude-plugin/marketplace.json` | 修改 | sync 条目描述 |
| `README.md` | 修改 | sync 章节：三层布局、GC、老项目迁移 |

`.agents/plugins/marketplace.json` 的 sync 条目无 `description` 字段，无需修改。

---

### Task 1: GC 场景搭建与 git 行为契约断言

**Files:**
- Create: `tests/gc-scenarios.ps1`

**Interfaces:**
- Consumes: 无
- Produces: `New-GcScenario`（返回含 `Root`/`Repo`/`WtA`/`WtB` 四个字符串属性的对象）、`Remove-GcScenario($scenario)`、`Add-BranchHandoff -WorkTree <path> -FileName <name> -Message <msg>`、`Check($cond, $msg)`、`Should-Run($name)`。Task 2 直接复用这些函数。

- [ ] **Step 1: 创建脚本骨架与场景工厂**

创建 `tests/gc-scenarios.ps1`，**保存为 UTF-8 with BOM**：

```powershell
param(
  [ValidateSet('all', 'env', 'algo')]
  [string]$Section = 'all'
)

# 原生 git 的非零退出码不应中断脚本，主干探测依赖 $LASTEXITCODE 判定
$ErrorActionPreference = 'Continue'
$script:fail = 0

function Check($cond, $msg) {
  if ($cond) {
    Write-Host "PASS: $msg"
  } else {
    Write-Host "FAIL: $msg"
    $script:fail++
  }
}

function Should-Run($name) {
  return $Section -eq 'all' -or $Section -eq $name
}

function ConvertTo-ComparablePath($path) {
  # git 在 Windows 输出正斜杠，PowerShell 拼接出反斜杠，比较前必须归一
  return ($path -replace '\\', '/').TrimEnd('/')
}

function New-GcScenario {
  $root = Join-Path $env:TEMP ('sync-gc-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  $repo = Join-Path $root 'repo'
  New-Item -ItemType Directory -Path $repo -Force | Out-Null
  & git init -q $repo
  # 不用 git init -b，兼容 2.28 以前的版本
  & git -C $repo symbolic-ref HEAD refs/heads/main
  & git -C $repo config user.email 'test@example.com'
  & git -C $repo config user.name 'sync-test'
  # 故意制造 T5 陷阱：配置值与真实主干不一致
  & git -C $repo config init.defaultBranch 'master'
  Set-Content -LiteralPath (Join-Path $repo 'HANDOFF.md') -Value '# stable' -Encoding utf8
  & git -C $repo add -A
  & git -C $repo commit -q -m 'init'
  foreach ($b in @('feat-a', 'feat-b', 'feat-c')) {
    & git -C $repo branch $b
  }
  $wtA = Join-Path $root 'wt-a'
  $wtB = Join-Path $root 'wt-b'
  & git -C $repo worktree add -q $wtA 'feat-a'
  & git -C $repo worktree add -q $wtB 'feat-b'
  return [pscustomobject]@{ Root = $root; Repo = $repo; WtA = $wtA; WtB = $wtB }
}

function Add-BranchHandoff {
  param($WorkTree, [string]$FileName, [string]$Message)
  $dir = Join-Path $WorkTree '.handoff'
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $dir $FileName) -Value $Message -Encoding utf8
  & git -C $WorkTree add -A
  & git -C $WorkTree commit -q -m $Message
}

function Remove-GcScenario($scenario) {
  if ($null -eq $scenario) { return }
  $repoKey = ConvertTo-ComparablePath $scenario.Repo
  foreach ($line in @(& git -C $scenario.Repo worktree list --porcelain)) {
    if ($line -match '^worktree\s+(.+)$') {
      $path = $Matches[1]
      if ((ConvertTo-ComparablePath $path) -ne $repoKey) {
        & git -C $scenario.Repo worktree remove $path --force
      }
    }
  }
  Remove-Item -LiteralPath $scenario.Root -Recurse -Force -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: 运行骨架，确认场景可搭建可清理**

在脚本末尾临时追加：

```powershell
$probe = New-GcScenario
Write-Host ("场景根: " + (Test-Path -LiteralPath $probe.Root))
Remove-GcScenario $probe
Write-Host ("已清理: " + (-not (Test-Path -LiteralPath $probe.Root)))
```

Run:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/gc-scenarios.ps1
```

Expected: 输出 `场景根: True` 与 `已清理: True`。确认后删除这段临时代码。

- [ ] **Step 3: 写入 env section 的 7 条契约断言**

在 `Remove-GcScenario` 函数之后追加：

```powershell
if (Should-Run 'env') {
  $scenario = $null
  try {
    $scenario = New-GcScenario

    $topA = & git -C $scenario.WtA rev-parse --show-toplevel
    $topB = & git -C $scenario.WtB rev-parse --show-toplevel
    Check ((ConvertTo-ComparablePath $topA) -ne (ConvertTo-ComparablePath $topB)) `
      'T1 各 worktree 的 --show-toplevel 互不相同'

    $commonA = & git -C $scenario.WtA rev-parse --path-format=absolute --git-common-dir
    $commonB = & git -C $scenario.WtB rev-parse --path-format=absolute --git-common-dir
    Check ((ConvertTo-ComparablePath $commonA) -eq (ConvertTo-ComparablePath $commonB)) `
      'T2 各 worktree 的 --git-common-dir 指向同一路径'

    $linesDir = Join-Path $commonA 'sync/lines'
    New-Item -ItemType Directory -Path $linesDir -Force | Out-Null
    $probeFile = Join-Path $linesDir 'probe.md'
    Set-Content -LiteralPath $probeFile -Value 'probe' -Encoding utf8
    & git -C $scenario.Repo gc -q --prune=now
    Check (Test-Path -LiteralPath $probeFile) `
      'T3 git gc --prune=now 后看板文件仍存在'
    $statusText = (@(& git -C $scenario.Repo status --short) -join '')
    Check ([string]::IsNullOrWhiteSpace($statusText)) `
      'T3 git status 不报告 common dir 下的看板文件'

    Add-BranchHandoff -WorkTree $scenario.WtA -FileName 'feat-a.md' -Message 'handoff-a'
    Add-BranchHandoff -WorkTree $scenario.WtB -FileName 'feat-b.md' -Message 'handoff-b'
    & git -C $scenario.Repo merge -q --no-ff feat-a -m 'merge feat-a'

    $merged = @(& git -C $scenario.WtB branch --merged main --format='%(refname:short)')
    Check ($merged -contains 'feat-a') `
      'T4 非主干 worktree 中 branch --merged 识别已合并分支'
    Check (-not ($merged -contains 'feat-b')) `
      'T4 未合并分支不被 branch --merged 误判'

    $mainTree = (@(& git -C $scenario.Repo ls-tree -r --name-only main -- .handoff/) -join "`n")
    Check ($mainTree -match 'feat-a\.md') `
      'T6 已合并分支的现场文件留在主干（孤儿来源）'
    Check ($mainTree -notmatch 'feat-b\.md') `
      'T6 未合并分支的现场文件不在主干'

    $emptyDir = Join-Path $scenario.Repo '.handoff-empty'
    New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
    & git -C $scenario.Repo add -A
    $wtC = Join-Path $scenario.Root 'wt-c'
    & git -C $scenario.Repo worktree add -q $wtC 'feat-c'
    Check (-not (Test-Path -LiteralPath (Join-Path $wtC '.handoff-empty'))) `
      'T9 空目录不进 Git，新 worktree 中不存在'

    $singleFile = Join-Path $scenario.Root 'single.md'
    $writeBlock = {
      param($path, $text)
      Set-Content -LiteralPath $path -Value $text -Encoding utf8
    }
    $jobs = @(
      (Start-Job -ScriptBlock $writeBlock -ArgumentList $singleFile, 'LINE-A'),
      (Start-Job -ScriptBlock $writeBlock -ArgumentList $singleFile, 'LINE-B')
    )
    Wait-Job -Job $jobs | Out-Null
    Remove-Job -Job $jobs
    $singleText = Get-Content -LiteralPath $singleFile -Raw
    Check (-not (($singleText -match 'LINE-A') -and ($singleText -match 'LINE-B'))) `
      'T8 单文件并发写必然丢失一方（故看板禁止单文件）'

    $splitDir = Join-Path $scenario.Root 'lines'
    New-Item -ItemType Directory -Path $splitDir -Force | Out-Null
    $splitA = Join-Path $splitDir 'a.md'
    $splitB = Join-Path $splitDir 'b.md'
    $splitJobs = @(
      (Start-Job -ScriptBlock $writeBlock -ArgumentList $splitA, 'LINE-A'),
      (Start-Job -ScriptBlock $writeBlock -ArgumentList $splitB, 'LINE-B')
    )
    Wait-Job -Job $splitJobs | Out-Null
    Remove-Job -Job $splitJobs
    Check (((Get-Content -LiteralPath $splitA -Raw) -match 'LINE-A') -and
           ((Get-Content -LiteralPath $splitB -Raw) -match 'LINE-B')) `
      'T8 分文件并发写两方均无丢失'
  } finally {
    Remove-GcScenario $scenario
  }
}

if ($script:fail -gt 0) {
  Write-Host "`n$script:fail 项失败"
  exit 1
}

Write-Host "`n全部通过"
exit 0
```

- [ ] **Step 4: 运行并确认 9 条断言全部通过**

Run:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/gc-scenarios.ps1 -Section env
```

Expected: 9 行 `PASS:`，末尾 `全部通过`，退出码 0。若 `--path-format=absolute` 报错，说明 git 低于 2.31，升级 git 后重跑。

- [ ] **Step 5: 确认临时目录已清理干净**

Run:

```bash
powershell -NoProfile -Command "Get-ChildItem -Path $env:TEMP -Filter 'sync-gc-*' -Directory | Measure-Object | Select-Object -ExpandProperty Count"
```

Expected: `0`

- [ ] **Step 6: 提交**

```bash
git add tests/gc-scenarios.ps1
git commit -m "test: 新增 sync 2.0 的 git 行为契约回归测试"
```

---

### Task 2: 主干探测与文件名生成的参考实现

**Files:**
- Modify: `tests/gc-scenarios.ps1`

**Interfaces:**
- Consumes: Task 1 的 `New-GcScenario`、`Remove-GcScenario`、`Check`、`Should-Run`
- Produces: `Resolve-MainBranch -Repo <path>` 返回主干分支名字符串或 `$null`；`Get-BranchFileName -BranchName <string>` 返回形如 `feat-auth-3a9c55.md` 的文件名。这两个函数是 `SKILL.md` 中同名算法的可执行对照物，Task 4 的指令文本必须与之一致。

- [ ] **Step 1: 先写会失败的测试**

在 `Should-Run 'env'` 区块之后、退出统计之前插入：

```powershell
if (Should-Run 'algo') {
  Check ((Get-BranchFileName 'feat/auth') -eq 'feat-auth-3a9c55.md') `
    'T7 feat/auth 生成带哈希后缀的文件名'
  Check ((Get-BranchFileName 'feat-auth') -eq 'feat-auth-f42474.md') `
    'T7 feat-auth 生成不同的哈希后缀'
  Check ((Get-BranchFileName 'feat/auth') -ne (Get-BranchFileName 'feat-auth')) `
    'T7 slug 碰撞被哈希后缀消除'
  Check ((Get-BranchFileName '功能/登录') -eq '功能-登录-9ff12b.md') `
    'T7 中文分支名按 UTF-8 字节哈希，跨工具一致'

  $algoScenario = $null
  try {
    $algoScenario = New-GcScenario
    $resolved = Resolve-MainBranch -Repo $algoScenario.Repo
    Check ($resolved -eq 'main') `
      'T5 主干探测忽略 init.defaultBranch，返回真实主干 main'
  } finally {
    Remove-GcScenario $algoScenario
  }
}
```

期望值来源：`printf 'feat/auth' | sha1sum` 得 `3a9c55`，`feat-auth` 得 `f42474`，`功能/登录` 得 `9ff12b`。这三个向量同时校验哈希算法与 UTF-8 编码。

- [ ] **Step 2: 运行测试，确认失败**

Run:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/gc-scenarios.ps1 -Section algo
```

Expected: 报错 `The term 'Get-BranchFileName' is not recognized`（函数尚未定义）。

- [ ] **Step 3: 实现两个函数**

在 `ConvertTo-ComparablePath` 之后插入：

```powershell
function Get-BranchFileName {
  param([string]$BranchName)
  # Windows 非法文件名字符统一替换为连字符
  $slug = $BranchName -replace '[\\/:*?"<>|]', '-'
  # 必须显式 UTF-8，否则含中文的分支名在不同宿主下哈希不一致
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($BranchName)
  $sha1 = [System.Security.Cryptography.SHA1]::Create()
  try {
    $hashBytes = $sha1.ComputeHash($bytes)
  } finally {
    $sha1.Dispose()
  }
  $hash = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
  return ('{0}-{1}.md' -f $slug, $hash.Substring(0, 6))
}

function Resolve-MainBranch {
  param([string]$Repo)
  # 1. 远端 HEAD 指向
  $originHead = & git -C $Repo symbolic-ref --quiet refs/remotes/origin/HEAD
  if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($originHead)) {
    return ($originHead -replace '^refs/remotes/origin/', '')
  }
  # 2. 远端候选分支
  foreach ($candidate in @('main', 'master')) {
    & git -C $Repo rev-parse --verify --quiet "refs/remotes/origin/$candidate" | Out-Null
    if ($LASTEXITCODE -eq 0) { return $candidate }
  }
  # 3. 本地候选分支
  foreach ($candidate in @('main', 'master')) {
    & git -C $Repo rev-parse --verify --quiet "refs/heads/$candidate" | Out-Null
    if ($LASTEXITCODE -eq 0) { return $candidate }
  }
  # 4. 不可得，调用方须跳过 merged 判据
  return $null
}
```

**注意**：绝不读取 `git config init.defaultBranch`。场景仓库刻意把它设为 `master` 而真实主干为 `main`，就是为了让任何走捷径的实现在这一步失败。

- [ ] **Step 4: 运行测试，确认通过**

Run:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/gc-scenarios.ps1 -Section algo
```

Expected: 5 行 `PASS:`，末尾 `全部通过`。

- [ ] **Step 5: 运行全量，确认两个 section 都绿**

Run:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/gc-scenarios.ps1
```

Expected: 14 行 `PASS:`，`全部通过`，退出码 0。

- [ ] **Step 6: 提交**

```bash
git add tests/gc-scenarios.ps1
git commit -m "test: 新增主干探测与分支文件名生成的参考实现"
```

---

### Task 3: 用断言定义 2.0 文本契约

**Files:**
- Modify: `tests/validate-plugin.ps1`（`sync` section 位于第 208 行起，`docs` section 位于第 327 行起）

**Interfaces:**
- Consumes: 现有 `Check`、`Remove-Whitespace`、`Should-Run`、`Read-JsonUtf8`
- Produces: 定义 2.0 契约的断言集合。Task 4–7 的目标就是让这些断言全部转绿。

- [ ] **Step 1: 新增对 markdown 标记鲁棒的归一化函数**

`Remove-Whitespace` 只删空白，不删反引号和 `**`。新断言要匹配的文本里两者都有，
必须先加一个更强的归一化函数。在 `Remove-Whitespace` 定义之后追加：

```powershell
function Remove-Markup($text) {
  # 同时去掉空白、markdown 强调符与反引号；保留下划线，它出现在标识符里
  return ($text -replace '[\s*`]', '')
}
```

- [ ] **Step 2: 移除被 2.0 打破的 4 条旧断言**

按内容定位并整块删除下列四处。

1. 二阶段入口已取消（`sync` section 内）：
```powershell
    Check ($content -match '\$sync:docs 应用 1,3') 'sync 定义 Codex 二阶段入口'
```

2. 措辞含「应用确认项」，流程已变——删除完整的三行语句：
```powershell
    Check ($normalized.Contains(
      'Git项目在应用确认项后先读取相关安全diff元数据；只有在敏感信息闸门内完成本地过滤后，才能读取脱敏正文。')) `
      'sync Git 项目确认后也遵守证据读取闸门'
```

3. 反向断言引用已废弃措辞——删除完整的两行语句：
```powershell
    Check ($content -notmatch '(?m)^- 完成确认项后.*`git diff`') `
      'sync 不在完成确认项后直接读取 raw git diff'
```
若该消息行文字与此处不完全一致，以文件中 `-notmatch '(?m)^- 完成确认项后` 所在
语句的实际两行为准整体删除。

4. README 断言中的「快照式重写」——2.0 稳定层不再整体重写（`docs` section 内）：
```powershell
    Check ($readme -match '快照式重写') 'README 保留 sync 核心功能说明'
```

**不要删除任何敏感信息闸门相关的断言。** 它们是 2.0 仍须满足的契约，如果改写
`SKILL.md` 时误删了闸门条款，这些断言会立刻报失败，这是预期的保护。

- [ ] **Step 3: 在 sync section 的 `if (Test-Path -LiteralPath $codexSkillPath) {` 区块内追加 2.0 契约断言**

追加到该区块末尾（`}` 之前）。首行先建立 markup 归一化文本，后面两条断言依赖它——
它们要匹配的原文分别含反引号和 `**`，用 `Remove-Whitespace` 会漏匹配：

```powershell
    $markup = Remove-Markup $content

    Check ($content -match 'sync:docs schema=2') `
      'sync 2.0 定义稳定层 schema 标记'
    Check ($content -match '\.handoff/') `
      'sync 2.0 定义分支现场目录'
    Check ($content -match 'git rev-parse --path-format=absolute --git-common-dir') `
      'sync 2.0 用 common dir 定位协同看板'
    Check ($markup.Contains('禁止使用gitconfiginit.defaultBranch')) `
      'sync 2.0 明令禁止用 init.defaultBranch 探测主干'
    Check ($content -match 'git symbolic-ref --quiet refs/remotes/origin/HEAD') `
      'sync 2.0 定义主干探测第一优先级'
    Check ($markup.Contains('完整分支名的UTF-8字节')) `
      'sync 2.0 规定哈希输入为 UTF-8 字节'
    Check ($content -match 'git branch --merged') `
      'sync 2.0 用 merged 判据识别已完成分支'
    Check ($markup.Contains('禁止使用文件mtime')) `
      'sync 2.0 禁止用 mtime 做时间判据'
    Check ($content -match '\[待核实\]') `
      'sync 2.0 定义 L3 语义过期的就地标注'
    Check ($markup.Contains('只产出淘汰决议')) `
      'sync 2.0 规定 GC 不直接落盘'
    Check ($markup.Contains('稳定层不设全局更新时间戳')) `
      'sync 2.0 移除必然冲突的全局时间戳'
    Check ($markup.Contains('非主干分支不修改HANDOFF.md')) `
      'sync 2.0 把迁移锚点锁定在主干'
    Check ($content -match '/sync:docs 预览') `
      'sync 2.0 提供预览开关'
    Check ($markup.Contains('Git项目直接应用，不再要求确认编号')) `
      'sync 2.0 取消 Git 项目的两阶段确认'
    Check ($markup.Contains('非Git项目保留二次确认')) `
      'sync 2.0 对非 Git 项目保留确认'
    Check ($markup.Contains('绝不记录配置项的值')) `
      'sync 2.0 配置项清单只记存在性'
    Check ($content -match 'mkdir -p') `
      'sync 2.0 要求写入前创建目录（空目录不进 Git）'
```

- [ ] **Step 4: 在 sync section 追加版本断言**

在 `if (Should-Run 'sync') {` 区块内、`$claudeSkillPath` 定义之后追加：

```powershell
  $claudeManifestPath = Join-Path $root 'plugins\sync\.claude-plugin\plugin.json'
  $codexManifestPath = Join-Path $root 'plugins\sync\codex\.codex-plugin\plugin.json'
  if ((Test-Path -LiteralPath $claudeManifestPath) -and
      (Test-Path -LiteralPath $codexManifestPath)) {
    $claudeManifest = Read-JsonUtf8 $claudeManifestPath
    $codexManifest = Read-JsonUtf8 $codexManifestPath
    Check ($claudeManifest.version -eq '2.0.0') 'sync Claude 清单版本为 2.0.0'
    Check ($codexManifest.version -eq '2.0.0') 'sync Codex 清单版本为 2.0.0'
    Check ($claudeManifest.version -eq $codexManifest.version) `
      'sync 双平台清单版本一致'
  }
```

- [ ] **Step 5: 在 docs section 追加 README 与新计划文档的断言**

替换掉 Step 1 删除的 README 断言，在同一 `if (Test-Path -LiteralPath $readmePath) {` 区块内追加：

```powershell
    Check ($readme -match '\.handoff/') 'README 说明分支现场目录'
    Check ($readme -match '协同看板') 'README 说明协同看板'
    Check ($readme -match '主干分支') 'README 说明老项目迁移需在主干执行'
```

并在 `foreach ($portableDocument in @(` 的数组中追加一行，使新计划也受可移植性检查约束：

```powershell
    @{ Label = 'sync 2.0 实施计划'; Path = (Join-Path $root `
        'docs\superpowers\plans\2026-09-01-sync-v2-layered-handoff.md') }
```

- [ ] **Step 6: 运行测试，确认预期数量的失败**

Run:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/validate-plugin.ps1 -Section sync
```

Expected: 出现 **19 项** `FAIL:`——17 条文本契约全部失败（`SKILL.md` 尚未改写），
版本断言失败 2 条。第 3 条「sync 双平台清单版本一致」此时**通过**，因为两处当前
同为 `1.2.0`，一致性本就成立。这是 TDD 的红灯状态，符合预期。

若失败数多于 19，说明误删了敏感闸门等仍需保留的断言，回到 Step 2 核对。

- [ ] **Step 7: 提交**

```bash
git add tests/validate-plugin.ps1
git commit -m "test: 用断言定义 sync 2.0 文本契约"
```

---

### Task 4: SKILL.md —— 三层布局、定位与主干探测

**Files:**
- Modify: `plugins/sync/codex/skills/docs/SKILL.md`（替换「定位项目根与证据优先级」章节，新增「三层交接布局」章节）

**Interfaces:**
- Consumes: Task 2 的 `Resolve-MainBranch`、`Get-BranchFileName` 算法定义
- Produces: 供 Task 5–7 引用的三层术语——「稳定层」`HANDOFF.md`、「分支现场」`.handoff/<slug>-<hash>.md`、「协同看板」`<common-dir>/sync/lines/<slug>-<hash>.md`

- [ ] **Step 1: 替换「定位项目根与证据优先级」整节**

将该节全文替换为：

```markdown
## 定位项目根、主干与共享目录

若属于 Git 仓库，运行 `git rev-parse --show-toplevel` 并使用返回目录作为项目根；
否则使用当前工作目录。各 worktree 的项目根互不相同，这是分支现场天然隔离的基础。

协同看板位于 `git rev-parse --path-format=absolute --git-common-dir` 返回目录下的
`sync/lines/`。所有 worktree 的该路径指向同一个主仓库 `.git`，因此看板天然跨
worktree 共享，且不进 Git、不参与 merge。

主干分支按以下优先级探测，**禁止使用 `git config init.defaultBranch`**，其值可能
与真实主干不符：

1. `git symbolic-ref --quiet refs/remotes/origin/HEAD`，去掉 `refs/remotes/origin/` 前缀
2. `refs/remotes/origin/main` 或 `refs/remotes/origin/master` 的存在性
3. `refs/heads/main` 或 `refs/heads/master` 的存在性
4. 均不可得时，**跳过全部 merged 判据**，仅使用时间判据，并在报告中说明

实时 Git、测试和文件状态优先于旧交接文档；旧交接只作为线索。发现冲突时写入当前
事实，并把未重新验证的旧结论标为未验证或删除。
```

- [ ] **Step 2: 在其后新增「三层交接布局」章节**

```markdown
## 三层交接布局

按变动频率与归属范围分为三层，各层职责不得混淆。

| 层 | 位置 | 进 Git | 内容 |
|---|---|---|---|
| 稳定层 | 项目根 `HANDOFF.md` | 是 | 概览、运行现状、配置项清单、重要文件、长期决策、坑、常用命令 |
| 分支现场 | `.handoff/<slug>-<hash>.md` | 是 | 任务看板、本分支决策、下一步 |
| 协同看板 | `<common-dir>/sync/lines/<slug>-<hash>.md` | 否 | 一句话状态、占用文件、最后更新时间 |

文件名生成规则：`slug` 为分支名把 `/ \ : * ? " < > |` 替换为 `-`；`hash` 为
**完整分支名的 UTF-8 字节**做 SHA-1 后取前 6 位十六进制小写。必须显式使用 UTF-8，
不得依赖平台默认编码，否则含中文的分支名在不同宿主下会算出不同哈希。加哈希是
必需的：`feat/auth` 与 `feat-auth` 的 slug 相同，仅靠 slug 会碰撞。

分支现场与看板条目的 frontmatter 必须记录完整分支名与 worktree 路径，读取时校验
一致性；不一致说明发生了哈希碰撞或文件被手工改名，此时停止写入并报告。

写入任何一层之前必须先 `mkdir -p` 创建目录。空目录不进 Git，新建的 worktree 中
`.handoff/` 并不存在。

稳定层**不设全局更新时间戳**。1.x 顶部的 `> 更新时间` 行每次调用必变，两个分支
各运行一次即产生必然冲突。新鲜度由 `git blame` 与各条目的「最后核实」标注承担。
稳定层顶部改写 `<!-- sync:docs schema=2 -->` 作为版本标记。

稳定层仅在事实确实变化时才修改，禁止无意义重写。
```

- [ ] **Step 3: 运行测试，确认对应断言转绿**

Run:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/validate-plugin.ps1 -Section sync
```

Expected: 以下 8 条由 FAIL 转为 PASS——schema 标记、分支现场目录、common dir、禁止 init.defaultBranch、主干探测第一优先级、UTF-8 字节、全局时间戳、mkdir -p。剩余断言仍为 FAIL。

- [ ] **Step 4: 提交**

```bash
git add plugins/sync/codex/skills/docs/SKILL.md
git commit -m "feat(sync): 定义三层交接布局与主干探测规则"
```

---

### Task 5: SKILL.md —— 三级信息淘汰机制

**Files:**
- Modify: `plugins/sync/codex/skills/docs/SKILL.md`（在「三层交接布局」之后新增「信息淘汰」章节）

**Interfaces:**
- Consumes: Task 4 的三层术语与主干探测结果
- Produces: 「淘汰决议」概念，Task 7 的写入步骤消费它

- [ ] **Step 1: 新增「信息淘汰」整节**

```markdown
## 信息淘汰

按判据可靠性分三级，判据越可靠动作越激进。三级机制**只产出淘汰决议，不自行写
文件**；决议与本次新内容在写入步骤合并后一次性落盘，避免同一文件被写两次。

### L1 客观过期：直接执行

判据均为 Git 或文件系统可回答的是非题。

| 对象 | 判据 | 动作 |
|---|---|---|
| 看板条目 | 分支已不在 `git branch --format='%(refname:short)'` 输出中 | 删除该条目文件 |
| 看板条目 | 分支仍在，但其 worktree 已不在 `git worktree list --porcelain` 中 | 不删，标注「无活跃 worktree」并转入 L2 |
| 分支现场 | 分支已合并进主干（`git branch --merged <主干>`） | 决策提炼后删除，见下 |
| 稳定层条目 | 引用的文件路径已不存在 | 就地标注 `⚠️ 路径已失效` |
| 常用命令 | 对应脚本或 target 已不存在 | 就地标注 `⚠️ 命令已失效` |

主干不可探测时跳过 merged 判据，并在报告中说明。

**已合并分支的决策提炼**：删除其现场文件前，先把该文件 `## 🧠 本分支决策` 中仍然
成立的条目去重并入稳定层 `## 🧠 长期决策与理由`。决策是长期资产，现场是易失状态。
提炼后删除现场文件；Git 历史保留完整内容，可用
`git log --all -- .handoff/<文件名>` 找回，且本 skill 不执行 commit，用户提交前
必然看到 diff。

### L2 时间陈旧：降级

| 对象 | 判据 | 动作 |
|---|---|---|
| 看板条目 | 条目更新超过 14 天**且**该分支 `git log -1` 也超过 14 天 | 移入「💤 休眠」区 |
| 休眠条目 | 进入休眠后再超过 30 天 | 删除 |
| 任务看板 | `[x]` 已完成条目超过 15 条 | 最早的收敛为一行摘要 |

两个条件必须同时满足。只看条目时间会误杀——用户可能在该分支持续开发但未运行本
skill，叠加 Git 活动度后判定才准确。

时间一律取文件内记录的 ISO 8601 时间戳，**禁止使用文件 mtime**：`git checkout`
与创建 worktree 都会重写 mtime，据此判断会大面积误杀。

### L3 语义过期：只标注，不删除

适用于需要判断而非查证的情形，例如「下一步」中的事项看起来已完成、两处描述互相
矛盾。动作是就地改写为 `- [待核实] <原内容>`，**保留原文不删**，并在报告中列出。

这类判断可能出错，因此以「只标不删」限制其破坏面，把删除决定权留给用户；用户在
`git diff` 中一眼可见。

### 非 Git 项目的退化

无分支、无 common dir 时只保留两项：稳定层引用路径的存在性检查，以及 L3 就地
标注。没有 L1 的分支判据，也没有 L2 的时间判据。禁止执行任何 Git 命令。
```

- [ ] **Step 2: 运行测试，确认对应断言转绿**

Run:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/validate-plugin.ps1 -Section sync
```

Expected: 以下 4 条转为 PASS——`git branch --merged`、禁止 mtime、`[待核实]`、只产出淘汰决议。

- [ ] **Step 3: 提交**

```bash
git add plugins/sync/codex/skills/docs/SKILL.md
git commit -m "feat(sync): 新增三级信息淘汰机制"
```

---

### Task 6: SKILL.md —— 老项目迁移与续接升级

**Files:**
- Modify: `plugins/sync/codex/skills/docs/SKILL.md`（新增「老项目迁移」章节，替换「步骤 3：配置新会话/任务续接」）

**Interfaces:**
- Consumes: Task 4 的 schema 标记与三层术语
- Produces: 迁移判据与续接区块模板

- [ ] **Step 1: 新增「老项目迁移」整节**

```markdown
## 老项目迁移（1.x → 2.0）

### 识别

| 痕迹 | 旧格式特征 | 处理 |
|---|---|---|
| `HANDOFF.md` | 不含 `<!-- sync:docs schema=2 -->` | 需要拆分 |
| `CLAUDE.md` | 含裸 `@HANDOFF.md` 行但无 `<!-- sync:docs start -->` | 升级为哨兵区块 |
| `AGENTS.md` | 已含 `<!-- sync:docs start -->` 与 `<!-- sync:docs end -->` | 幂等替换区块内容 |

### 迁移锚点

拆分只能发生一次。若各分支分别拆分，会产生互不相同的稳定层，造成严重冲突。

- 在主干分支：执行完整拆分。
- 在非主干分支：**非主干分支不修改 HANDOFF.md**，仅创建本分支现场文件与看板
  条目，并在报告中提示「稳定层拆分请在主干分支运行一次」。

### 节归类

| 旧节 | 去向 |
|---|---|
| `## 概览` | 稳定层 `## 概览` |
| `## 📁 重要文件` | 稳定层 `## 📁 重要文件` |
| `## ⚠️ 注意事项 / 坑` | 稳定层 `## ⚠️ 注意事项 / 坑` |
| `## ▶️ 常用命令` | 稳定层 `## ▶️ 常用命令` |
| `## 🧠 关键决策与理由` | 稳定层 `## 🧠 长期决策与理由` |
| `## ✅ 已完成` | 分支现场 `## 📋 任务看板`，标记 `[x]` |
| `## 🔄 进行中` | 分支现场 `## 📋 任务看板`，标记 `[~]` |
| `## ⏭️ 下一步` | 分支现场 `## ⏭️ 下一步` |
| `> 更新时间：<时间>` | 删除 |

稳定层新增的 `## 🚀 运行现状` 与 `## 🔑 配置项清单` 由本次收集的证据填充；无法
确定的条目写「待补充」并在报告中列出。

迁移到分支现场的内容统一在顶部标注
`> 迁移自 1.x HANDOFF，未按分支归属核实`。1.x 在每个分支上都整体重写过，其中的
「已完成」可能混入其它分支的历史，不能默认属于当前分支。
```

- [ ] **Step 2: 替换「步骤 3：配置新会话/任务续接」整节**

```markdown
## 步骤 3：配置新会话/任务续接

### Claude Code

在项目根 `CLAUDE.md` 中幂等维护下列哨兵区块；文件不存在时以 `# CLAUDE.md`
开头创建。若检测到旧版遗留的裸 `@HANDOFF.md` 独占行且无哨兵，用本区块替换该行。

<!-- sync:docs start -->
@HANDOFF.md

## 开发现场续接

当前分支的执行现场在 `.handoff/` 下与当前分支同名的文件，开始任务时一并读取。
并行线看板位于仓库 common dir 的 `sync/lines/`，不进 Git。
把交接文档作为线索；若与实时 Git、测试或文件状态冲突，以实时证据为准。
<!-- sync:docs end -->

`@HANDOFF.md` 必须独占一行且**不得被反引号包裹**，否则 Claude Code 不会导入它。
区块内其它路径一律用反引号包裹，防止被误当作导入指令。不要修改 `AGENTS.md`。

### Codex

在项目根 `AGENTS.md` 中幂等维护以下区块，**不得写裸 `@HANDOFF.md`**：

<!-- sync:docs start -->
## 开发现场续接

开始任务时，先读取项目根目录的 `HANDOFF.md`，再读取 `.handoff/` 下与当前分支
同名的现场文件。并行线看板位于仓库 common dir 的 `sync/lines/`，不进 Git。
把旧交接作为线索；若与实时 Git、测试或文件状态冲突，以实时证据为准并更新交接。
<!-- sync:docs end -->

不要修改 `CLAUDE.md`。若存在 `AGENTS.override.md`，报告遮蔽风险但不自动修改。

### 哨兵校验（两平台通用）

先精确统计两个哨兵并检查位置。只有在开始哨兵和结束哨兵各恰好出现一次，且开始
哨兵位于结束哨兵之前时，才替换完整区块。两个哨兵都未出现时追加。其它情况，包括
单边、重复或逆序哨兵，均停止修改该文件并报告。
```

- [ ] **Step 3: 运行测试，确认迁移锚点断言转绿**

Run:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/validate-plugin.ps1 -Section sync
```

Expected: 「sync 2.0 把迁移锚点锁定在主干」转为 PASS。

- [ ] **Step 4: 提交**

```bash
git add plugins/sync/codex/skills/docs/SKILL.md
git commit -m "feat(sync): 新增老项目迁移与续接区块升级"
```

---

### Task 7: SKILL.md —— 流程改造与冲突预警

**Files:**
- Modify: `plugins/sync/codex/skills/docs/SKILL.md`（替换「平台速查」「步骤 2」「步骤 4.5」「步骤 5」「常见错误」）
- Modify: `plugins/sync/skills/docs/SKILL.md`（同步参数说明）

**Interfaces:**
- Consumes: Task 4 三层布局、Task 5 淘汰决议、Task 6 迁移判据
- Produces: 完整的 2.0 执行流程

- [ ] **Step 1: 替换「平台速查」表**

```markdown
## 平台速查

| 宿主 | 调用 | 预览 | 续接载体 |
|---|---|---|---|
| Claude Code | `/sync:docs` | `/sync:docs 预览` | `CLAUDE.md` 哨兵区块（含 `@HANDOFF.md`） |
| Codex | `$sync:docs` | `$sync:docs 预览` | `AGENTS.md` 哨兵区块 |
```

- [ ] **Step 2: 替换「步骤 2」为三层写入**

```markdown
## 步骤 2：写入三层

把淘汰决议与本次新内容合并后一次性落盘。

### 稳定层 `HANDOFF.md`

仅在事实确实变化时修改。顶部为 `<!-- sync:docs schema=2 -->`，无全局时间戳。

节结构：`## 概览`、`## 🚀 运行现状`、`## 🔑 配置项清单`、`## 📁 重要文件`、
`## 🧠 长期决策与理由`、`## ⚠️ 注意事项 / 坑`、`## ▶️ 常用命令`。某节确无内容时可
省略。同一事实只写一条，不得跨节重复。

`## 🚀 运行现状` 记录部署目标、启动方式、依赖的外部服务与端口；带凭据的 URL 必须
脱敏。`## 🔑 配置项清单` 只记录需要哪些环境变量或密钥、位于哪个文件、由谁提供，
**绝不记录配置项的值**。

### 分支现场 `.handoff/<slug>-<hash>.md`

整体重写。顶部写 `> 更新时间：<ISO 8601>` 与记录完整分支名的 frontmatter。

节结构：`## 📋 任务看板`、`## 🧠 本分支决策`、`## ⏭️ 下一步`。

任务看板条目带稳定序号与状态标记：`[ ]` 待办、`[~]` 进行中、`[!]` 阻塞、
`[x]` 已完成。

### 协同看板 `<common-dir>/sync/lines/<slug>-<hash>.md`

只重写属于当前分支的那一份，**禁止写入汇总单文件**——两个 worktree 并发写同一
文件会导致先写方内容完全丢失。聚合视图在读取时现场渲染，不落盘。

单条内容：完整分支名、worktree 绝对路径、一句话状态、占用文件列表、最后更新时间。
占用文件列表取自 `git diff --name-only` 与 `git diff --staged --name-only`，属安全
元数据。该文件虽不进 Git，仍受持久化前的敏感信息筛查约束。
```

- [ ] **Step 3: 用「步骤 4：刷新其它文档」替换原步骤 4 与 4.5 的确认流程**

保留原有的建议类型定义（`过时`、`可收敛`、`可合并`）、日志型跳过规则与权威出处
规则，仅把确认模型替换为：

```markdown
### 应用方式

**Git 项目直接应用，不再要求确认编号。** 本 skill 从不执行 `git commit`，全部改动
停留在工作树，用户可用 `git diff` 复核、`git checkout` 撤销，Git 本身即安全网。

**非 Git 项目保留二次确认**：没有该安全网。修改前由同一本地调用捕获将修改文件的
修改前 UTF-8 快照；raw 快照只能留在进程内存或系统临时文件中，按闸门过滤后才可
返回。若发现疑似秘密且无法在不破坏原文的前提下安全修改，跳过该文件并请求人工
处理。

`/sync:docs 预览` 或 `$sync:docs 预览` 输出全部拟执行动作，包括迁移计划与淘汰
明细，但不写任何文件。
```

- [ ] **Step 4: 替换「步骤 5：向用户汇报」**

```markdown
## 步骤 5：向用户汇报

用简体中文报告：

1. 实际创建或更新的三层文件路径
2. 当前宿主的续接载体
3. 本次淘汰明细：L1 删除项、L2 降级项、L3 标注为 `[待核实]` 的条目
4. **并行线冲突预警**：比对各活跃线的占用文件列表，若两条线改动同一批文件，
   直接列出重合的文件与涉及的分支
5. 若执行了迁移，说明迁移结果；若在非主干分支跳过了稳定层拆分，明确提示
6. Git 项目附 `git diff --stat` 摘要；非 Git 项目摘要同一本地调用内 UTF-8 前后
   快照的脱敏比较结果，并明确全程未执行 Git 命令
7. 主干不可探测时，说明已跳过 merged 判据

提示用户复核并自行决定是否提交。不执行 `git commit`。
```

- [ ] **Step 5: 更新「常见错误」列表**

```markdown
## 常见错误

- 不把旧交接当作比实时 Git 更可信的事实。
- 不用 `git config init.defaultBranch` 探测主干。
- 不用文件 mtime 做时间判据。
- 不把协同看板写成单个汇总文件。
- 不在非主干分支拆分稳定层。
- 不在稳定层写全局更新时间戳。
- 不直接运行会把原始 diff 或测试 stdout/stderr 返回任务上下文的命令。
- 不在过滤能力缺失或失败时降级输出原始内容。
- 不在 Codex 的 AGENTS 中写裸 `@HANDOFF.md`。
- 不扫描全项目做两两文档比较。
- 不在非 Git 项目中运行任何 Git 命令。
- 不读写 Claude Code 的 auto memory 目录。memory 是本机私有且不进 Git，Codex
  无对等物；由它承载长期偏好，本 skill 只承载项目现场，两者职责分离。
- 不自动 commit。
```

- [ ] **Step 6: 同步 Claude 薄入口的参数说明**

修改 `plugins/sync/skills/docs/SKILL.md` 第 1 条，把 `（可带 应用 1,3 参数）`
改为 `（可带 预览 参数）`。其余结构不变，仍只声明宿主并读取共享核心。

- [ ] **Step 7: 运行 sync section，确认全绿**

Run:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/validate-plugin.ps1 -Section sync
```

Expected: 仅剩 2 条版本断言 FAIL（两处 `plugin.json` 仍为 `1.2.0`，待 Task 8 升级），
其余全部 PASS。

- [ ] **Step 8: 提交**

```bash
git add plugins/sync/codex/skills/docs/SKILL.md plugins/sync/skills/docs/SKILL.md
git commit -m "feat(sync): 取消两阶段确认并新增冲突预警"
```

---

### Task 8: 版本升级与发布物更新

**Files:**
- Modify: `plugins/sync/.claude-plugin/plugin.json`
- Modify: `plugins/sync/codex/.codex-plugin/plugin.json`
- Modify: `plugins/sync/codex/skills/docs/agents/openai.yaml`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 3 的版本断言与 README 断言
- Produces: 可发布的 2.0.0 版本

- [ ] **Step 1: 升级两处版本号与描述**

`plugins/sync/.claude-plugin/plugin.json`：

```json
{
  "name": "sync",
  "version": "2.0.0",
  "description": "分层固化开发现场并安全刷新相关文档，支持多 worktree 并行",
  "author": {
    "name": "hangwenlei"
  }
}
```

`plugins/sync/codex/.codex-plugin/plugin.json`：把 `version` 改为 `2.0.0`，
`description` 改为与上面一致，并把 `interface.longDescription` 改为：

```json
"longDescription": "分层生成 HANDOFF.md 与分支现场，维护跨 worktree 协同看板，配置新任务读取交接，并自动淘汰过时信息。"
```

- [ ] **Step 2: 更新 openai.yaml，去掉「确认式流程」措辞**

```yaml
interface:
  display_name: "同步开发现场"
  short_description: "为 Codex 分层固化开发现场并刷新相关文档"
  default_prompt: "Use $sync:docs to capture the current development state and refresh related documentation."
policy:
  allow_implicit_invocation: false
```

`allow_implicit_invocation: false` 必须保留在顶层 `policy` 下，缩进不变——
`Test-YamlPolicyFalse` 会拒绝嵌套写法。

- [ ] **Step 3: 更新 marketplace 描述**

`.claude-plugin/marketplace.json` 的 sync 条目：

```json
    {
      "name": "sync",
      "source": "./plugins/sync",
      "description": "分层固化开发现场，支持多 worktree 并行与过时信息淘汰"
    }
```

- [ ] **Step 4: 改写 README 的 sync 章节**

替换「## sync 插件」整节为：

```markdown
## sync 插件

开发到一半想停下来时，运行对应平台的调用命令：它会把当前开发现场分层固化，供后续
新任务续接，并刷新相关文档。

分三层存放：

- `HANDOFF.md`（进 Git）：稳定层，写概览、运行现状、配置项清单、重要文件、长期
  决策、坑与常用命令，变动慢；
- `.handoff/<分支>-<哈希>.md`（进 Git）：分支现场，写任务看板、本分支决策与下一步。
  文件名带分支标识，多个分支产生不同文件，合并时不冲突；
- 仓库 common dir 下的 `sync/lines/`（不进 Git）：协同看板，跨 worktree 共享，
  记录每条并行线在做什么、占用了哪些文件，并在两条线改同一批文件时预警。

它会：

- 一条指令跑完全部工作，Git 项目不再要求二次确认编号；改动全在工作树，用
  `git diff` 复核、`git checkout` 撤销；
- 自动淘汰过时信息：已合并分支的现场文件在决策提炼后删除，长期无活动的看板条目
  先休眠后清除，语义可疑的条目就地标注 `[待核实]` 而不删除；
- Claude Code 维护 `CLAUDE.md` 哨兵区块（含 `@HANDOFF.md`）；Codex 维护
  `AGENTS.md` 哨兵区块；
- 不自动 commit，改完后请用 `git diff` 复核并自行提交。

**从 1.x 升级**：首次运行会自动把旧的单文件 `HANDOFF.md` 拆成稳定层与分支现场。
拆分只在**主干分支**执行；在非主干分支运行时不会修改 `HANDOFF.md`，只创建该分支
自己的现场与看板条目。想先看不改，用 `/sync:docs 预览` 或 `$sync:docs 预览`。
```

- [ ] **Step 5: 运行全量测试**

Run:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/validate-plugin.ps1
```

Expected: `全部通过`，退出码 0。

- [ ] **Step 6: 运行 GC 契约测试**

Run:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/gc-scenarios.ps1
```

Expected: 14 项 PASS，`全部通过`。

- [ ] **Step 7: 提交**

```bash
git add plugins/sync .claude-plugin/marketplace.json README.md
git commit -m "feat(sync): 发布 2.0.0 分层交接版本"
```

---

### Task 9: 本仓库自身迁移验证

**Files:**
- Modify: `HANDOFF.md`（拆分为稳定层）
- Create: `.handoff/<当前分支slug>-<hash>.md`
- Modify: `CLAUDE.md`（裸 `@HANDOFF.md` 升级为哨兵区块）
- Modify: `AGENTS.md`（哨兵区块内容更新）

**Interfaces:**
- Consumes: Task 4–8 的全部实现
- Produces: 首个真实迁移用例的验证证据

本仓库自身就是 1.x 老项目：现有 `HANDOFF.md` 为 8 节含 `> 更新时间` 行、
`CLAUDE.md` 末尾为裸 `@HANDOFF.md`、`AGENTS.md` 已有哨兵区块。它是检验第 7 节
迁移逻辑的首个真实用例。

- [ ] **Step 1: 先在预览模式确认迁移计划**

在 Claude Code 中运行：

```text
/sync:docs 预览
```

Expected: 输出迁移计划，列出 8 节的归类去向、将创建的分支现场文件名、将升级的
`CLAUDE.md` 区块，且**不修改任何文件**。

- [ ] **Step 2: 确认工作树在预览后未被修改**

Run:

```bash
git status --short
```

Expected: 与预览前一致，`sync` 未写入任何文件。

- [ ] **Step 3: 切到主干分支执行真实迁移**

迁移锚点锁定主干，必须在主干上执行拆分：

```bash
git checkout main
```

然后运行 `/sync:docs`。

- [ ] **Step 4: 核对迁移结果**

Run:

```bash
git status --short
git diff --stat
head -3 HANDOFF.md
ls .handoff/
```

Expected: `HANDOFF.md` 首行为 `<!-- sync:docs schema=2 -->`，不含 `> 更新时间`
行；`.handoff/` 下存在一个 `main-<哈希>.md`；`CLAUDE.md` 的裸 `@HANDOFF.md` 已被
哨兵区块包裹且 `@HANDOFF.md` 仍独占一行未被反引号包裹。

- [ ] **Step 5: 验证非主干分支不拆分稳定层**

```bash
git checkout feat/sync-v2-layered-handoff
```

运行 `/sync:docs`，然后：

```bash
git diff --stat HANDOFF.md
```

Expected: `HANDOFF.md` **无改动**；只新增该分支自己的 `.handoff/` 文件与看板
条目；报告中出现「稳定层拆分请在主干分支运行一次」的提示。

- [ ] **Step 6: 运行全量测试确认未破坏契约**

Run:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/validate-plugin.ps1
```

Expected: `全部通过`。

- [ ] **Step 7: 提交**

```bash
git add HANDOFF.md .handoff CLAUDE.md AGENTS.md
git commit -m "docs: 迁移本仓库到 sync 2.0 分层交接格式"
```
