<#
  Starts llama-server on 127.0.0.1:8080 (this PC only, needs the key in llm.key).
    Start-LLM.bat                      # first downloaded model that fits your GPU
    Start-LLM.bat qwen3.6-35b-a3b      # pick a model by id (see config\models.json)
    Start-LLM.bat qwen3.8-27b-q6 -Ctx 32768
    Start-LLM.bat qwen3.8-27b-q6 -Mtp  # experimental speed head
  Close the window (or Ctrl+C) to stop it and free the VRAM.
#>
param(
    [Parameter(Position = 0)][string]$Model,
    [int]$Ctx = 0,
    [int]$Port = 8080,
    [switch]$Mtp
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $Root 'llama.cpp\llama-server.exe'
if (-not (Test-Path $exe)) { Write-Host 'llama.cpp is not installed. Run Install.bat first.' -ForegroundColor Red; exit 1 }
$keyFile = Join-Path $Root 'llm.key'
if (-not (Test-Path $keyFile)) { Write-Host 'llm.key missing. Run Install.bat first.' -ForegroundColor Red; exit 1 }
$key = (Get-Content $keyFile -Raw).Trim()
$catalog = Get-Content (Join-Path $Root 'config\models.json') -Raw | ConvertFrom-Json
$vramGB = [math]::Round([int](& nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | Select-Object -First 1) / 1024)

function Have($id) { $m = $catalog.$id; $m -and $m.ctx -and (Test-Path (Join-Path $Root ('models\' + (Split-Path $m.file -Leaf)))) }
if (-not $Model) {
    $order = if ($vramGB -ge 28) { 'qwen3.8-27b-q6', 'qwen3.8-27b-q4', 'qwen3.6-35b-a3b' } else { 'qwen3.8-27b-q4', 'qwen3.6-35b-a3b', 'qwen3.8-27b-q6' }
    $Model = $order | Where-Object { Have $_ } | Select-Object -First 1
    if (-not $Model) { Write-Host 'No model downloaded. Run Install.bat first.' -ForegroundColor Red; exit 1 }
}
if (-not (Have $Model)) { Write-Host "Model '$Model' is not downloaded. Run: .\install.ps1 -Models $Model" -ForegroundColor Red; exit 1 }
$m = $catalog.$Model
if ($Ctx -le 0) { $Ctx = if ($vramGB -lt 28 -and $m.ctxSmallCard) { [int]$m.ctxSmallCard } else { [int]$m.ctx } }
$file = Join-Path $Root ('models\' + (Split-Path $m.file -Leaf))

$argv = @(
    '-m', $file, '--alias', 'local-coder',
    '--jinja',                      # needed for tool calls
    '-ngl', '99', '-fa', 'on',
    '-c', "$Ctx",
    '-ctk', 'q8_0', '-ctv', 'q8_0', # q8 KV cache; q4 hurts tool calls
    '--host', '127.0.0.1', '--port', "$Port",
    '--api-key', $key,
    '--no-webui-mcp-proxy',
    '--temp', '0.6', '--top-p', '0.95', '--top-k', '20', '--min-p', '0', '--presence-penalty', '0'
)
if ($Mtp) {
    $draft = Join-Path $Root 'models\mtp-Qwen3.8-27B-Q4_0.gguf'
    if (-not (Test-Path $draft)) { Write-Host 'MTP head not downloaded. Run: .\install.ps1 -Models qwen3.8-27b-mtp' -ForegroundColor Red; exit 1 }
    $argv += @('--spec-type', 'draft-mtp', '-md', $draft)
}
Write-Host "Model: $Model  |  context $Ctx  |  http://127.0.0.1:$Port/v1 (this PC only)" -ForegroundColor Cyan
& $exe @argv
