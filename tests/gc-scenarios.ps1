param(
  [ValidateSet('all', 'env', 'algo', 'scenario')]
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

function New-RemoteScenario {
  param(
    [string]$InitialBranch,
    [string[]]$OriginBranches = @(),
    [string]$OriginHeadBranch = $null
  )
  # 独立于 New-GcScenario 的场景工厂：专门造带 origin 远端的仓库，
  # 用来覆盖 Resolve-MainBranch 的第 1/2 级（origin/HEAD、origin/<candidate>）
  # 以及第 4 级（无 remote 且本地无候选分支）。不改动 New-GcScenario，
  # 避免影响 env section 已依赖它当前行为的 11 个断言。
  $root = Join-Path $env:TEMP ('sync-remote-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  $repo = Join-Path $root 'repo'
  New-Item -ItemType Directory -Path $repo -Force | Out-Null
  & git init -q $repo
  # 不用 git init -b，兼容 2.28 以前的版本
  & git -C $repo symbolic-ref HEAD "refs/heads/$InitialBranch"
  & git -C $repo config user.email 'test@example.com'
  & git -C $repo config user.name 'sync-test'
  Set-Content -LiteralPath (Join-Path $repo 'seed.md') -Value '# seed' -Encoding utf8
  & git -C $repo add -A
  & git -C $repo commit -q -m 'init'

  $origin = $null
  if ($OriginBranches.Count -gt 0) {
    $origin = Join-Path $root 'origin.git'
    & git init -q --bare $origin
    foreach ($b in $OriginBranches) {
      & git -C $repo push -q $origin "HEAD:refs/heads/$b"
    }
    & git -C $repo remote add origin $origin
    & git -C $repo fetch -q origin
    if ($OriginHeadBranch) {
      # 显式设置 origin/HEAD，模拟 clone 时从远端默认分支继承的本地副本
      & git -C $repo symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$OriginHeadBranch"
    }
  }

  return [pscustomobject]@{ Root = $root; Repo = $repo; Origin = $origin }
}

# ===========================================================================
# scenario section 的判据实现与场景工厂
# 这一节验证什么、不验证什么，见下面 `if (Should-Run 'scenario')` 顶部的说明。
# 下列函数是 SKILL.md「信息淘汰」散文判据的 PowerShell 重写，二者靠人工保持
# 一致：改判据时必须两边一起改，否则测试会继续为一份已经过时的规则背书。
# ===========================================================================

function Invoke-GitCapture {
  param([string]$Repo, [string[]]$GitArgs)
  # 需要同时拿到 stdout、stderr 和 exit code 时用它。Windows PowerShell 5.1 下
  # 不能用 2>&1 把原生 exe 的 stderr 并进管道：每行会被包成 ErrorRecord，
  # 且 $? 变 false，判据会被这层包装误导。改用 System.Diagnostics.Process，
  # 与 SKILL.md「敏感信息与证据读取闸门」推荐的可靠本地捕获形式一致。
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = 'git'
  $psi.Arguments = ((@('-C', $Repo) + $GitArgs) | ForEach-Object { '"' + $_ + '"' }) -join ' '
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $proc = [System.Diagnostics.Process]::Start($psi)
  # 先建异步读取任务再 WaitForExit：任一管道写满 4KB 缓冲都会造成死锁
  $outTask = $proc.StandardOutput.ReadToEndAsync()
  $errTask = $proc.StandardError.ReadToEndAsync()
  $proc.WaitForExit()
  $captured = [pscustomobject]@{
    Out  = $outTask.Result
    Err  = $errTask.Result
    Code = $proc.ExitCode
  }
  $proc.Dispose()
  return $captured
}

function Get-BranchNameCandidate {
  param([string]$Repo, [string]$BranchName)
  # SKILL.md：比对时 `<分支名>` 与 `<remote>/<分支名>` 任一命中即算分支仍存在。
  # 候选用 git remote 列出的真实 remote 名拼，不靠「按斜杠切一刀」猜——
  # 分支名自己就可能带斜杠（feat/auth 的远端短名是 origin/feat/auth）。
  $candidates = @($BranchName)
  foreach ($remote in @(& git -C $Repo remote)) {
    if (-not [string]::IsNullOrWhiteSpace($remote)) {
      $candidates += ('{0}/{1}' -f $remote.Trim(), $BranchName)
    }
  }
  return $candidates
}

function Get-BranchPresentMatch {
  param([string]$Repo, [string]$BranchName, [switch]$LocalOnly)
  # tier 1 的实际命中项：既是分支存在性判据的依据，也是 tier 3 第 2 顺位修订的来源
  # （SKILL.md：解析不到裸名时，改试 tier 1 在 branch -a 输出里实际命中的那个短名）。
  # -LocalOnly 复现修复前只查本地的 `git branch` 形态，供鉴别力断言使用。
  $branchArgs = @('branch')
  if (-not $LocalOnly) { $branchArgs += '-a' }
  $branchArgs += '--format=%(refname:short)'
  $listed = @(@(& git -C $Repo @branchArgs) | ForEach-Object { $_.Trim() })
  $candidates = Get-BranchNameCandidate -Repo $Repo -BranchName $BranchName
  return @($candidates | Where-Object { $listed -contains $_ })
}

function Test-BranchPresent {
  param([string]$Repo, [string]$BranchName, [switch]$LocalOnly)
  # tier 1：分支是否仍存在。本地没有、远端还有的分支绝不算消失。
  return (@(Get-BranchPresentMatch -Repo $Repo -BranchName $BranchName -LocalOnly:$LocalOnly).Count -gt 0)
}

function Resolve-MainRevision {
  param([string]$Repo, [string]$MainBranch, [switch]$BareOnly)
  # SKILL.md 的 `<主干修订>`，与 `<分支修订>` 同形。主干探测链的第 1、2 级是从远端
  # 得出结论的，返回的是裸名（如 main）。本地若没有同名分支（本地 master、远端 main），
  # 把裸名直接传给 `git branch -a --merged main` 会以 exit 128 +
  # `fatal: malformed object name main` 失败，tier 2 于是静默失效——失败方向是「不删」，
  # 安全，但也正因为安全才最容易被忽略。因此：裸名 → <remote>/<主干名> → 均不解析
  # 则返回 $null，调用方据此跳过 tier 2 并报告。
  # -BareOnly 复现修复前只认裸名的形态，供鉴别力断言使用。
  if ([string]::IsNullOrWhiteSpace($MainBranch)) { return $null }
  $ordered = @($MainBranch)
  if (-not $BareOnly) {
    foreach ($remote in @(& git -C $Repo remote)) {
      if (-not [string]::IsNullOrWhiteSpace($remote)) {
        $ordered += ('{0}/{1}' -f $remote.Trim(), $MainBranch)
      }
    }
  }
  foreach ($candidate in $ordered) {
    & git -C $Repo rev-parse --verify --quiet $candidate | Out-Null
    if ($LASTEXITCODE -eq 0) { return $candidate }
  }
  return $null
}

function Test-BranchMerged {
  param(
    [string]$Repo,
    [string]$BranchName,
    [string]$MainBranch,
    [switch]$LocalOnly,
    [switch]$BareMain
  )
  # tier 2：是否已合并进主干，判定用 `git branch -a --merged <主干修订>`。
  # 主干不可探测时本判据跳过（SKILL.md：只有 merged 判据需要主干，
  # 另外两条不需要，不得因主干探测失败连带停掉整个孤儿回收）。
  # 主干名同样要先解析成修订，理由见 Resolve-MainRevision。
  # -BareMain 复现修复前把裸主干名直接交给 git 的形态：git 以 exit 128 失败、
  # 输出为空，判据于是静默给出 $false，供鉴别力断言使用。
  if ([string]::IsNullOrWhiteSpace($MainBranch)) { return $false }
  if ($BareMain) {
    $mainRevision = $MainBranch
  } else {
    $mainRevision = Resolve-MainRevision -Repo $Repo -MainBranch $MainBranch
    # $null 表示两种形式都解析不到：跳过 tier 2 并报告，不读作「未合并」后沉默
    if ($null -eq $mainRevision) { return $false }
  }
  $branchArgs = @('branch')
  if (-not $LocalOnly) { $branchArgs += '-a' }
  $branchArgs += @('--merged', $mainRevision, '--format=%(refname:short)')
  $listed = @(@(& git -C $Repo @branchArgs) | ForEach-Object { $_.Trim() })
  $candidates = Get-BranchNameCandidate -Repo $Repo -BranchName $BranchName
  return (@($candidates | Where-Object { $listed -contains $_ }).Count -gt 0)
}

function Resolve-BranchRevision {
  param([string]$Repo, [string]$BranchName, [switch]$BareOnly)
  # SKILL.md 的 `<分支修订>` 解析顺序：先裸分支名，再 tier 1 命中的
  # `<remote>/<分支名>`；两者都解析不到时返回 $null，调用方据此走「不动作」。
  # 可解析性用 `git rev-parse --verify --quiet` 判定：不可解析时静默 exit 1，
  # 不像 git log 那样打出 fatal 噪音。
  # -BareOnly 复现修复前只认裸名的形态，供鉴别力断言使用。
  $ordered = @($BranchName)
  if (-not $BareOnly) {
    foreach ($hit in Get-BranchPresentMatch -Repo $Repo -BranchName $BranchName) {
      if ($hit -ne $BranchName) { $ordered += $hit }
    }
  }
  foreach ($candidate in $ordered) {
    & git -C $Repo rev-parse --verify --quiet $candidate | Out-Null
    if ($LASTEXITCODE -eq 0) { return $candidate }
  }
  return $null
}

function Get-BranchIdleState {
  param([string]$Repo, [string]$BranchName, [int]$IdleDay = 14, [switch]$BareOnly)
  # tier 3：三态返回，'IDLE' 超过阈值、'ACTIVE' 未超过、'NOOP' 修订解析不到。
  # 'NOOP' 必须与 'IDLE' 严格区分：取不到提交时间不等于长期无活动。把解析失败
  # 沿用「超过 14 天」那条分支，等于拿一次错误当删除依据，方向恰好反了。
  $revision = Resolve-BranchRevision -Repo $Repo -BranchName $BranchName -BareOnly:$BareOnly
  if ($null -eq $revision) { return 'NOOP' }
  # 只取 %cI（ISO 8601 提交时间）：不带 --format 的 git log 会把 commit subject
  # 带进上下文，而 subject 属证据读取闸门管辖，判据不该在这里绕开它。
  $stamp = (@(& git -C $Repo log -1 --format=%cI $revision) -join '').Trim()
  if ([string]::IsNullOrWhiteSpace($stamp)) { return 'NOOP' }
  $age = ([datetimeoffset]::Now - [datetimeoffset]::Parse($stamp)).TotalDays
  if ($age -gt $IdleDay) { return 'IDLE' }
  return 'ACTIVE'
}

function Get-HandoffVerdict {
  param(
    [string]$Repo,
    [string]$BranchName,
    [string]$MainBranch,
    [int]$IdleDay = 14,
    [ValidateSet('current', 'legacy-local', 'legacy-wide-tier1',
                 'legacy-no-main-exempt', 'legacy-bare-main')]
    [string]$Mode = 'current'
  )
  # 对一个 .handoff/ 现场文件依次跑 L1 的三条判据，产出本轮裁决：
  #   COLLECT  提炼决策后删除（tier 1 或 tier 2 命中）
  #   DORMANT  转入 L2 休眠流程（tier 3 命中）
  #   KEEP     本轮不动它（含 tier 3 因修订解析不到而不动作、以及主干豁免）
  # Mode 复现四个历史形态，让每条场景断言都能自证有鉴别力：
  #   legacy-local           三条判据全是本地视角 —— 第一次事故：新 clone 全量误删
  #   legacy-wide-tier1      只把 tier 1 放宽到 -a —— 第二次事故：孤儿回收成死规则
  #   legacy-no-main-exempt  无主干豁免 —— 2.0.0 缺陷 A：主干自己的现场文件每次被删
  #   legacy-bare-main       裸主干名直接当修订 —— 2.0.0 缺陷 B：tier 2 exit 128 静默失效
  $localTier1 = ($Mode -eq 'legacy-local')
  $localTier2 = ($Mode -in @('legacy-local', 'legacy-wide-tier1'))
  $bareTier3 = ($Mode -in @('legacy-local', 'legacy-wide-tier1'))
  $bareMain = ($Mode -eq 'legacy-bare-main')
  $exemptMain = ($Mode -ne 'legacy-no-main-exempt')

  # 主干自身的现场文件只受 tier 1 约束。两条理由（SKILL.md「主干自身的现场文件
  # 豁免 tier 2、tier 3 与全部 L2」）：任何分支都平凡地「已合并进它自己」，
  # `branch -a --merged <主干修订>` 的输出必然含主干本身，tier 2 每次运行都命中；
  # 且主干是干线不是功能线，长期无提交不构成回收理由。站在主干上时 tier 1 平凡
  # 成立，因此这里直接给 KEEP。豁免只针对主干这一份，其它分支照旧走完三条判据。
  if ($exemptMain -and
      -not [string]::IsNullOrWhiteSpace($MainBranch) -and
      $BranchName -eq $MainBranch) {
    return 'KEEP'
  }

  if (-not (Test-BranchPresent -Repo $Repo -BranchName $BranchName -LocalOnly:$localTier1)) {
    return 'COLLECT'
  }
  if (Test-BranchMerged -Repo $Repo -BranchName $BranchName -MainBranch $MainBranch `
        -LocalOnly:$localTier2 -BareMain:$bareMain) {
    return 'COLLECT'
  }
  if ((Get-BranchIdleState -Repo $Repo -BranchName $BranchName -IdleDay $IdleDay -BareOnly:$bareTier3) -eq 'IDLE') {
    return 'DORMANT'
  }
  return 'KEEP'
}

# 场景工厂：全部建在 $env:TEMP 下，根目录登记进 $script:scenarioRoot，
# 供本节末尾的零残留断言核对。
$script:scenarioRoot = @()

function New-ScenarioRoot {
  param([string]$Tag)
  $root = Join-Path $env:TEMP ('sync-scn-' + $Tag + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Path $root -Force | Out-Null
  $script:scenarioRoot += $root
  return $root
}

function Initialize-ScenarioRepo {
  param([string]$Path)
  & git init -q $Path | Out-Null
  # 不用 git init -b，兼容 2.28 以前的版本
  & git -C $Path symbolic-ref HEAD refs/heads/main | Out-Null
  & git -C $Path config user.email 'test@example.com' | Out-Null
  & git -C $Path config user.name 'sync-test' | Out-Null
  # 场景仓库对开发者的全局 git 配置保持隔离：否则 core.autocrlf=true 会让
  # `git add` 对本节写出的 LF 文件打印换行归一警告，绿灯里混进看似失败的噪音。
  & git -C $Path config core.autocrlf false | Out-Null
}

function Add-ScenarioCommit {
  param([string]$Repo, [string]$FileName, [string]$Message, [string]$IsoDate)
  # 指定 $IsoDate 时必须同时设 AUTHOR 与 COMMITTER：时间判据读的是 %cI（提交
  # 时间），而 `git commit --date` 只改作者时间，改不动它。
  Set-Content -LiteralPath (Join-Path $Repo $FileName) -Value $Message -Encoding utf8
  & git -C $Repo add -A | Out-Null
  if ([string]::IsNullOrWhiteSpace($IsoDate)) {
    & git -C $Repo commit -q -m $Message | Out-Null
    return
  }
  $env:GIT_AUTHOR_DATE = $IsoDate
  $env:GIT_COMMITTER_DATE = $IsoDate
  try {
    & git -C $Repo commit -q -m $Message | Out-Null
  } finally {
    Remove-Item Env:GIT_AUTHOR_DATE -ErrorAction SilentlyContinue
    Remove-Item Env:GIT_COMMITTER_DATE -ErrorAction SilentlyContinue
  }
}

function New-OriginScenario {
  param([string]$Tag)
  # 「bare origin + 一份 seed 工作仓库」，是全部 clone 场景的共同底座。
  # bare 仓库的 HEAD 必须显式指回 refs/heads/main：默认 HEAD 指向
  # refs/heads/master，clone 时会 warning: remote HEAD refers to nonexistent ref
  # 且不检出任何本地分支——那样场景就不再是「一份正常的新 clone」，
  # 后面 tier 2 连 <主干> 都解析不到，测的是另一回事了。
  $root = New-ScenarioRoot -Tag $Tag
  $origin = Join-Path $root 'origin.git'
  & git init -q --bare $origin | Out-Null
  & git -C $origin symbolic-ref HEAD refs/heads/main | Out-Null
  $seed = Join-Path $root 'seed'
  New-Item -ItemType Directory -Path $seed -Force | Out-Null
  Initialize-ScenarioRepo -Path $seed
  Add-ScenarioCommit -Repo $seed -FileName 'seed.md' -Message 'init'
  & git -C $seed remote add origin $origin | Out-Null
  & git -C $seed push -q origin main | Out-Null
  return [pscustomobject]@{ Root = $root; Origin = $origin; Seed = $seed }
}

function New-ScenarioClone {
  param($Scenario, [string]$Name = 'clone')
  $clone = Join-Path $Scenario.Root $Name
  & git clone -q $Scenario.Origin $clone | Out-Null
  & git -C $clone config user.email 'test@example.com' | Out-Null
  & git -C $clone config user.name 'sync-test' | Out-Null
  & git -C $clone config core.autocrlf false | Out-Null
  return $clone
}

function Add-ScenarioHandoff {
  param([string]$Repo, [string]$BranchName, [string]$FileName)
  # 造一份真实形状的分支现场文件：frontmatter 记录完整分支名与 worktree 路径。
  $dir = Join-Path $Repo '.handoff'
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $content = @(
    '---',
    ('branch: {0}' -f $BranchName),
    ('worktree: {0}' -f $Repo),
    '---',
    '',
    '## 🧠 本分支决策',
    '',
    '- 占位决策，用于验证删除前的决策提炼有东西可提'
  ) -join "`n"
  Set-Content -LiteralPath (Join-Path $dir $FileName) -Value $content -Encoding utf8
  return (Join-Path $dir $FileName)
}

function Get-HandoffBranchName {
  param([string]$Path)
  # 判据的输入取自现场文件 frontmatter 里的**完整分支名**，不从文件名反推——
  # 文件名经过 slug 化与哈希，不可逆。必须显式 UTF-8 读取。
  foreach ($line in @(Get-Content -LiteralPath $Path -Encoding UTF8)) {
    if ($line -match '^branch:\s*(.+)$') { return $Matches[1].Trim() }
  }
  return $null
}

function Remove-ScenarioTree {
  param([string]$Root)
  # 这些场景不建 worktree，因此不需要 Remove-GcScenario 的 worktree 拆除步骤。
  if ([string]::IsNullOrWhiteSpace($Root)) { return }
  Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
}

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
    Check ((($singleText -match 'LINE-A') -xor ($singleText -match 'LINE-B'))) `
      'T8 单文件后写覆盖先写，只有一方内容存活（故看板禁止单文件）'

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
      'T8 分文件各写各的，两方内容均存活'
  } finally {
    Remove-GcScenario $scenario
  }
}

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

  # 上面的 T5 只覆盖了第 3 级（本地分支回退）。以下三条补齐第 1/2/4 级，
  # 每条都要能区分“正确走了目标优先级”与“跳过它回退到下一级”。
  $remoteHeadScenario = $null
  try {
    # 第 1 级：origin/HEAD 指向 trunk，同时本地也存在 main——
    # 走第 1 级返回 trunk，误跳到第 3 级会返回 main，两者不同才有鉴别力。
    $remoteHeadScenario = New-RemoteScenario -InitialBranch 'main' -OriginBranches @('trunk') -OriginHeadBranch 'trunk'
    $resolvedHead = Resolve-MainBranch -Repo $remoteHeadScenario.Repo
    Check ($resolvedHead -eq 'trunk') `
      'T5 主干探测优先读取 origin/HEAD，即使本地存在同名 main 分支'
  } finally {
    Remove-GcScenario $remoteHeadScenario
  }

  $remoteMainScenario = $null
  try {
    # 第 2 级：没有 origin/HEAD，远端有 origin/main，本地只有 master——
    # 走第 2 级返回 main，误跳到第 3 级会返回 master，两者不同才有鉴别力。
    $remoteMainScenario = New-RemoteScenario -InitialBranch 'master' -OriginBranches @('main')
    $resolvedMain = Resolve-MainBranch -Repo $remoteMainScenario.Repo
    Check ($resolvedMain -eq 'main') `
      'T5 无 origin/HEAD 时回退到远端候选分支 origin/main，不误判本地 master'
  } finally {
    Remove-GcScenario $remoteMainScenario
  }

  $noMainScenario = $null
  try {
    # 第 4 级：无 remote，本地既无 main 也无 master
    $noMainScenario = New-RemoteScenario -InitialBranch 'dev'
    $resolvedNone = Resolve-MainBranch -Repo $noMainScenario.Repo
    Check ($null -eq $resolvedNone) `
      'T5 无 remote 且本地无 main/master 候选时返回 $null'
  } finally {
    Remove-GcScenario $noMainScenario
  }
}

if (Should-Run 'scenario') {
  # =========================================================================
  # 本节测的是什么、**不是**什么——先说清楚，免得后来人把绿灯读错。
  #
  # 【测的是】把 SKILL.md「信息淘汰」小节的判据用 PowerShell 重写一份（上面那组
  #   Test-BranchPresent / Test-BranchMerged / Resolve-MainRevision /
  #   Resolve-BranchRevision / Get-BranchIdleState / Get-HandoffVerdict），在真实
  #   建出来的 git 仓库上跑，核对它在六类真实处境下给出的裁决。已经逃逸过四次的
  #   缺陷都属于这一类：新 clone 把同事的现场文件全判成孤儿；「推送 → 合并 →
  #   删远端分支」之后三条判据同时落空；tier 2 把主干自己的现场文件判成删除；
  #   本地无同名主干分支时 tier 2 以 exit 128 静默失效。后两条是 2.0.0 发布后
  #   第一次在有内容的 `.handoff/` 上真实运行才暴露的——迁移那次目录还是空的，
  #   判据一条都没被真正问到。文本匹配断言看不见它们，只有把仓库真的建出来才会暴露。
  #
  # 【不测的是】skill 本身没有被执行，一次也没有。SKILL.md 的实现是自然语言指令，
  #   由 AI 在运行时阅读，并据此对用户的真实仓库执行创建、重写和**删除**。测试
  #   框架无法驱动「一个照着散文办事的模型」。因此本节全绿只证明**判据本身是对
  #   的**，不证明**AI 会照着判据做**。这个缺口依然存在，不要把本节的绿灯读成
  #   「这个 skill 已经验证过了」。
  #
  # 【于是】上面的判据函数与 SKILL.md 的散文是两份靠人工同步的实现。改任何一边
  #   都必须同时改另一边并重跑本节；否则测试会继续为一份已经过时的规则背书，
  #   那比没有测试更危险。
  #
  # 每条场景都必须有**鉴别力**：先用 Get-HandoffVerdict 的 legacy-* 模式跑出错误
  # 裁决，再用 current 模式跑出正确裁决。两种模式给同一个答案的场景什么也没测到。
  # =========================================================================

  # --- 场景 1：新 clone 不得删掉同事的现场文件 ---
  # bare origin 上有若干分支，clone 下来本地只有一个；.handoff/ 里躺着一份属于
  # 「远端独有且未合并」分支的现场文件。正确裁决是 KEEP。旧的只查本地
  # `git branch` 的 tier 1 会给出 COLLECT——那正是大规模误删事故本身。
  $freshScenario = $null
  try {
    $freshScenario = New-OriginScenario -Tag 'fresh'
    foreach ($colleague in @('feat/colleague-a', 'feat/colleague-b')) {
      & git -C $freshScenario.Seed checkout -q -b $colleague main | Out-Null
      Add-ScenarioCommit -Repo $freshScenario.Seed `
        -FileName ('{0}.md' -f ($colleague -replace '/', '-')) `
        -Message ('work on {0}' -f $colleague)
      & git -C $freshScenario.Seed push -q origin $colleague | Out-Null
    }
    & git -C $freshScenario.Seed checkout -q main | Out-Null
    $freshClone = New-ScenarioClone -Scenario $freshScenario

    $freshLocal = @(& git -C $freshClone branch --format='%(refname:short)')
    Check ($freshLocal.Count -eq 1 -and $freshLocal -contains 'main') `
      'S1 新 clone 本地只有一个分支，同事的分支只以远端追踪引用存在'

    $freshFile = Get-BranchFileName 'feat/colleague-a'
    $freshPath = Add-ScenarioHandoff -Repo $freshClone -BranchName 'feat/colleague-a' -FileName $freshFile
    $freshBranch = Get-HandoffBranchName -Path $freshPath
    Check ($freshBranch -eq 'feat/colleague-a') `
      'S1 判据输入取自现场文件 frontmatter 的完整分支名，不从文件名反推'

    $freshMain = Resolve-MainBranch -Repo $freshClone
    Check ($freshMain -eq 'main') `
      'S1 新 clone 中主干经 origin/HEAD 探测为 main'

    Check (-not (Test-BranchPresent -Repo $freshClone -BranchName $freshBranch -LocalOnly)) `
      'S1 鉴别力：只查本地的旧 tier 1 认定同事的分支「已不存在」'
    Check ((Get-HandoffVerdict -Repo $freshClone -BranchName $freshBranch -MainBranch $freshMain -Mode 'legacy-local') -eq 'COLLECT') `
      'S1 鉴别力：修复前的判据把同事正在开发的现场文件判为删除'

    Check ((Get-BranchPresentMatch -Repo $freshClone -BranchName $freshBranch) -contains 'origin/feat/colleague-a') `
      'S1 现行 tier 1 在 branch -a 输出中命中 origin/feat/colleague-a'
    Check (Test-BranchPresent -Repo $freshClone -BranchName $freshBranch) `
      'S1 本地没有、远端还有的分支不算已消失'
    Check (-not (Test-BranchMerged -Repo $freshClone -BranchName $freshBranch -MainBranch $freshMain)) `
      'S1 该分支确实未合并进主干，tier 2 不命中'
    Check ((Get-BranchIdleState -Repo $freshClone -BranchName $freshBranch) -eq 'ACTIVE') `
      'S1 tier 3 经 origin/ 短名取到提交时间，判为活跃'
    Check ((Get-HandoffVerdict -Repo $freshClone -BranchName $freshBranch -MainBranch $freshMain) -eq 'KEEP') `
      'S1 现行判据给出 KEEP，新 clone 不再误删同事的现场文件'
    Check (Test-Path -LiteralPath $freshPath) `
      'S1 场景结束时该现场文件仍在（KEEP 的实际含义）'
  } finally {
    Remove-ScenarioTree $freshScenario.Root
  }

  # --- 场景 2：推送 → 合并 → 删远端分支，之后仍必须可回收 ---
  # GitHub 的默认流程。clone 先 fetch 到 origin/<分支名>；远端合并并删除该分支后，
  # 本地只做普通 `git fetch`（不带 --prune），陈旧的 origin/<分支名> 于是留了下来。
  # 正确裁决是 COLLECT（tier 2 用 -a 命中）。只把 tier 1 放宽到 -a 的中间形态会
  # 给出 KEEP：tier 1 看见陈旧引用说「还在」，tier 2 只查本地看不见它，tier 3 拿
  # 裸名解析必然失败——三条判据同时落空，孤儿从此只增不减。
  $shippedScenario = $null
  try {
    $shippedScenario = New-OriginScenario -Tag 'shipped'
    & git -C $shippedScenario.Seed checkout -q -b 'feat/shipped' main | Out-Null
    Add-ScenarioCommit -Repo $shippedScenario.Seed -FileName 'shipped.md' -Message 'shipped work'
    & git -C $shippedScenario.Seed push -q origin 'feat/shipped' | Out-Null
    # clone 必须建在远端删除之前，才会留下一份陈旧的 origin/feat/shipped
    $shippedClone = New-ScenarioClone -Scenario $shippedScenario
    & git -C $shippedScenario.Seed checkout -q main | Out-Null
    & git -C $shippedScenario.Seed merge -q --no-ff 'feat/shipped' -m 'merge feat/shipped' | Out-Null
    & git -C $shippedScenario.Seed push -q origin main | Out-Null
    & git -C $shippedScenario.Seed push -q origin --delete 'feat/shipped' | Out-Null
    # 关键：普通 fetch，不带 --prune
    & git -C $shippedClone fetch -q origin | Out-Null
    & git -C $shippedClone merge -q --ff-only origin/main | Out-Null

    $shippedMain = Resolve-MainBranch -Repo $shippedClone
    Check ($shippedMain -eq 'main') `
      'S2 clone 中主干经 origin/HEAD 探测为 main'
    Check ((Get-BranchPresentMatch -Repo $shippedClone -BranchName 'feat/shipped') -contains 'origin/feat/shipped') `
      'S2 普通 fetch 不清理陈旧引用，origin/feat/shipped 仍留在 branch -a 输出中'
    Check (Test-BranchPresent -Repo $shippedClone -BranchName 'feat/shipped') `
      'S2 tier 1 因陈旧引用判定分支仍在，不命中（这不是缺陷，是它该有的行为）'

    Check (-not (Test-BranchMerged -Repo $shippedClone -BranchName 'feat/shipped' -MainBranch $shippedMain -LocalOnly)) `
      'S2 鉴别力：只查本地的旧 tier 2 不列远端追踪分支，不命中'
    Check ($null -eq (Resolve-BranchRevision -Repo $shippedClone -BranchName 'feat/shipped' -BareOnly)) `
      'S2 鉴别力：旧 tier 3 拿裸分支名当修订，本地 ref 已删必然解析失败'
    Check ((Get-HandoffVerdict -Repo $shippedClone -BranchName 'feat/shipped' -MainBranch $shippedMain -Mode 'legacy-wide-tier1') -eq 'KEEP') `
      'S2 鉴别力：只放宽 tier 1 时三条判据同时落空，孤儿回收变成死规则'

    Check (Test-BranchMerged -Repo $shippedClone -BranchName 'feat/shipped' -MainBranch $shippedMain) `
      'S2 现行 tier 2 用 branch -a --merged 命中 origin/feat/shipped'
    Check ((Get-HandoffVerdict -Repo $shippedClone -BranchName 'feat/shipped' -MainBranch $shippedMain) -eq 'COLLECT') `
      'S2 现行判据给出 COLLECT，GitHub 默认流程下的孤儿可以被回收'
  } finally {
    Remove-ScenarioTree $shippedScenario.Root
  }

  # --- 场景 3：只剩远端追踪引用的沉寂分支，时间判据必须解析得到 ---
  # 分支只以 refs/remotes/origin/<分支名> 存在，最后一次提交在 60 天前。正确行为：
  # <分支修订> 退到 origin/<分支名>，取到真实 ISO 时间戳，裁决 DORMANT（转入 L2）。
  # 旧的只认裸名的形态取不到任何时间戳；而 SKILL.md 的安全底线是——解析失败
  # 一律「不动作」（NOOP），绝不能读成「长期无活动」。
  $idleScenario = $null
  try {
    $idleScenario = New-OriginScenario -Tag 'idle'
    & git -C $idleScenario.Seed checkout -q -b 'feat/idle' main | Out-Null
    $idleStamp = (Get-Date).AddDays(-60).ToString('yyyy-MM-ddTHH:mm:sszzz')
    Add-ScenarioCommit -Repo $idleScenario.Seed -FileName 'idle.md' -Message 'idle work' -IsoDate $idleStamp
    & git -C $idleScenario.Seed push -q origin 'feat/idle' | Out-Null
    & git -C $idleScenario.Seed checkout -q main | Out-Null
    $idleClone = New-ScenarioClone -Scenario $idleScenario
    $idleMain = Resolve-MainBranch -Repo $idleClone

    Check ($null -eq (Resolve-BranchRevision -Repo $idleClone -BranchName 'feat/idle' -BareOnly)) `
      'S3 鉴别力：裸分支名对只剩远端追踪引用的分支解析不到'
    $idleBareLog = Invoke-GitCapture -Repo $idleClone -GitArgs @('log', '-1', '--format=%cI', 'feat/idle')
    Check ($idleBareLog.Code -eq 128) `
      'S3 鉴别力：把裸分支名直接传给 git log 会以 exit 128 失败'
    Check ($idleBareLog.Err -match 'ambiguous argument') `
      'S3 鉴别力：失败信息正是 SKILL.md 记录的 fatal: ambiguous argument'
    Check ((Get-BranchIdleState -Repo $idleClone -BranchName 'feat/idle' -BareOnly) -eq 'NOOP') `
      'S3 鉴别力：旧形态下这条沉寂分支的时间判据只能落空'

    $idleRevision = Resolve-BranchRevision -Repo $idleClone -BranchName 'feat/idle'
    Check ($idleRevision -eq 'origin/feat/idle') `
      'S3 <分支修订> 第 2 顺位退到 tier 1 命中的 origin/feat/idle'
    $idleIso = (@(& git -C $idleClone log -1 --format=%cI $idleRevision) -join '').Trim()
    Check ($idleIso -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$') `
      'S3 时间判据拿到真实 ISO 8601 提交时间，而不是报错'
    $idleAge = ([datetimeoffset]::Now - [datetimeoffset]::Parse($idleIso)).TotalDays
    Check ($idleAge -gt 14 -and $idleAge -lt 61) `
      'S3 取到的时间戳确实是 60 天前那一次提交'
    Check ((Get-BranchIdleState -Repo $idleClone -BranchName 'feat/idle') -eq 'IDLE') `
      'S3 超过 14 天，tier 3 判为 IDLE'
    Check ((Get-HandoffVerdict -Repo $idleClone -BranchName 'feat/idle' -MainBranch $idleMain) -eq 'DORMANT') `
      'S3 tier 3 命中后转入 L2 休眠流程，而不是直接删除'

    # 安全底线：两种形式都解析不到时是「不动作」，不是「无活动」。现实中 tier 1
    # 命中后修订通常都解析得到，这条守的是两次调用之间 ref 被删、或短名解析异常
    # 的情形——要点是解析失败绝不能沿用「超过 14 天」那条分支。
    Check ($null -eq (Resolve-BranchRevision -Repo $idleClone -BranchName 'feat/never-existed')) `
      'S3 裸名与 origin/ 短名都解析不到时返回 $null'
    Check ((Get-BranchIdleState -Repo $idleClone -BranchName 'feat/never-existed') -eq 'NOOP') `
      'S3 修订解析失败给出 NOOP 不动作'
    Check ((Get-BranchIdleState -Repo $idleClone -BranchName 'feat/never-existed') -ne 'IDLE') `
      'S3 修订解析失败绝不被读成「长期无活动」'
  } finally {
    Remove-ScenarioTree $idleScenario.Root
  }

  # --- 场景 4：游离 HEAD 没有分支身份 ---
  # SKILL.md 禁止用 `git rev-parse --abbrev-ref HEAD` 取当前分支名，理由是它在游离
  # HEAD 时返回字面量 HEAD，会被当成一个叫 HEAD 的分支名。这里让两条命令在同一个
  # 仓库状态上给出不同答案，「该用哪条」的鉴别力就在这个差值里。
  $detachedRoot = $null
  try {
    $detachedRoot = New-ScenarioRoot -Tag 'detached'
    $detachedRepo = Join-Path $detachedRoot 'repo'
    New-Item -ItemType Directory -Path $detachedRepo -Force | Out-Null
    Initialize-ScenarioRepo -Path $detachedRepo
    Add-ScenarioCommit -Repo $detachedRepo -FileName 'first.md' -Message 'first'
    Add-ScenarioCommit -Repo $detachedRepo -FileName 'second.md' -Message 'second'
    $detachedHead = (@(& git -C $detachedRepo rev-parse HEAD) -join '').Trim()
    & git -C $detachedRepo checkout -q --detach $detachedHead | Out-Null

    $detachedShown = Invoke-GitCapture -Repo $detachedRepo -GitArgs @('branch', '--show-current')
    Check ($detachedShown.Code -eq 0) `
      'S4 游离 HEAD 下 git branch --show-current 的 exit code 仍是 0'
    Check ($detachedShown.Out.Trim() -eq '') `
      'S4 游离 HEAD 的检测信号是输出为空串，不是 exit code'
    $detachedAbbrev = Invoke-GitCapture -Repo $detachedRepo -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD')
    Check ($detachedAbbrev.Code -eq 0 -and $detachedAbbrev.Out.Trim() -eq 'HEAD') `
      'S4 同一状态下 rev-parse --abbrev-ref HEAD 返回字面量 HEAD'
    Check ($detachedShown.Out.Trim() -ne $detachedAbbrev.Out.Trim()) `
      'S4 鉴别力：两条命令在同一状态下给出不同答案，用错那条会造出名为 HEAD 的假分支'
    $detachedNative = @(& git -C $detachedRepo branch --show-current)
    Check ($detachedNative.Count -eq 0) `
      'S4 PowerShell 下空输出不产生任何对象，判空前必须先 join 成字符串'

    & git -C $detachedRepo checkout -q main | Out-Null
    $attachedShown = Invoke-GitCapture -Repo $detachedRepo -GitArgs @('branch', '--show-current')
    Check ($attachedShown.Out.Trim() -eq 'main') `
      'S4 对照：回到 main 后 show-current 返回真实分支名，空串确由游离 HEAD 造成'
  } finally {
    Remove-ScenarioTree $detachedRoot
  }

  # --- 场景 5：主干自身的现场文件不被删除 ---
  # 仓库停在 main，`.handoff/` 里有一份 frontmatter 记 `branch: main` 的现场文件——
  # 1.x → 2.0 迁移正是在主干上刻意创建它的。`git branch -a --merged main` 的输出
  # 第一项就是 main 自己（下面的 T15 断言），因此无豁免的 tier 2 对它**每次运行
  # 都命中**，裁决 COLLECT：一份刚建出来的现场文件在下一次调用就被提炼后删除。
  # 正确裁决是 KEEP。2.0.0 的迁移那次没暴露它，只因为当时 `.handoff/` 还是空的。
  $mainSelfScenario = $null
  try {
    $mainSelfScenario = New-OriginScenario -Tag 'mainself'
    $mainSelfClone = New-ScenarioClone -Scenario $mainSelfScenario
    $mainSelfMain = Resolve-MainBranch -Repo $mainSelfClone
    Check ($mainSelfMain -eq 'main') `
      'S5 clone 中主干经 origin/HEAD 探测为 main'

    $mainSelfRevision = Resolve-MainRevision -Repo $mainSelfClone -MainBranch $mainSelfMain
    Check ($mainSelfRevision -eq 'main') `
      'S5 本地存在同名分支时 <主干修订> 第 1 顺位就是裸主干名'
    $mainSelfMerged = @(@(& git -C $mainSelfClone branch -a --merged $mainSelfRevision `
      --format='%(refname:short)') | ForEach-Object { $_.Trim() })
    Check ($mainSelfMerged -contains 'main') `
      'S5 T15：git branch -a --merged <X> 的输出包含 X 自身'

    $mainSelfFile = Get-BranchFileName 'main'
    $mainSelfPath = Add-ScenarioHandoff -Repo $mainSelfClone -BranchName 'main' `
      -FileName $mainSelfFile
    $mainSelfBranch = Get-HandoffBranchName -Path $mainSelfPath
    Check ($mainSelfBranch -eq 'main') `
      'S5 现场文件 frontmatter 记录的完整分支名即主干名'

    Check (Test-BranchMerged -Repo $mainSelfClone -BranchName $mainSelfBranch `
      -MainBranch $mainSelfMain) `
      'S5 鉴别力：撇开豁免单看 tier 2，主干确实「已合并进主干」，判据命中'
    Check ((Get-HandoffVerdict -Repo $mainSelfClone -BranchName $mainSelfBranch `
      -MainBranch $mainSelfMain -Mode 'legacy-no-main-exempt') -eq 'COLLECT') `
      'S5 鉴别力：修复前的判据把主干自己的现场文件判为删除'

    Check ((Get-HandoffVerdict -Repo $mainSelfClone -BranchName $mainSelfBranch `
      -MainBranch $mainSelfMain) -eq 'KEEP') `
      'S5 现行判据给出 KEEP，主干自身的现场文件豁免 tier 2/3 与 L2'
    Check (Test-Path -LiteralPath $mainSelfPath) `
      'S5 场景结束时主干的现场文件仍在（KEEP 的实际含义）'

    # 护栏：豁免只针对主干那一份。同一个仓库里一条已合并进主干的功能分支
    # 必须照旧被 tier 2 命中，否则这次修复就把 tier 2 整条放宽掉了。
    & git -C $mainSelfClone checkout -q -b 'feat/merged-into-main' main | Out-Null
    Add-ScenarioCommit -Repo $mainSelfClone -FileName 'merged-into-main.md' `
      -Message 'feature work'
    & git -C $mainSelfClone checkout -q main | Out-Null
    & git -C $mainSelfClone merge -q --no-ff 'feat/merged-into-main' `
      -m 'merge feat/merged-into-main' | Out-Null
    Check (Test-BranchMerged -Repo $mainSelfClone -BranchName 'feat/merged-into-main' `
      -MainBranch $mainSelfMain) `
      'S5 护栏：功能分支合并进主干后 tier 2 仍然命中'
    Check ((Get-HandoffVerdict -Repo $mainSelfClone -BranchName 'feat/merged-into-main' `
      -MainBranch $mainSelfMain) -eq 'COLLECT') `
      'S5 护栏：主干豁免不外溢，已合并的功能分支照旧判为 COLLECT'
  } finally {
    Remove-ScenarioTree $mainSelfScenario.Root
  }

  # --- 场景 6：主干名不可解析为本地修订时 tier 2 仍须工作 ---
  # 本地主干叫 master，远端叫 main：探测链第 2 级从 refs/remotes/origin/main 得出
  # 裸名 `main`，而本地根本没有这个分支。把裸名直接传给
  # `git branch -a --merged main` 会 exit 128 + fatal: malformed object name，
  # 输出为空 —— tier 2 于是**静默**返回「未合并」，一条真正已合并的孤儿分支
  # 永远回收不掉。正确行为：<主干修订> 退到 origin/main，tier 2 恢复工作。
  # 注意：本场景运行时控制台会出现两行 `fatal: malformed object name main`，
  # 那是下面两处 -BareMain 鉴别力断言**故意**触发的真实 git 报错，不是测试失败；
  # 它正是这个缺陷的现场——判据看到的只有一个空 stdout，看不到这行 stderr。
  $mainRevScenario = $null
  try {
    $mainRevRoot = New-ScenarioRoot -Tag 'mainrev'
    $mainRevOrigin = Join-Path $mainRevRoot 'origin.git'
    & git init -q --bare $mainRevOrigin | Out-Null
    & git -C $mainRevOrigin symbolic-ref HEAD refs/heads/main | Out-Null
    $mainRevRepo = Join-Path $mainRevRoot 'repo'
    New-Item -ItemType Directory -Path $mainRevRepo -Force | Out-Null
    & git init -q $mainRevRepo | Out-Null
    # 本地主干叫 master，与远端的 main 不同名——这正是本场景的全部要害
    & git -C $mainRevRepo symbolic-ref HEAD refs/heads/master | Out-Null
    & git -C $mainRevRepo config user.email 'test@example.com' | Out-Null
    & git -C $mainRevRepo config user.name 'sync-test' | Out-Null
    & git -C $mainRevRepo config core.autocrlf false | Out-Null
    Add-ScenarioCommit -Repo $mainRevRepo -FileName 'seed.md' -Message 'init'
    & git -C $mainRevRepo checkout -q -b 'feat/merged-remote' | Out-Null
    Add-ScenarioCommit -Repo $mainRevRepo -FileName 'remote-merged.md' -Message 'shipped work'
    & git -C $mainRevRepo checkout -q master | Out-Null
    & git -C $mainRevRepo merge -q --no-ff 'feat/merged-remote' `
      -m 'merge feat/merged-remote' | Out-Null
    & git -C $mainRevRepo remote add origin $mainRevOrigin | Out-Null
    & git -C $mainRevRepo push -q origin 'master:refs/heads/main' | Out-Null
    & git -C $mainRevRepo push -q origin 'feat/merged-remote:refs/heads/feat/merged-remote' | Out-Null
    & git -C $mainRevRepo fetch -q origin | Out-Null
    # 本地删掉功能分支，只留远端追踪引用：tier 1 仍判「分支还在」，判定会走到 tier 2
    & git -C $mainRevRepo branch -D 'feat/merged-remote' | Out-Null
    $mainRevScenario = [pscustomobject]@{ Root = $mainRevRoot; Repo = $mainRevRepo }

    $mainRevMain = Resolve-MainBranch -Repo $mainRevRepo
    Check ($mainRevMain -eq 'main') `
      'S6 探测链第 2 级从 origin/main 得出裸主干名 main'
    & git -C $mainRevRepo rev-parse --verify --quiet refs/heads/main | Out-Null
    Check ($LASTEXITCODE -ne 0) `
      'S6 本地并不存在名为 main 的分支，裸名无从解析'
    Check (Test-BranchPresent -Repo $mainRevRepo -BranchName 'feat/merged-remote') `
      'S6 tier 1 经 origin/feat/merged-remote 判定该分支仍在，判定会走到 tier 2'

    $mainRevBare = Invoke-GitCapture -Repo $mainRevRepo `
      -GitArgs @('branch', '-a', '--merged', 'main', '--format=%(refname:short)')
    Check ($mainRevBare.Code -eq 128) `
      'S6 鉴别力：裸主干名直接传给 branch -a --merged 以 exit 128 失败'
    Check ($mainRevBare.Err -match 'malformed object name') `
      'S6 鉴别力：失败信息正是设计 §10 第 6 条记录的 malformed object name'
    Check ([string]::IsNullOrWhiteSpace($mainRevBare.Out)) `
      'S6 鉴别力：失败时 stdout 为空，判据看不出这是错误还是「没合并」'
    Check ($null -eq (Resolve-MainRevision -Repo $mainRevRepo -MainBranch $mainRevMain -BareOnly)) `
      'S6 鉴别力：只认裸名的旧形态解析不到主干修订'
    Check (-not (Test-BranchMerged -Repo $mainRevRepo -BranchName 'feat/merged-remote' `
      -MainBranch $mainRevMain -BareMain)) `
      'S6 鉴别力：修复前 tier 2 对一条真正已合并的分支静默返回「未合并」'
    Check ((Get-HandoffVerdict -Repo $mainRevRepo -BranchName 'feat/merged-remote' `
      -MainBranch $mainRevMain -Mode 'legacy-bare-main') -eq 'KEEP') `
      'S6 鉴别力：修复前该孤儿现场文件永远回收不掉'

    Check ((Resolve-MainRevision -Repo $mainRevRepo -MainBranch $mainRevMain) -eq 'origin/main') `
      'S6 <主干修订> 第 2 顺位退到 origin/main'
    Check (Test-BranchMerged -Repo $mainRevRepo -BranchName 'feat/merged-remote' `
      -MainBranch $mainRevMain) `
      'S6 现行 tier 2 用 <主干修订> 命中已合并进远端主干的分支'
    Check ((Get-HandoffVerdict -Repo $mainRevRepo -BranchName 'feat/merged-remote' `
      -MainBranch $mainRevMain) -eq 'COLLECT') `
      'S6 现行判据给出 COLLECT，本地主干异名时孤儿回收恢复工作'

    # 安全底线：两种形式都解析不到时是「跳过 tier 2」，不是「已合并」。
    Check ($null -eq (Resolve-MainRevision -Repo $mainRevRepo -MainBranch 'trunk-never-existed')) `
      'S6 裸名与 <remote>/<主干名> 都解析不到时返回 $null（跳过 tier 2 并报告）'
    Check (-not (Test-BranchMerged -Repo $mainRevRepo -BranchName 'feat/merged-remote' `
      -MainBranch 'trunk-never-existed')) `
      'S6 跳过 tier 2 时不产出 tier 2 决议，绝不据此删除'
  } finally {
    Remove-ScenarioTree $mainRevScenario.Root
  }

  # 零残留核对：本节全部场景目录都建在 $env:TEMP 下，且都已在 finally 中删除
  $scenarioResidue = @($script:scenarioRoot | Where-Object { Test-Path -LiteralPath $_ })
  Check ($scenarioResidue.Count -eq 0) `
    ('S0 本节建立的 {0} 个临时场景目录已全部清理，无残留' -f @($script:scenarioRoot).Count)
}

if ($script:fail -gt 0) {
  Write-Host "`n$script:fail 项失败"
  exit 1
}

Write-Host "`n全部通过"
exit 0
