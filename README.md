# AI Traffic Inference Gateway — Mac onboarding (v0.3)

## Scope and verified baseline

This starter is the **inference environment / traffic-generator** stage of the larger AI Traffic Inference Gateway project, not the finished Java gateway or telemetry stack.

The initial Mac setup was verified on an Apple Silicon MacBook Air M5 (32 GB) with Docker Desktop 4.98.0, Docker Model Runner v1.2.9, and the vLLM-Metal backend. The user successfully built `ai-traffic-generator:0.1.0`, served `hf.co/mlx-community/Llama-3.2-1B-Instruct-4bit`, and completed 50/50 API requests from Docker (concurrency 10, elapsed 14.96 s, throughput 3.34 requests/s, P50/P95/P99 2.214/5.648/5.757 s; 1,784 completion tokens and aggregate throughput 119.26 tokens/s). **These numbers are observations, not guarantees or rigorous benchmarks.**

Architecture:

```text
MacBook (Apple Silicon)
  Docker Desktop
    Docker Model Runner -> vLLM-Metal native host-managed runtime
      -> Llama-3.2-1B-Instruct-4bit (local model cache)
    Docker Compose
      -> traffic-generator image (Python 3.12 inside Linux/arm64 container)
        -> http://model-runner.docker.internal/engines/v1
```

**Important:** The GPU-backed model process is managed by Docker Model Runner, *not* packed into a conventional Linux Docker image. A Linux container cannot directly use Apple Metal GPU acceleration. Windows/Linux NVIDIA CUDA will have a separate inference runtime, though the traffic generator is portable. Nothing should be running manually at port `8000` for this setup.

## Quick start — brand-new Apple Silicon Mac

1. Download/clone the project and enter the project directory.
2. Open **Terminal**, then run:

```bash
cd /path/to/ai-traffic-gateway
chmod +x scripts/setup-mac.sh
./scripts/setup-mac.sh
```

This installer is designed to be re-runnable. It will:

1. Verify this is Apple Silicon macOS.
2. Install Homebrew if missing, using the official installer (interactive); use Homebrew to install Docker Desktop if missing.
3. Launch Docker Desktop, waiting for the Docker Engine. Docker's first-run agreement/permissions must be completed interactively.
4. Check Docker Engine, Compose and Docker Model Runner CLI.
5. Check Python 3.12+ on the host, installing Python 3.12 with Homebrew when necessary. **Host Python is optional for the Docker app**; the Docker image already contains Python 3.12. Host Python is installed here for future local engineering tooling because the project requested it.
6. Enable Docker Model Runner where possible and install the `vllm` backend (vLLM-Metal).
7. Copy `.env.mac.example` to `.env` if missing; migrate previous native-vLLM settings if detected; preserve existing test concurrency and model settings wherever possible. `.env` is not committed.
8. Pull the model weights once into the Model Runner cache.
9. Test the model discovery endpoint from a Docker container.
10. Build the traffic generator container and run the 50-request test.

The install is **one user command**, but first-time downloads, Mac administrator permissions, Docker license acceptance, and (in some Docker Desktop builds) enabling **Settings → AI → Enable Docker Model Runner** can still require interactive action. This is an honest limitation, not a separate manual Python/vLLM installation.

If Docker Model Runner is not enabled, open Docker Desktop → Settings → AI → **Enable Docker Model Runner**, apply, then rerun `./scripts/setup-mac.sh`.

If Homebrew is installed but Terminal cannot find it, run:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Docker Desktop 4.62+ is required for the macOS vLLM-Metal feature. If an older version is installed, update Docker Desktop before running the installer.

## Existing Mac project upgrade

**Do not delete your existing `.env` or old working project.** Back up the project before merging files from this package. Replace/merge `scripts/setup-mac.sh`, `scripts/doctor-mac.sh`, `.env.mac.example`, and README, and retain the other services/Compose files as desired. The installer backs up `.env` only when it detects an earlier native-model configuration; for additional safety, save a copy manually before updating.

Run the same installer:

```bash
./scripts/setup-mac.sh
```

Skip the load test if you only need dependency provisioning/build:

```bash
./scripts/setup-mac.sh --skip-test
```

## Day-to-day commands

```bash
# Rerun the workload; model loads on demand
 docker compose -f compose.yaml -f compose.mac.yaml run --rm traffic-generator

# Runtime / model status
 docker model status
 docker model list

# Check model API from a Docker container (works without host TCP)
 docker run --rm curlimages/curl:8.16.0 http://model-runner.docker.internal/engines/v1/models

# Show full diagnostics (read-only)
 ./scripts/doctor-mac.sh

# Inspect final Compose configuration
 docker compose -f compose.yaml -f compose.mac.yaml config
```

**Host Terminal access:** to use `curl http://localhost:12434/engines/v1/models`, enable **Docker Desktop → Settings → AI → host-side TCP support**, or run `docker desktop enable model-runner --tcp 12434` if supported. This is not necessary for containerized clients. Native `localhost:8000` is the old, manually launched vLLM endpoint and is intentionally no longer used.

### Send one request from a disposable Docker container

