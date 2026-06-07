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
