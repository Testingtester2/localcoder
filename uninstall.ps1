<#
  Removes everything install.ps1 added. Nothing outside this folder and Docker is touched.
    .\uninstall.ps1             # removes llama.cpp, key, sandbox image and volumes, keeps models
    .\uninstall.ps1 -Models     # also deletes the downloaded models
#>
param([switch]$Models)
$Root = $PSScriptRoot
function Say($m) { Write-Host "[kit] $m" -ForegroundColor Cyan }

if (Get-Command docker -ErrorAction SilentlyContinue) {
    & docker image rm localcoder:1 2>$null | Out-Null
    & docker volume rm localcoder-data localcoder-cache 2>$null | Out-Null
    Say 'removed Docker image localcoder:1 and its volumes'
}
foreach ($p in 'llama.cpp', 'llm.key') {
    $full = Join-Path $Root $p
    if (Test-Path $full) { Remove-Item -Recurse -Force $full; Say "removed $p" }
}
if ($Models -and (Test-Path (Join-Path $Root 'models'))) {
    Remove-Item -Recurse -Force (Join-Path $Root 'models'); Say 'removed models'
}
Say 'done. You can now delete this folder.'
