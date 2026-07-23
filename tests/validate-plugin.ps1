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
    Check ($content -match '(?m)^- Git 项目在应用确认项后.*`git diff`') `
      'sync Git 项目确认后读取实际 diff'
    Check ($content -match '(?m)^- 非 Git 项目禁止执行 Git 命令；') `
      'sync 非 Git 项目全程禁止 Git 命令'
    Check ($content -match '\*\*修改前 UTF-8 快照\*\*') `
      'sync 非 Git 项目使用 UTF-8 前后快照'
    Check ($content -notmatch '(?m)^- 完成确认项后.*`git diff`') `
      'sync 移除无条件 git diff 要求'
  }

  if (Test-Path -LiteralPath $openaiPath) {
    $openai = Get-Content -LiteralPath $openaiPath -Raw -Encoding UTF8
    Check ($openai -match 'allow_implicit_invocation:\s*false') 'sync 禁止 Codex 隐式调用'
    Check ($openai -match '\$sync:docs') 'sync 默认提示包含显式入口'
  }
}

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

if ($script:fail -gt 0) {
  Write-Host "`n$script:fail 项失败"
  exit 1
}

Write-Host "`n全部通过"
exit 0
