<#
  Opens OpenCode on one project folder inside the Docker sandbox.
    Start-Agent.bat "C:\code\my-project"
  The container sees only that folder (mounted at /work). It cannot see the rest of
  your drives or run Windows programs. Start the model server first (Start-LLM.bat).
#>
param([Parameter(Position = 0)][string]$Project)
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
if (-not $Project) { $Project = Read-Host 'Project folder to open' }
$Project = $Project.Trim('"')
if (-not (Test-Path -LiteralPath $Project -PathType Container)) { Write-Host "Folder not found: $Project" -ForegroundColor Red; exit 1 }
$Project = (Resolve-Path -LiteralPath $Project).Path
$blocked = @($env:USERPROFILE, "$env:SystemDrive\", $env:SystemRoot, $Root) | ForEach-Object { $_.TrimEnd('\') }
if ($blocked -contains $Project.TrimEnd('\')) { Write-Host "Refusing to mount $Project. Pick a single project folder." -ForegroundColor Red; exit 1 }

$keyFile = Join-Path $Root 'llm.key'
if (-not (Test-Path $keyFile)) { Write-Host 'llm.key missing. Run Install.bat first.' -ForegroundColor Red; exit 1 }
$env:LLM_KEY = (Get-Content $keyFile -Raw).Trim()

try { $null = Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 'http://127.0.0.1:8080/health' }
catch { Write-Host 'Model server is not running on 127.0.0.1:8080. Start Start-LLM.bat first.' -ForegroundColor Yellow }

Write-Host "Sandbox sees ONLY: $Project" -ForegroundColor Cyan
& docker run -it --rm `
    -e LLM_KEY `
    -v "${Project}:/work" `
    -v localcoder-data:/home/coder/.local/share/opencode `
    -v localcoder-cache:/home/coder/.cache/opencode `
    --cap-drop ALL --security-opt no-new-privileges `
    --pids-limit 512 --memory 8g `
    localcoder:1
