"""Standard-library-only, concurrent smoke test for an OpenAI-compatible model endpoint."""
import asyncio
import json
import os
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

BASE_URL = os.environ["VLLM_BASE_URL"].rstrip("/")
MODEL = os.environ["MODEL_NAME"]
CONCURRENCY = int(os.getenv("CONCURRENCY", "5"))
TOTAL_REQUESTS = int(os.getenv("TOTAL_REQUESTS", "20"))
MAX_TOKENS = int(os.getenv("MAX_TOKENS", "40"))
READINESS_TIMEOUT = int(os.getenv("READINESS_TIMEOUT", "180"))


def http_json(path, data=None, timeout=60):
    headers = {"Content-Type": "application/json"}
    req = Request(BASE_URL + path, data=data, headers=headers,
                  method="POST" if data is not None else "GET")
    with urlopen(req, timeout=timeout) as response:
        return json.load(response)


def probe():
    try:
        response = http_json("/models", timeout=10)
        if not isinstance(response, dict):
            raise ValueError("Unexpected models response")
        return response
    except Exception as exc:
        raise RuntimeError(str(exc)) from exc


async def wait_until_ready():
    start = time.monotonic()
    while time.monotonic() - start < READINESS_TIMEOUT:
        try:
            result = await asyncio.to_thread(probe)
            ids = [m.get("id") for m in result.get("data", [])]
            print(f"Model API reachable; visible models: {ids}")
            return
        except Exception as exc:
            print(f"Waiting for model API: {exc}", flush=True)
            await asyncio.sleep(5)
    raise TimeoutError(f"Model API not reachable after {READINESS_TIMEOUT}s: {BASE_URL}")


def send_one(index):
    prompt = f"Request {index}: explain why AI inference latency matters in one sentence."
    data = json.dumps({
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": MAX_TOKENS,
        "temperature": 0,
        "stream": False,
    }).encode("utf-8")
    start = time.perf_counter()
    try:
        response = http_json("/chat/completions", data=data, timeout=180)
        return (True, time.perf_counter() - start,
                (response.get("usage") or {}).get("completion_tokens", 0), "")
    except HTTPError as exc:
        return False, time.perf_counter() - start, 0, f"HTTP {exc.code}: {exc.read(500).decode(errors='replace')}"
    except Exception as exc:
        return False, time.perf_counter() - start, 0, str(exc)


def percentile(values, fraction):
    if not values:
        return None
    idx = (len(values) - 1) * fraction
    lo = int(idx)
    hi = min(lo + 1, len(values) - 1)
    return values[lo] + (values[hi] - values[lo]) * (idx - lo)


async def main():
    if min(CONCURRENCY, TOTAL_REQUESTS, MAX_TOKENS, READINESS_TIMEOUT) < 1:
        raise ValueError("All numeric configuration values must be positive")
    print(f"Endpoint: {BASE_URL}\nModel: {MODEL}")
    print(f"Concurrency: {CONCURRENCY}; total requests: {TOTAL_REQUESTS}", flush=True)
    await wait_until_ready()
    sem = asyncio.Semaphore(CONCURRENCY)

    async def one(i):
        async with sem:
            return await asyncio.to_thread(send_one, i)

    started = time.perf_counter()
    results = await asyncio.gather(*(one(i) for i in range(TOTAL_REQUESTS)))
    elapsed = time.perf_counter() - started
    successes = [r for r in results if r[0]]
    failures = [r for r in results if not r[0]]
    latencies = sorted(r[1] for r in successes)
    tokens = sum(r[2] for r in successes)
    print(f"Success: {len(successes)}, failures: {len(failures)}")
    print(f"Elapsed: {elapsed:.2f}s; completed throughput: {TOTAL_REQUESTS / elapsed:.2f} req/s")
    if successes:
        print(f"P50/P95/P99 latency: {percentile(latencies, .5):.3f} / {percentile(latencies, .95):.3f} / {percentile(latencies, .99):.3f}s")
        print(f"Reported completion tokens: {tokens}; aggregate output tokens/s: {tokens/elapsed:.2f}")
    for i, result in enumerate(failures[:5]):
        print(f"Example failure {i + 1}: {result[3]}")
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    asyncio.run(main())