```bash
docker run --rm curlimages/curl:8.16.0 -fsS \
  http://model-runner.docker.internal/engines/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"huggingface.co/mlx-community/llama-3.2-1b-instruct-4bit:latest","messages":[{"role":"user","content":"Explain network monitoring in one sentence."}],"max_tokens":50}'
```

The model identifier exposed by `/models` may use a normalized `huggingface.co/...:latest` name even though `.env` uses `hf.co/...`. The working traffic-generator test shows that the shorter model reference is accepted in this environment.

## Configuration

`.env.mac.example` is the safe committed example; `.env` is a local configuration file and should not enter source control.

```dotenv
TRAFFIC_IMAGE=ai-traffic-generator:0.1.0
MODEL_NAME=hf.co/mlx-community/Llama-3.2-1B-Instruct-4bit
VLLM_BASE_URL=http://model-runner.docker.internal/engines/v1
CONCURRENCY=10
TOTAL_REQUESTS=50
MAX_TOKENS=40
READINESS_TIMEOUT=180
```

`compose.mac.yaml` deliberately overrides `VLLM_BASE_URL` to the Docker Model Runner container hostname. The URL comment from the old file saying "vLLM running natively" is outdated: **Docker Model Runner now owns the vLLM-Metal process**.

Dependencies overview:

| Component | Provisioned how? | Host installation needed? |
|---|---|---|
| Homebrew | Installer if missing | Yes, if installing Docker/Python this way |
| Docker Desktop / Engine / Compose | Homebrew cask / Docker Desktop | Yes |
| Python 3.12 inside traffic generator | `python:3.12-slim` Dockerfile | No |
| Python 3.12 on Mac | Brew if missing | Optional at runtime; script installs for development |
| vLLM-Metal | `docker model install-runner --backend vllm` | Managed by Docker Model Runner |
| Model weights | `docker model pull` | Cached by Model Runner |
| Python pip packages | None (standard library only) | No |

## Troubleshooting

- **`failed to install vllm backend: service unavailable`**: Verify `docker model status`. If not running, enable Docker Model Runner in Docker Desktop → Settings → AI, restart Docker Desktop, retry `docker model install-runner --backend vllm --debug`, then rerun setup. This is the exact issue encountered in the first installation.
- **`curl localhost:8000` connection refused**: That is expected now. The old host-native server is no longer started. Use Model Runner's container URL. Enable host TCP for localhost:12434 only if needed.
- **Model Runner service unreachable inside container**: Run `docker run --rm curlimages/curl:8.16.0 -v http://model-runner.docker.internal/engines/v1/models`, then `./scripts/doctor-mac.sh`.
- **`model not found`**: `docker model list`, then call `/engines/v1/models` to see actual model IDs. Update `MODEL_NAME` in `.env` and rerun. Check that the model was pulled.
- **Docker Desktop GUI is installed but CLI is unavailable**: Complete Docker Desktop first-run setup and ensure Docker CLI is on PATH; rerun.
- **Version mismatch**: Update Docker Desktop if the vLLM backend option does not exist. The installer does not silently remove or downgrade existing Docker Desktop installations.
- **Python version**: If `/usr/bin/python3` is old, `brew install python@3.12` provisions `/opt/homebrew/opt/python@3.12/bin/python3.12`; the application container uses Python 3.12 independently.

## Reconstructed step-by-step history

1. Started with manual native vLLM serving Qwen on `localhost:8000`; inference worked but the process was outside Docker management.
2. Created `.env`, validated Compose, built `ai-traffic-generator:0.1.0` successfully.
3. First container test to `host.docker.internal:8000` failed with `Network is unreachable`: 0/50 passed. This showed only a container-to-host connectivity problem.
4. Switched to Docker Model Runner to eliminate manual `vllm serve` lifecycle management.
5. First attempt to install the vLLM backend returned `service unavailable`. Docker diagnostics showed Model Runner was not running; rerunning `docker model install-runner --backend vllm --debug` succeeded.
6. Re-ran the Mac setup script; Docker-managed vLLM-Metal installed; the Llama model downloaded; traffic generator image rebuilt.
7. Docker container successfully called `http://model-runner.docker.internal/engines/v1/models`.
8. Final 50-request test succeeded with 0 failures, concurrency 10, in 14.96 seconds.

## Limitations and next steps

The generator is a smoke/load probe, not yet the Java traffic gateway. It does not yet support replaying original HTTP requests to a backend, tracing or Prometheus dashboards. Those are future phases. For meaningful benchmarking, use repeated runs, warmup, controlled prompt/output sizes, and better token/queueing instrumentation.

This installer targets **Apple Silicon Macs only**. `scripts/setup-windows.ps1` is preserved from the earlier portable project but has not been validated in this environment. Cloud portability requires a platform-specific NVIDIA CUDA inference backend. This work intentionally does not test Windows at this stage.

Do not expose an unauthenticated Docker Model Runner API to untrusted networks. The API may allow model management operations in addition to inference.

## Official references

- https://docs.docker.com/desktop/setup/install/mac-install/
- https://docs.docker.com/ai/model-runner/get-started/
- https://docs.docker.com/ai/model-runner/api-reference/
- https://www.docker.com/blog/docker-model-runner-vllm-metal-macos/
