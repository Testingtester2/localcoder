<#
  Local Coder Kit installer.
  Sets up a local coding LLM on an NVIDIA GPU:
    llama.cpp (official build) serving a Qwen model on 127.0.0.1 only,
    OpenCode running inside a Docker sandbox that only sees one project folder.
  Every download is checked against the publisher's SHA-256 before it is kept.

  Usage (from this folder, in PowerShell):
    .\install.ps1                         # picks a model for your GPU
    .\install.ps1 -Models qwen3.8-27b-q6,qwen3.6-35b-a3b
    .\install.ps1 -Models all
    .\install.ps1 -SkipModels             # only tools, no model download
#>
[CmdletBinding()]
param(
    [string[]]$Models,
    [switch]$SkipModels,
    [switch]$SkipDocker
)

$ErrorActionPreference = 'Stop'
if ($Models) { $Models = @($Models | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = $PSScriptRoot
$UA = @{ 'User-Agent' = 'local-coder-kit'; 'Accept' = 'application/vnd.github+json' }

function Say($msg) { Write-Host "[kit] $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "[kit] $msg" -ForegroundColor Red; exit 1 }

function Get-Sha256($path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower() }

function Get-Verified($url, $out, $sha256) {
    # curl.exe ships with Windows 10/11 and can resume (-C -)
    $part = "$out.part"
    if ((Test-Path $out) -and ((Get-Sha256 $out) -eq $sha256)) { Say "already have $(Split-Path $out -Leaf)"; return }
    Say "downloading $(Split-Path $out -Leaf)"
    & curl.exe -L --fail --retry 5 --retry-delay 5 -C - -o $part $url
    if ($LASTEXITCODE -ne 0) { Fail "download failed: $url" }
    $got = Get-Sha256 $part
    if ($got -ne $sha256) { Remove-Item $part -Force; Fail "checksum mismatch for $(Split-Path $out -Leaf) (expected $sha256, got $got). File deleted." }
    Move-Item -Force $part $out
    Say "verified $(Split-Path $out -Leaf)"
}

# ---------- checks ----------
Say 'checking this PC'
$smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if (-not $smi) { Fail 'nvidia-smi not found. This kit needs an NVIDIA GPU with a current driver.' }
$gpu = (& nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits | Select-Object -First 1).Split(',')
$gpuName = $gpu[0].Trim(); $vramGB = [math]::Round([int]$gpu[1].Trim() / 1024)
$cudaLine = (& nvidia-smi | Select-String 'CUDA Version:\s*([0-9]+)\.([0-9]+)')
$cudaMajor = if ($cudaLine) { [int]$cudaLine.Matches[0].Groups[1].Value } else { 12 }
Say "GPU: $gpuName, $vramGB GB VRAM, driver supports CUDA $cudaMajor"
if ($vramGB -lt 20) { Write-Warning 'Less than 20 GB VRAM: the 27B models will spill to RAM and be slow.' }

if (-not $SkipDocker) {
    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $docker) { Fail 'Docker not found. Install Docker Desktop (WSL2 backend), start it, then run this again. Or use -SkipDocker.' }
    & docker version --format '{{.Server.Version}}' *> $null
    if ($LASTEXITCODE -ne 0) { Fail 'Docker is installed but not running. Start Docker Desktop and run this again.' }
}

$versions = Get-Content (Join-Path $Root 'config\versions.json') -Raw | ConvertFrom-Json
$catalog = Get-Content (Join-Path $Root 'config\models.json') -Raw | ConvertFrom-Json

# ---------- llama.cpp ----------
$tag = $versions.llamaCppTag
$cuda = if ($cudaMajor -ge 13) { '13.5' } else { '12.4' }
$llamaDir = Join-Path $Root 'llama.cpp'
$marker = Join-Path $llamaDir 'kit-version.txt'
if ((Test-Path $marker) -and ((Get-Content $marker -Raw).Trim() -eq "$tag cuda-$cuda")) {
    Say "llama.cpp $tag already installed"
} else {
    Say "getting llama.cpp $tag (CUDA $cuda) from github.com/ggml-org/llama.cpp"
    $rel = Invoke-RestMethod -UseBasicParsing -Headers $UA "https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$tag"
    $want = @("llama-$tag-bin-win-cuda-$cuda-x64.zip", "cudart-llama-bin-win-cuda-$cuda-x64.zip")
    New-Item -ItemType Directory -Force $llamaDir | Out-Null
    $tmp = Join-Path $env:TEMP "lck-$tag"; New-Item -ItemType Directory -Force $tmp | Out-Null
    foreach ($name in $want) {
        $a = $rel.assets | Where-Object { $_.name -eq $name }
        if (-not $a) { Fail "release $tag has no asset $name" }
        if (-not $a.digest) { Fail "GitHub gave no checksum for $name, refusing to install it" }
        $zip = Join-Path $tmp $name
        Get-Verified $a.browser_download_url $zip ($a.digest -replace '^sha256:', '')
        Expand-Archive -Force -LiteralPath $zip -DestinationPath $llamaDir
    }
    Set-Content -Path $marker -Value "$tag cuda-$cuda"
    Remove-Item -Recurse -Force $tmp
}

# ---------- models ----------
$modelDir = Join-Path $Root 'models'
New-Item -ItemType Directory -Force $modelDir | Out-Null
if (-not $SkipModels) {
    if (-not $Models) {
        $Models = if ($vramGB -ge 28) { @('qwen3.8-27b-q6') } else { @('qwen3.8-27b-q4') }
        Say "no -Models given, picking $($Models -join ', ') for $vramGB GB"
    }
    if ($Models -contains 'all') { $Models = $catalog.PSObject.Properties.Name }
    $trees = @{}
    foreach ($id in $Models) {
        $m = $catalog.$id
        if (-not $m) { Fail "unknown model '$id'. Choices: $($catalog.PSObject.Properties.Name -join ', ')" }
        if (-not $trees.ContainsKey($m.repo)) {
            $trees[$m.repo] = Invoke-RestMethod -UseBasicParsing -Headers @{ 'User-Agent' = 'local-coder-kit' } "https://huggingface.co/api/models/$($m.repo)/tree/main?recursive=1"
        }
        $entry = $trees[$m.repo] | Where-Object { $_.path -eq $m.file }
        if (-not $entry -or -not $entry.lfs.oid) { Fail "could not find $($m.file) with a checksum in $($m.repo)" }
        Say "$id : $($m.file) ($([math]::Round($entry.size / 1e9, 1)) GB) from huggingface.co/$($m.repo)"
        $out = Join-Path $modelDir (Split-Path $m.file -Leaf)
        Get-Verified "https://huggingface.co/$($m.repo)/resolve/main/$($m.file)" $out $entry.lfs.oid
    }
}

# ---------- API key (local only) ----------
$keyFile = Join-Path $Root 'llm.key'
if (-not (Test-Path $keyFile)) {
    $bytes = New-Object byte[] 24
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $key = 'sk-local-' + (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
    Set-Content -Path $keyFile -Value $key -NoNewline
    Say 'created llm.key (random key between the agent and the model server)'
}

# ---------- OpenCode sandbox image ----------
if (-not $SkipDocker) {
    $ver = $versions.openCodeVersion
    Say "getting OpenCode $ver from github.com/$($versions.openCodeRepo)"
    $rel = Invoke-RestMethod -UseBasicParsing -Headers $UA "https://api.github.com/repos/$($versions.openCodeRepo)/releases/tags/$ver"
    $a = $rel.assets | Where-Object { $_.name -eq 'opencode-linux-x64.tar.gz' }
    if (-not $a -or -not $a.digest) { Fail "OpenCode ${ver}: linux-x64 build or its checksum not found" }
    $tmp = Join-Path $env:TEMP "lck-oc"; New-Item -ItemType Directory -Force $tmp | Out-Null
    $tgz = Join-Path $tmp $a.name
    Get-Verified $a.browser_download_url $tgz ($a.digest -replace '^sha256:', '')
    & tar.exe -xzf $tgz -C (Join-Path $Root 'docker') opencode
    if ($LASTEXITCODE -ne 0) { Fail 'could not unpack OpenCode' }
    Remove-Item -Recurse -Force $tmp
    Copy-Item -Force (Join-Path $Root 'config\opencode.json') (Join-Path $Root 'docker\opencode.json')
    Say 'building the sandbox image localcoder:1 (first time pulls ubuntu:24.04)'
    & docker build -t localcoder:1 (Join-Path $Root 'docker')
    if ($LASTEXITCODE -ne 0) { Fail 'docker build failed' }
}

Say 'done.'
Say '  1. Start-LLM.bat            starts the model server (close the window to stop it)'
Say '  2. Start-Agent.bat <folder> opens OpenCode on that folder, sandboxed'
