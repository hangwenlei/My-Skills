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

if ($script:fail -gt 0) {
  Write-Host "`n$script:fail 项失败"
  exit 1
}

Write-Host "`n全部通过"
exit 0
