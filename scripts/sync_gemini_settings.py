#!/usr/bin/env python3
import json
import os
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
SETTINGS_PATH = Path(os.environ.get("MAS_SETTINGS_PATH", ROOT / "config/settings.yaml"))
OUTPUT_PATH = Path(os.environ.get("MAS_GEMINI_SETTINGS_PATH", ROOT / ".gemini/settings.json"))
SUMMARY_PATH = Path(os.environ.get("MAS_GEMINI_SUMMARY_PATH", ROOT / "queue/runtime/gemini_aliases.tsv"))

SCHEMA_URL = "https://raw.githubusercontent.com/google-gemini/gemini-cli/main/schemas/settings.schema.json"


def load_yaml(path: Path) -> dict:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


def load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def normalize_cli_type(agent_cfg) -> str:
    if isinstance(agent_cfg, str):
        return agent_cfg.strip().lower()
    if isinstance(agent_cfg, dict):
        return str(agent_cfg.get("type", "")).strip().lower()
    return ""


def normalize_model(agent_cfg) -> str:
    if not isinstance(agent_cfg, dict):
        return "auto"
    model = str(agent_cfg.get("model", "auto") or "auto").strip()
    return model or "auto"


def normalize_level(agent_cfg) -> str:
    if not isinstance(agent_cfg, dict):
        return ""
    level = str(agent_cfg.get("thinking_level", "") or "").strip().lower()
    if level == "auto":
        return ""
    if level in {"minimal", "low", "medium", "high"}:
        return level
    return ""


def normalize_budget(agent_cfg):
    if not isinstance(agent_cfg, dict):
        return None
    raw = agent_cfg.get("thinking_budget", None)
    if raw in (None, "", "auto", "dynamic"):
        return None
    try:
        value = int(raw)
    except (TypeError, ValueError):
        return None
    if value == -1 or value >= 0:
        return value
    return None


def default_level_for_agent(agent_id: str, model: str) -> str:
    return ""


def default_budget_for_agent(agent_id: str, model: str):
    return None


def choose_base_model(configured_model: str, level: str, budget):
    model = (configured_model or "auto").strip()
    lowered = model.lower()
    if model not in {"", "auto", "default"}:
        return model
    if budget is not None:
        return "gemini-2.5-pro"
    if level in {"minimal", "medium"}:
        return "gemini-3-flash-preview"
    return "gemini-3-pro-preview"


def normalize_level_for_model(model: str, level: str):
    if not level or level == "auto":
        return None, None
    lowered_model = model.lower()
    if lowered_model.startswith("gemini-3-pro") and level in {"minimal", "medium"}:
        return "LOW", f"{model} は MINIMAL/MEDIUM 非対応のため LOW へ丸めました"
    return level.upper(), None


def normalize_budget_for_model(model: str, budget):
    if budget is None:
        return None, None
    lowered_model = model.lower()
    if lowered_model.startswith("gemini-2.5-pro") and budget == 0:
        return -1, f"{model} は thinkingBudget=0 で思考停止できないため dynamic(-1) へ丸めました"
    return budget, None


def build_alias(agent_id: str, agent_cfg: dict):
    model = normalize_model(agent_cfg)
    level = normalize_level(agent_cfg)
    budget = normalize_budget(agent_cfg)
    if not level:
        level = default_level_for_agent(agent_id, model)
    if budget is None:
        budget = default_budget_for_agent(agent_id, model)
    if not level and budget is None:
        return None

    base_model = choose_base_model(model, level, budget)
    alias_name = f"mas-{agent_id}"
    alias_cfg = {"modelConfig": {"model": base_model}}
    warnings = []
    generate = {}

    normalized_level, level_warning = normalize_level_for_model(base_model, level)
    if level_warning:
        warnings.append(level_warning)
    if normalized_level:
        generate.setdefault("thinkingConfig", {})["thinkingLevel"] = normalized_level

    normalized_budget, budget_warning = normalize_budget_for_model(base_model, budget)
    if budget_warning:
        warnings.append(budget_warning)
    if normalized_budget is not None:
        generate.setdefault("thinkingConfig", {})["thinkingBudget"] = normalized_budget

    if generate:
        alias_cfg["modelConfig"]["generateContentConfig"] = generate

    return {
        "agent_id": agent_id,
        "alias": alias_name,
        "base_model": base_model,
        "thinking_level": normalized_level or "",
        "thinking_budget": "" if normalized_budget is None else str(normalized_budget),
        "alias_config": alias_cfg,
        "warnings": warnings,
    }


def main() -> int:
    settings = load_yaml(SETTINGS_PATH)
    cli = settings.get("cli", {}) if isinstance(settings, dict) else {}
    agents = cli.get("agents", {}) if isinstance(cli, dict) else {}

    existing = load_json(OUTPUT_PATH)
    if not isinstance(existing, dict):
        existing = {}

    model_configs = existing.setdefault("modelConfigs", {})
    if not isinstance(model_configs, dict):
        model_configs = {}
        existing["modelConfigs"] = model_configs

    custom_aliases = model_configs.setdefault("customAliases", {})
    if not isinstance(custom_aliases, dict):
        custom_aliases = {}
        model_configs["customAliases"] = custom_aliases

    for alias_name in list(custom_aliases.keys()):
        if alias_name.startswith("mas-"):
            custom_aliases.pop(alias_name, None)

    generated = []
    for agent_id, agent_cfg in agents.items():
        if normalize_cli_type(agent_cfg) != "gemini":
            continue
        alias = build_alias(agent_id, agent_cfg if isinstance(agent_cfg, dict) else {})
        if not alias:
            continue
        custom_aliases[alias["alias"]] = alias["alias_config"]
        generated.append(alias)

    existing["$schema"] = SCHEMA_URL

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_PATH.open("w", encoding="utf-8") as fh:
        json.dump(existing, fh, ensure_ascii=False, indent=2)
        fh.write("\n")

    SUMMARY_PATH.parent.mkdir(parents=True, exist_ok=True)
    with SUMMARY_PATH.open("w", encoding="utf-8") as fh:
        fh.write("agent_id\talias\tbase_model\tthinking_level\tthinking_budget\twarnings\n")
        for item in generated:
            fh.write(
                "\t".join(
                    [
                        item["agent_id"],
                        item["alias"],
                        item["base_model"],
                        item["thinking_level"],
                        item["thinking_budget"],
                        " | ".join(item["warnings"]),
                    ]
                )
                + "\n"
            )

    print(f"[INFO] synced Gemini workspace settings: {OUTPUT_PATH} ({len(generated)} alias(es))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
