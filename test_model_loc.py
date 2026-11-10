
import asyncio
import json
import time
from urllib.request import Request, urlopen

URL = "http://localhost:8000/v1/chat/completions"
MODEL = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"

def send_request(index):
    payload = json.dumps({
        "model": MODEL,
        "messages": [
            {
                "role": "user",
                "content": f"Say hello to client {index}."
            }
        ],
        "max_tokens": 40
    }).encode()

    request = Request(
        URL,
        data=payload,
        headers={"Content-Type": "application/json"}
    )

    start = time.perf_counter()

    try:
        with urlopen(request, timeout=120) as response:
            response.read()
            return index, response.status, time.perf_counter() - start
    except Exception as exc:
        return index, str(exc), time.perf_counter() - start

async def main():
    tasks = [
        asyncio.to_thread(send_request, i)
        for i in range(10)
    ]

    results = await asyncio.gather(*tasks)

    for index, status, elapsed in results:
        print(f"Client {index}: {status}, {elapsed:.2f}s")

asyncio.run(main())
