#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.."
check(){ printf '\n---- %s ----\n' "$1"; shift; "$@" || echo '[FAILED]'; }
check 'System' uname -a
check 'Homebrew' brew --version
check 'Host Python (optional)' python3 --version
check 'Docker' docker version
check 'Docker Compose' docker compose version
check 'Model Runner' docker model status
check 'Models' docker model list
check 'Resolved Compose' docker compose -f compose.yaml -f compose.mac.yaml config
check 'Container-to-Runner API' docker run --rm curlimages/curl:8.16.0 -fsS --max-time 30 http://model-runner.docker.internal/engines/v1/models
