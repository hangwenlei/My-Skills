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

function Remove-Whitespace($text) {
  return ($text -replace '\s+', '')
}

function Remove-Markup($text) {
  # 同时去掉空白、markdown 强调符与反引号；保留下划线，它出现在标识符里
  return ($text -replace '[\s*`]', '')
}

function Test-YamlPolicyFalse($text, $key) {
  $inPolicy = $false
  $directIndent = $null
  foreach ($line in @($text -split '\r?\n')) {
    if ($line -eq 'policy:') {
      $inPolicy = $true
      continue
    }
    if ($inPolicy -and $line -match '^\S') {
      return $false
    }
    if (-not $inPolicy -or [string]::IsNullOrWhiteSpace($line) -or
        $line -match '^\s*#') {
      continue
    }
    $indentMatch = [regex]::Match($line, '^(?<indent>[ \t]+)')
    if (-not $indentMatch.Success) {
      return $false
    }
    $indent = $indentMatch.Groups['indent'].Value.Length
    if ($null -eq $directIndent) {
      $directIndent = $indent
    }
    if ($indent -eq $directIndent -and
        $line -match "^[ \t]{$directIndent}$([regex]::Escape($key)):\s*false\s*$") {
      return $true
    }
  }
  return $false
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
    $claudeNames = @($claudeCatalog.plugins.name)
    Check ($claudeNames.Count -eq 2 -and
           @($claudeNames | Where-Object {
             $_ -notin @('chinese', 'sync')
           }).Count -eq 0) `
      'Claude marketplace 仅登记唯一 chinese 与 sync'
    foreach ($expected in @('chinese', 'sync')) {
      $entries = @(
        $claudeCatalog.plugins | Where-Object { $_.name -eq $expected }
      )
      Check ($entries.Count -eq 1) "Claude marketplace 唯一登记 $expected"
      if ($entries.Count -eq 1) {
        $entry = $entries[0]
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
    $codexNames = @($codexCatalog.plugins.name)
    Check ($codexNames.Count -eq 2 -and
           @($codexNames | Where-Object {
             $_ -notin @('chinese', 'sync')
           }).Count -eq 0) `
      'Codex marketplace 仅登记唯一 chinese 与 sync'
    foreach ($expected in @('chinese', 'sync')) {
      $entries = @(
        $codexCatalog.plugins | Where-Object { $_.name -eq $expected }
      )
      Check ($entries.Count -eq 1) "Codex marketplace 唯一登记 $expected"
      if ($entries.Count -eq 1) {
        $entry = $entries[0]
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
    @{ Name = 'sync'; Version = '2.0.1' }
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
    Check (([regex]::Matches(
      $claudeContent,
      '\$\{CLAUDE_PLUGIN_ROOT\}/codex/skills/init/SKILL\.md'
    )).Count -eq 1) 'chinese Claude 薄入口只引用共享核心一次'
  }

  if (Test-Path -LiteralPath $codexSkillPath) {
    $content = Get-Content -LiteralPath $codexSkillPath -Raw -Encoding UTF8
    $normalized = Remove-Whitespace $content
    Check ($content -notmatch '(?m)^disable-model-invocation:') `
      'chinese Codex 核心无 Claude-only disable-model-invocation'
    Check ($content -notmatch '(?m)^allowed-tools:') `
      'chinese Codex 核心无宿主专属 allowed-tools'
    Check ($content -match '\$chinese:init') 'chinese 核心包含 Codex 显式入口'
    Check ($content -match '/chinese:init') 'chinese 核心包含 Claude 薄入口契约'
    Check ($content -match 'git rev-parse --show-toplevel') 'chinese 会定位 Git 项目根'
    Check ($content -match 'AGENTS\.md') 'chinese 包含 Codex AGENTS 分支'
    Check ($content -match '单边哨兵') 'chinese 会保护损坏哨兵'
    Check ($normalized.Contains(
      '只有在开始哨兵和结束哨兵各恰好出现一次，且开始哨兵位于结束哨兵之前时，才替换完整区块。')) `
      'chinese 仅替换唯一且有序的哨兵区块'
    Check ($content -match '平台速查') 'chinese 含平台速查'
    Check ($content -match '常见错误') 'chinese 含常见错误'
  }

  if (Test-Path -LiteralPath $openaiPath) {
    $openai = Get-Content -LiteralPath $openaiPath -Raw -Encoding UTF8
    Check (Test-YamlPolicyFalse $openai 'allow_implicit_invocation') `
      'chinese policy 结构禁止 Codex 隐式调用'
    Check ($openai -match '\$chinese:init') 'chinese 默认提示包含显式入口'
  }
}

if (Should-Run 'sync') {
  $claudeSkillPath = Join-Path $root 'plugins\sync\skills\docs\SKILL.md'
  $claudeManifestPath = Join-Path $root 'plugins\sync\.claude-plugin\plugin.json'
  $codexManifestPath = Join-Path $root 'plugins\sync\codex\.codex-plugin\plugin.json'
  if ((Test-Path -LiteralPath $claudeManifestPath) -and
      (Test-Path -LiteralPath $codexManifestPath)) {
    $claudeManifest = Read-JsonUtf8 $claudeManifestPath
    $codexManifest = Read-JsonUtf8 $codexManifestPath
    Check ($claudeManifest.version -eq '2.0.1') 'sync Claude 清单版本为 2.0.1'
    Check ($codexManifest.version -eq '2.0.1') 'sync Codex 清单版本为 2.0.1'
    Check ($claudeManifest.version -eq $codexManifest.version) `
      'sync 双平台清单版本一致'
  }
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
    Check (([regex]::Matches(
      $claudeContent,
      '\$\{CLAUDE_PLUGIN_ROOT\}/codex/skills/docs/SKILL\.md'
    )).Count -eq 1) 'sync Claude 薄入口只引用共享核心一次'
  }

  if (Test-Path -LiteralPath $codexSkillPath) {
    $content = Get-Content -LiteralPath $codexSkillPath -Raw -Encoding UTF8
    $normalized = Remove-Whitespace $content
    $evidenceGateIndex = $content.IndexOf('## 敏感信息与证据读取闸门')
    $collectionStepIndex = $content.IndexOf('## 步骤 1：收集现场状态')
    Check ($content -notmatch '(?m)^disable-model-invocation:') `
      'sync Codex 核心无 Claude-only disable-model-invocation'
    Check ($content -notmatch '(?m)^allowed-tools:') `
      'sync Codex 核心无宿主专属 allowed-tools'
    Check ($content -match '\$sync:docs') 'sync 核心包含 Codex 显式入口'
    Check ($content -match '/sync:docs') 'sync 核心包含 Claude 薄入口契约'
    Check ($content -match 'git rev-parse --show-toplevel') 'sync 会定位 Git 项目根'
    Check ($content -match '实时 Git、测试和文件状态') 'sync 定义证据优先级'
    Check ($content -match 'sync:docs start') 'sync 定义 AGENTS 哨兵'
    Check ($normalized.Contains(
      '只有在开始哨兵和结束哨兵各恰好出现一次，且开始哨兵位于结束哨兵之前时，才替换完整区块。')) `
      'sync 仅替换唯一且有序的哨兵区块'
    Check ($content -match '平台速查') 'sync 含平台速查'
    Check ($content -match '常见错误') 'sync 含常见错误'
    Check ($content -match '可收敛') 'sync 保留可收敛'
    Check ($content -match '可合并') 'sync 保留可合并'
    Check ($content -match '日志型') 'sync 保留日志型跳过'
    Check ($content -match '同一事实只写一条') 'sync 保留 HANDOFF 去重'
    Check ($evidenceGateIndex -ge 0 -and
           $collectionStepIndex -ge 0 -and
           $evidenceGateIndex -lt $collectionStepIndex) `
      'sync 在收集现场前建立敏感信息与证据读取闸门'
    Check ($normalized.Contains(
      '该保护必须发生在任何原始diff正文或测试stdout/stderr进入任务上下文或用户输出之前。')) `
      'sync 在原始内容进入上下文前保护'
    Check ($normalized.Contains(
      '默认只读取不含正文的安全元数据，包括status、name-status、stat和numstat。')) `
      'sync 默认只读取安全元数据'
    Check ($content -match [regex]::Escape(
      '`git log --format="%h %ad" --date=short -15`')) `
      'sync 默认提交历史仅含 hash 与日期'
    Check ($content -notmatch '(?m)^- `git log --oneline -15`\s*$') `
      'sync 默认提交历史不读取 subject'
    Check ($normalized.Contains(
      '需要commitsubject时，必须复用同一本地调用内捕获、扫描、脱敏的证据闸门。')) `
      'sync commit subject 复用证据读取闸门'
    Check ($normalized.Contains(
      '禁止把原始diff正文或测试stdout/stderr直接返回任务上下文或用户。')) `
      'sync 禁止直接返回原始 diff 与测试输出'
    Check ($normalized.Contains(
      '需要内容时，必须在同一个本地命令或工具调用内捕获原始输出、完成敏感扫描与脱敏，并且只返回脱敏结果。')) `
      'sync 要求同调用内完成过滤'
    Check ($normalized.Contains(
      '原始输出只能留在该本地进程的内存或系统临时文件中；临时文件必须在finally中安全删除并做删除后断言。')) `
      'sync 限制 raw 暂存并要求 finally 清理'
    Check ($normalized.Contains(
      '在WindowsPowerShell5.1中不要依赖直接`2>&1`作为隔离边界；应使用`System.Diagnostics.Process`重定向标准输出和错误，或使用等价的可靠本地捕获。')) `
      'sync 避免 PowerShell 5.1 native stderr 提前泄露'
    Check ($normalized.Contains(
      '如果没有可靠的本地过滤能力，跳过原始内容读取，只基于安全元数据继续并明确报告限制；绝不降级为直接输出。')) `
      'sync 无可靠过滤时禁止降级'
    Check ($content -notmatch
      '(?m)^- `git diff` 与 `git diff --staged`\s*$') `
      'sync 默认收集不直接读取 raw diff'
    Check ($normalized.Contains(
      '不得把token、密码、私钥、连接串、带凭据URL、订阅链接、cookie或session等敏感值写入HANDOFF.md、其它文档或用户可见摘要。')) `
      'sync 禁止持久化或复述敏感值'
    Check ($normalized.Contains(
      '只记录存在敏感配置、所在文件和需要人工处理，不记录或复述具体值；无法判断时按敏感信息处理并脱敏。')) `
      'sync 对敏感信息只记录位置并默认脱敏'
    Check ($content -match '(?m)^- 非 Git 项目禁止执行 Git 命令；') `
      'sync 非 Git 项目全程禁止 Git 命令'
    Check ($content -match '\*\*修改前 UTF-8 快照\*\*') `
      'sync 非 Git 项目使用 UTF-8 前后快照'

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
    Check ($content -match 'git branch -a --merged') `
      'sync 2.0 用 merged 判据识别已完成分支'
    Check ($markup -match "frontmatter记录的分支已不在gitbranch") `
      'sync 2.0 孤儿判据以分支是否存在为主判据'
    # 远端删除分支后 origin/<name> 不 prune 就一直留在 git branch -a 里；
    # 三级判据必须都能处理远端限定名，否则最常见的 GitHub 流程永远回收不掉
    Check ($markup.Contains('gitfetch--prune')) `
      'sync 2.0 说明远端追踪引用需 prune 才消失'
    Check ($content -match 'git rev-parse --verify --quiet') `
      'sync 2.0 用 rev-parse 判定分支修订是否可解析'
    # 2.0.1：任何分支都平凡地「已合并进它自己」，`branch -a --merged <主干>` 的输出
    # 必然含主干本身，tier 2 会在每次运行时判主干自己的现场文件为删除
    Check ($markup.Contains('主干自身的现场文件豁免tier2、tier3与全部L2')) `
      'sync 2.0.1 主干自身的现场文件豁免 tier 2、tier 3 与 L2'
    # 2.0.1：探测链第 1/2 级从远端返回裸主干名，本地无同名分支时
    # `branch -a --merged main` 以 exit 128 静默失效，tier 2 从此不再触发
    Check ($markup.Contains('<主干修订>的解析顺序')) `
      'sync 2.0.1 定义 <主干修订> 的解析顺序'
    Check ($markup.Contains('该条时间判据视为未命中，本轮对该文件不做任何动作')) `
      'sync 2.0 修订解析失败时时间判据不动作'
    Check ($markup.Contains('|shasum|cut-c1-6')) `
      'sync 2.0 为 macOS 提供 shasum 回退'
    Check ($markup.Contains('禁止先写成.ps1文件再运行')) `
      'sync 2.0 禁止把哈希片段落成无 BOM 脚本'
    Check ($content -match 'git branch --show-current') `
      'sync 2.0 给出获取当前分支名的命令'
    Check ($markup.Contains('不要用gitrev-parse--abbrev-refHEAD')) `
      'sync 2.0 禁止用 abbrev-ref 取分支名'
    Check ($markup.Contains('游离HEAD的退化')) `
      'sync 2.0 定义游离 HEAD 的退化'
    Check ($markup.Contains('禁止用commitSHA顶替分支名去拼文件名')) `
      'sync 2.0 禁止用 commit SHA 拼现场文件名'
    Check ($markup -match '(禁止|不得)使用文件mtime') `
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
    Check ($content -notmatch '(?m)^> 更新时间：<当前日期时间>') `
      'sync 2.0 稳定层模板不再要求全局更新时间戳'
    Check ($markup -notmatch '整体重写该文件，不追加') `
      'sync 2.0 不再保留 1.x 的单文件快照式重写指令'
    Check ($content -notmatch '应用 1,3') `
      'sync 2.0 不再保留二阶段确认入口'
  }

  if (Test-Path -LiteralPath $openaiPath) {
    $openai = Get-Content -LiteralPath $openaiPath -Raw -Encoding UTF8
    Check (Test-YamlPolicyFalse $openai 'allow_implicit_invocation') `
      'sync policy 结构禁止 Codex 隐式调用'
    $nestedPolicyFixture = @"
policy:
  nested:
    allow_implicit_invocation: false
"@
    $nestedPolicyAccepted = Test-YamlPolicyFalse `
      $nestedPolicyFixture 'allow_implicit_invocation'
    Check (-not $nestedPolicyAccepted) `
      'sync policy helper 拒绝 nested 假阳性'
    Check ($openai -match '\$sync:docs') 'sync 默认提示包含显式入口'
  }
}

if (Should-Run 'docs') {
  $agentsPath = Join-Path $root 'AGENTS.md'
  $claudePath = Join-Path $root 'CLAUDE.md'
  $settingsPath = Join-Path $root '.claude\settings.json'
  $readmePath = Join-Path $root 'README.md'
  $designPath = Join-Path $root `
    'docs\superpowers\specs\2026-07-23-claude-codex-dual-compat-design.md'
  $planPath = Join-Path $root `
    'docs\superpowers\plans\2026-07-23-claude-codex-dual-compat.md'
  $verificationPath = Join-Path $root `
    'docs\superpowers\verification\2026-07-23-claude-codex-skill-tests.md'
  Check (Test-Path -LiteralPath $agentsPath) 'AGENTS.md 存在'
  Check (Test-Path -LiteralPath $claudePath) 'CLAUDE.md 存在'
  Check (Test-Path -LiteralPath $settingsPath) '.claude/settings.json 存在'
  Check (Test-Path -LiteralPath $readmePath) 'README.md 存在'
  Check (Test-Path -LiteralPath $designPath) '双平台设计文档存在'
  Check (Test-Path -LiteralPath $planPath) '双平台实施计划存在'
  Check (Test-Path -LiteralPath $verificationPath) '双平台验证证据存在'

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
    # 迁移前：裸 @HANDOFF.md 独占行本身就是文件最后一行
    # 迁移后：sync:docs 哨兵区块是文件结尾，裸 @HANDOFF.md 独占行位于区块内
    # 两种形态都算「在文件末尾挂载」，否则本仓库自迁移后这条断言必然失败
    $claudeTail = $claude.TrimEnd()
    $claudeBareTail = $claudeTail.EndsWith('@HANDOFF.md')
    $claudeSentinel = [regex]::Match(
      $claudeTail,
      '(?s)<!-- sync:docs start -->(?<body>.*?)<!-- sync:docs end -->')
    $claudeSentinelTail = $claudeTail.EndsWith('<!-- sync:docs end -->') -and
      $claudeSentinel.Success -and
      ($claudeSentinel.Groups['body'].Value -match '(?m)^@HANDOFF\.md[ \t]*\r?$')
    Check ($claudeBareTail -or $claudeSentinelTail) `
      'CLAUDE 在文件末尾挂载 HANDOFF'
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
    Check ($readme -match '升级后需新开 Codex 任务') `
      'README 明确 Codex 升级后新开任务'
    Check ($readme -match '\.handoff/') 'README 说明分支现场目录'
    Check ($readme -match '协同看板') 'README 说明协同看板'
    Check ($readme -match '主干分支') 'README 说明老项目迁移需在主干执行'
    Check ($readme -match 'language.*chinese') 'README 保留 chinese 核心功能说明'
    Check ($readme -match '不自动 commit') 'README 明确 skill 不自动 commit'
  }

  if (Test-Path -LiteralPath $designPath) {
    $design = Get-Content -LiteralPath $designPath -Raw -Encoding UTF8
    $designNormalized = Remove-Whitespace $design
    Check ($design -notmatch '实施计划待执行') '设计状态不再声称实施计划待执行'
    Check ($designNormalized.Contains(
      '状态：双平台实现、远端发布、本机Codex升级和Codexruntimesmoke已完成；Clauderuntimesmoke因CLI未安装而未执行')) `
      '设计状态反映发布、升级与 Codex runtime 已完成及 Claude runtime 未执行'
    Check ($designNormalized.Contains(
      '默认只读取不含正文的安全元数据')) `
      '设计默认只收集不含正文的安全元数据'
    Check ($designNormalized.Contains(
      'rawdiff或测试输出只有在同一个本地调用内完成捕获、扫描和完整脱敏后才能返回')) `
      '设计要求 raw 证据在同一本地调用内完整脱敏'
    Check ($designNormalized.Contains(
      '过滤、子命令或清理失败时failclosed，不回显raw内容')) `
      '设计定义敏感证据失败时 fail closed'
    Check ($designNormalized -notmatch
      '读取`gitstatus`、未暂存与已暂存diff') `
      '设计不再无条件读取 staged/unstaged raw diff'
    Check ($designNormalized -notmatch
      '完成后实际读取并摘要相关`gitdiff`') `
      '设计不再要求完成后直接读取并摘要 raw git diff'
  }

  foreach ($portableDocument in @(
    @{ Label = '实施计划'; Path = $planPath }
    @{ Label = '验证证据'; Path = $verificationPath }
    @{ Label = 'sync 2.0 实施计划'; Path = (Join-Path $root `
        'docs\superpowers\plans\2026-09-01-sync-v2-layered-handoff.md') }
  )) {
    if (Test-Path -LiteralPath $portableDocument.Path) {
      $portableContent = Get-Content -LiteralPath $portableDocument.Path `
        -Raw -Encoding UTF8
      Check ($portableContent -notmatch '(?i)[A-Z]:\\Users\\') `
        "$($portableDocument.Label) 不含反斜杠机器用户路径"
      Check ($portableContent -notmatch '(?i)[A-Z]:/Users/') `
        "$($portableDocument.Label) 不含正斜杠机器用户路径"
      Check ($portableContent -notmatch '(?<!\d)82370(?!\d)') `
        "$($portableDocument.Label) 不含机器用户名片段"
    }
  }
}

if ($script:fail -gt 0) {
  Write-Host "`n$script:fail 项失败"
  exit 1
}

Write-Host "`n全部通过"
exit 0
