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
