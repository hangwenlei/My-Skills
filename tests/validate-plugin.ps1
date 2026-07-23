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
        $sourcePath = Join-Path $root ($entry.source -replace '/', '\\')
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

if (Should-Run 'sync') {
  $skill = Join-Path $root 'plugins\sync\skills\docs\SKILL.md'
  Check (Test-Path -LiteralPath $skill) 'sync SKILL.md 存在'
  if (Test-Path -LiteralPath $skill) {
    $content = Get-Content -LiteralPath $skill -Raw -Encoding UTF8
    Check ($content -match '(?m)^name:\s*docs\s*$') 'sync SKILL.md name = docs'
    Check ($content -match 'disable-model-invocation:\s*true') 'sync SKILL.md disable-model-invocation = true'
    Check ($content -match 'HANDOFF\.md') 'sync SKILL.md 提及 HANDOFF.md'
    Check ($content -match '可收敛') 'sync SKILL.md 步骤4 含去重类型「可收敛」'
    Check ($content -match '可合并') 'sync SKILL.md 步骤4 含去重类型「可合并」'
    Check ($content -match '日志型') 'sync SKILL.md 步骤4 含日志型跳过规则'
    Check ($content -match '同一事实只写一条') 'sync SKILL.md 步骤2 含 HANDOFF 自身去重'
  }
}

if (Should-Run 'docs') {
  $readme = Join-Path $root 'README.md'
  Check (Test-Path -LiteralPath $readme) 'README.md 存在'
}

if ($script:fail -gt 0) {
  Write-Host "`n$script:fail 项失败"
  exit 1
}

Write-Host "`n全部通过"
exit 0
