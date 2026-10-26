"""End-to-end check of a running server through the official OpenAI Python SDK.

    pip install -r tests/requirements.txt
    python tests/smoke_test.py                                   # http://localhost:8000/v1
    python tests/smoke_test.py --base-url http://gpu-box:8000/v1 --api-key <key>

Exits non-zero on the first failure.
"""

import argparse
import os
import sys
import time

from openai import OpenAI


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base-url", default=os.environ.get("OPENAI_BASE_URL", "http://localhost:8000/v1"))
    parser.add_argument(
        "--api-key",
        default=os.environ.get("VLLM_API_KEY") or os.environ.get("OPENAI_API_KEY") or "not-needed",
        help="only required if the server was started with VLLM_API_KEY",
    )
    parser.add_argument("--model", default=None, help="served model name (default: first entry of /v1/models)")
    args = parser.parse_args()

    client = OpenAI(base_url=args.base_url, api_key=args.api_key)

    print(f"==> models at {args.base_url}")
    model_ids = [m.id for m in client.models.list().data]
    print("   ", model_ids)
    if not model_ids:
        print("no models served", file=sys.stderr)
        return 1
    model = args.model or model_ids[0]

    print(f"==> chat completion ({model})")
    t0 = time.perf_counter()
    reply = client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": "In one sentence, what is a qubit?"}],
        max_tokens=64,
        temperature=0.2,
    )
    elapsed = time.perf_counter() - t0
    text = reply.choices[0].message.content.strip()
    usage = reply.usage
    print("   ", text)
    if usage and usage.completion_tokens:
        print(f"    {usage.completion_tokens} tokens in {elapsed:.2f}s "
              f"({usage.completion_tokens / elapsed:.1f} tok/s, single request)")

    print(f"==> streaming chat completion ({model})")
    print("    ", end="", flush=True)
    stream = client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": "Count from one to five in words."}],
        max_tokens=32,
        temperature=0,
        stream=True,
    )
    for chunk in stream:
        delta = chunk.choices[0].delta.content if chunk.choices else None
        if delta:
            print(delta, end="", flush=True)
    print()

    print(f"==> text completion ({model})")
    completion = client.completions.create(
        model=model,
        prompt="The capital of France is",
        max_tokens=8,
        temperature=0,
    )
    print("   ", completion.choices[0].text.strip())

    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
