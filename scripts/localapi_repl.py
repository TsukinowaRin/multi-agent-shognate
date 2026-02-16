#!/usr/bin/env python3
"""Lightweight local OpenAI-compatible chat REPL for multi-agent-shogun.

Supports: Ollama, LM Studio, llama.cpp server, or any OpenAI-compatible endpoint.

Environment variables:
  LOCALAI_API_BASE (default: http://127.0.0.1:11434/v1)
  LOCALAI_API_KEY  (optional)
  LOCALAI_MODEL    (default: local-model)
  LOCALAI_SYSTEM   (optional system prompt)
"""

import json
import os
import sys
import urllib.error
import urllib.request


def chat_completion(
    api_base: str, api_key: str, model: str, messages: list
) -> str:
    url = f"{api_base.rstrip('/')}/chat/completions"
    payload = {
        "model": model,
        "messages": messages,
        "stream": False,
    }
    data = json.dumps(payload).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=120) as resp:
        body = resp.read().decode("utf-8")
        parsed = json.loads(body)
        return parsed["choices"][0]["message"]["content"]


def main() -> int:
    api_base = os.getenv("LOCALAI_API_BASE", "http://127.0.0.1:11434/v1")
    api_key = os.getenv("LOCALAI_API_KEY", "")
    model = os.getenv("LOCALAI_MODEL", "local-model")
    system_prompt = os.getenv("LOCALAI_SYSTEM", "")

    print(f"[localapi] connected base={api_base} model={model}")
    print("[localapi] commands: :model <name>, :clear, :help, :exit")

    messages: list = []
    if system_prompt:
        messages.append({"role": "system", "content": system_prompt})

    while True:
        try:
            line = input("localapi> ").strip()
        except EOFError:
            print("")
            return 0
        except KeyboardInterrupt:
            print("\n[localapi] interrupted")
            continue

        if not line:
            continue

        if line in (":exit", "/exit", "exit", "quit"):
            return 0

        if line in (":help", "/help", "help"):
            print("commands: :model <name>, :clear, :help, :exit")
            print(f"  current model: {model}")
            print(f"  endpoint: {api_base}")
            print(f"  history: {len(messages)} messages")
            continue

        if line.startswith(":model ") or line.startswith("/model "):
            next_model = line.split(" ", 1)[1].strip()
            if next_model:
                model = next_model
                print(f"[localapi] model={model}")
            continue

        if line in (":clear", "/clear"):
            messages = []
            if system_prompt:
                messages.append({"role": "system", "content": system_prompt})
            print("[localapi] conversation cleared")
            continue

        messages.append({"role": "user", "content": line})

        try:
            answer = chat_completion(api_base, api_key, model, messages)
            messages.append({"role": "assistant", "content": answer})
            print(answer)
        except urllib.error.HTTPError as e:
            err = e.read().decode("utf-8", errors="replace")
            print(f"[localapi][http:{e.code}] {err}")
            messages.pop()  # remove failed user message
        except urllib.error.URLError as e:
            print(f"[localapi][network] {e}")
            messages.pop()
        except (KeyError, IndexError, json.JSONDecodeError) as e:
            print(f"[localapi][protocol] malformed response: {e}")
            messages.pop()
        except Exception as e:
            print(f"[localapi][error] {e}")
            messages.pop()


if __name__ == "__main__":
    sys.exit(main())
