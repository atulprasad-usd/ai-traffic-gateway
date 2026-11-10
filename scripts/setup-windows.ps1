$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Install and start Docker Desktop with WSL2 support.' }
docker info | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Start Docker Desktop first.' }
if (-not (Test-Path .env)) {
    Copy-Item .env.windows.example .env
    Write-Host 'Created .env from .env.windows.example'
} else {
    Write-Warning 'Existing .env retained. Ensure MODEL_NAME and WINDOWS_MODEL refer to the Windows model.'
}
Write-Host 'Checking that Docker sees the NVIDIA GPU...'
docker run --rm --gpus all nvidia/cuda:12.9.0-base-ubuntu22.04 nvidia-smi
if ($LASTEXITCODE -ne 0) { throw 'GPU check failed: update NVIDIA drivers, WSL2 and Docker Desktop.' }
Write-Host 'Starting NVIDIA vLLM Docker service...'
docker compose -f compose.yaml -f compose.windows.yaml up -d --no-deps vllm
if ($LASTEXITCODE -ne 0) { throw 'Failed to start vLLM.' }
Write-Host 'vLLM is starting. Watch logs:'
Write-Host '  docker compose -f compose.yaml -f compose.windows.yaml logs -f vllm'
Write-Host 'After the model is ready, run:'
Write-Host '  docker compose -f compose.yaml -f compose.windows.yaml run --rm traffic-generator'
