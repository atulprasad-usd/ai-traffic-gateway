#!/usr/bin/env bash
# Reproducible, idempotent onboarding for Apple Silicon with Docker Desktop.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
MODEL_DEFAULT="hf.co/mlx-community/Llama-3.2-1B-Instruct-4bit"
INFERENCE_URL="http://model-runner.docker.internal/engines/v1"
SKIP_TEST=0
case "${1:-}" in
  "") ;;
  --skip-test) SKIP_TEST=1 ;;
  *) echo "Usage: ./scripts/setup-mac.sh [--skip-test]" >&2; exit 2 ;;
esac

log(){ printf '\n==> %s\n' "$*"; }
fail(){ printf '\nERROR: %s\n' "$*" >&2; exit 1; }
require_macos(){
  [[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || fail "This setup requires an Apple Silicon Mac (arm64)."
}
ensure_brew(){
  if command -v brew >/dev/null; then return; fi
  log 'Homebrew missing. Installing with the official installer (may ask for administrator approval).'
  command -v curl >/dev/null || fail 'curl is required to install Homebrew.'
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
  command -v brew >/dev/null || fail 'Homebrew installed but is not on PATH. Follow the shellenv instructions from its installer and rerun.'
}
ensure_python(){
  # Host Python is for future development tools. The container already has Python 3.12.
  if command -v python3 >/dev/null && python3 -c 'import sys; assert sys.version_info >= (3, 12)' >/dev/null 2>&1; then
    log "Host Python present: $(python3 --version)"
    return
  fi
  ensure_brew
  log 'Installing host Python 3.12 for development convenience.'
  brew install python@3.12
  # brew may install versioned Python without replacing an older system python3.
  if [[ -x "$(brew --prefix python@3.12)/bin/python3.12" ]]; then
    "$(brew --prefix python@3.12)/bin/python3.12" --version
  fi
}
ensure_docker(){
  if ! command -v docker >/dev/null; then
    ensure_brew
    log 'Installing Docker Desktop via Homebrew cask.'
    brew install --cask docker
  fi
  if ! docker info >/dev/null 2>&1; then
    log 'Starting Docker Desktop. First launch may require accepting license terms and granting permissions.'
    open -a Docker || fail 'Could not open Docker Desktop. Launch it manually from Applications.'
    for i in {1..90}; do
      if docker info >/dev/null 2>&1; then break; fi
      sleep 2
    done
  fi
  docker info >/dev/null 2>&1 || fail 'Docker Engine is not ready. Complete Docker Desktop onboarding, then rerun this script.'
  docker compose version >/dev/null 2>&1 || fail 'Docker Compose plugin missing. Update Docker Desktop.'
  docker model version >/dev/null 2>&1 || fail 'Docker Model Runner CLI missing. Update Docker Desktop (vLLM-Metal needs 4.62+).'
  log 'Docker Engine and Compose are available.'
}
ensure_runner(){
  if ! docker model status 2>/dev/null | grep -q 'Docker Model Runner is running'; then
    log 'Enabling Docker Model Runner (may require enabling Settings > AI in Docker Desktop).'
    docker desktop enable model-runner || true
  fi
  # Don't assume previous status; the backend may be absent even when Runner is enabled.
  log 'Installing/validating Docker-managed vLLM-Metal backend.'
  docker model install-runner --backend vllm || fail 'Docker Model Runner backend installation failed. Open Docker Desktop > Settings > AI, enable Model Runner, restart Docker Desktop, and rerun.'
  docker model status
  docker model status | grep -q 'vllm.*Running' || fail 'vLLM backend is not running; check Docker Desktop > Settings > AI.'
}
set_env_key(){
  local key="$1" value="$2" temp
  temp="$(mktemp)"
  if grep -q "^${key}=" .env; then
    awk -v k="$key" -v v="$value" 'index($0,k"=")==1 {$0=k"="v} {print}' .env > "$temp"
  else
    cat .env > "$temp"
    printf '%s=%s\n' "$key" "$value" >> "$temp"
  fi
  cat "$temp" > .env
  rm -f "$temp"
}
ensure_env(){
  if [[ ! -f .env ]]; then
    cp .env.mac.example .env
    log 'Created .env from .env.mac.example.'
  else
    log 'Using existing .env; preserving your concurrency and test settings.'
  fi
  # Migrate configurations from the previously manual host-vLLM setup.
  local model url
  model="$(sed -n 's/^MODEL_NAME=//p' .env | tail -1 | tr -d '\r')"
  url="$(sed -n 's/^VLLM_BASE_URL=//p' .env | tail -1 | tr -d '\r')"
  if [[ -z "$model" || "$model" == mlx-community/* || "$url" == *host.docker.internal:8000* ]]; then
    cp .env ".env.backup.$(date +%Y%m%d%H%M%S)"
    [[ -n "$model" && "$model" != mlx-community/* ]] || set_env_key MODEL_NAME "$MODEL_DEFAULT"
    log 'Backed up .env and migrated prior native vLLM settings.'
  fi
  set_env_key VLLM_BASE_URL "$INFERENCE_URL"
  # A custom Model Runner reference is respected.
  MODEL_REF="$(sed -n 's/^MODEL_NAME=//p' .env | tail -1 | tr -d '\r')"
  [[ -n "$MODEL_REF" ]] || fail 'MODEL_NAME is empty in .env.'
}
verify_api(){
  log 'Verifying API reachability from an ordinary Docker container.'
  docker run --rm --pull=missing curlimages/curl:8.16.0 \
    --fail --silent --show-error --max-time 30 \
    "${INFERENCE_URL}/models" || fail 'Model Runner endpoint not reachable from Docker. Check Docker Desktop > Settings > AI.'
  printf '\n'
}
build_and_test(){
  log 'Building the application image.'
  docker compose -f compose.yaml -f compose.mac.yaml build traffic-generator
  if (( SKIP_TEST == 0 )); then
    log 'Running the traffic-generator smoke test (loads the model on demand).'
    docker compose -f compose.yaml -f compose.mac.yaml run --rm traffic-generator
  fi
}

require_macos
log 'Beginning Apple Silicon development environment setup.'
ensure_docker
ensure_python
ensure_runner
ensure_env
log "Pulling model: $MODEL_REF"
docker model pull "$MODEL_REF"
verify_api
build_and_test
log 'Setup complete. To repeat the workload:'
printf '  docker compose -f compose.yaml -f compose.mac.yaml run --rm traffic-generator\n'
