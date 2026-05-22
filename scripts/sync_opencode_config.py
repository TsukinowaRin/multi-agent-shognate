#!/usr/bin/env python3
import json
import os
from pathlib import Path

try:
    import yaml  # type: ignore
except Exception as exc:
    raise SystemExit(f"[ERROR] PyYAML is required: {exc}")

ROOT = Path(__file__).resolve().parent.parent
SETTINGS_PATH = Path(os.environ.get("MAS_SETTINGS_PATH", ROOT / "config/settings.yaml"))
CONFIG_PATH = Path(os.environ.get("MAS_OPENCODE_CONFIG_PATH", ROOT / "opencode.json"))
SUMMARY_PATH = Path(os.environ.get("MAS_OPENCODE_SUMMARY_PATH", ROOT / "queue/runtime/opencode_like_config_summary.tsv"))


def load_settings() -> dict:
    if not SETTINGS_PATH.exists():
        return {}
    with SETTINGS_PATH.open(encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    return data if isinstance(data, dict) else {}


def iter_agent_types(cfg: dict) -> list[str]:
    agents = ((cfg.get("cli") or {}).get("agents") or {})
    result: list[str] = []
    if not isinstance(agents, dict):
        return result
    for value in agents.values():
        if isinstance(value, dict):
            cli_type = value.get("type")
        else:
            cli_type = value
        if isinstance(cli_type, str):
            result.append(cli_type)
    default = ((cfg.get("cli") or {}).get("default"))
    if isinstance(default, str):
        result.append(default)
    return result


def read_shared_section(cfg: dict) -> dict:
    cli = cfg.get("cli") or {}
    section = cli.get("opencode_like") or cfg.get("opencode_like") or {}
    return section if isinstance(section, dict) else {}


def default_base_url(provider_id: str) -> str:
    normalized = provider_id.strip().lower()
    if normalized == "ollama":
        return "http://127.0.0.1:11434/v1"
    if normalized in {"lmstudio", "openai-compatible"}:
        return "http://127.0.0.1:1234/v1"
    return ""


def build_config(section: dict) -> dict:
    provider_id = str(section.get("provider") or section.get("provider_id") or "").strip()
    base_url = str(section.get("base_url") or section.get("endpoint") or "").strip()
    api_key_env = str(section.get("api_key_env") or "").strip()
    instructions = section.get("instructions") or []
    extra_options = section.get("options") or {}

    if provider_id and not base_url:
        base_url = default_base_url(provider_id)

    config: dict = {
        # Default this repository to unattended operation for OpenCode/Kilo.
        "permission": "allow",
    }
    if isinstance(instructions, list):
        clean_instructions = [item for item in instructions if isinstance(item, str) and item.strip()]
        if clean_instructions:
            config["instructions"] = clean_instructions

    if provider_id:
        provider_options: dict = {}
        if base_url:
            provider_options["baseURL"] = base_url
        if api_key_env:
            provider_options["apiKey"] = f"{{env:{api_key_env}}}"
        if isinstance(extra_options, dict):
            for key, value in extra_options.items():
                if isinstance(key, str):
                    provider_options[key] = value
        provider_block = {provider_id: {}}
        if provider_options:
            provider_block[provider_id]["options"] = provider_options
        config["provider"] = provider_block

    return config


def main() -> int:
    cfg = load_settings()
    agent_types = iter_agent_types(cfg)
    section = read_shared_section(cfg)
    uses_opencode_like = any(t in {"opencode", "kilo"} for t in agent_types)

    SUMMARY_PATH.parent.mkdir(parents=True, exist_ok=True)

    if not uses_opencode_like and not section:
        SUMMARY_PATH.write_text("status\tskipped\treason\tno-opencode-or-kilo-agents\n", encoding="utf-8")
        return 0

    config = build_config(section)
    if not config:
        SUMMARY_PATH.write_text("status\tnoop\treason\tno-project-provider-config\n", encoding="utf-8")
        return 0

    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    provider_id = str(section.get("provider") or section.get("provider_id") or "")
    base_url = str(section.get("base_url") or section.get("endpoint") or "")
    if provider_id and not base_url:
        base_url = default_base_url(provider_id)
    api_key_env = str(section.get("api_key_env") or "")
    SUMMARY_PATH.write_text(
        "status\tgenerated\n"
        f"config_path\t{CONFIG_PATH}\n"
        f"provider\t{provider_id or '-'}\n"
        f"base_url\t{base_url or '-'}\n"
        f"api_key_env\t{api_key_env or '-'}\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
