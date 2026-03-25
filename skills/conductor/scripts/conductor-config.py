#!/usr/bin/env python3
"""
Conductor: Configuration Resolver

Resolves orchestration settings from .orchestra_configs/conductor files.

Search order (first hit wins):
1. <project-dir>/.orchestra_configs/conductor
2. <project-dir>/../.orchestra_configs/conductor

Output is always valid JSON. Invalid or missing values emit warnings and
fallback to safe defaults.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# --- Defaults ---
DEFAULTS = {
    "PROJECT_DIR": None,  # resolved to cwd at runtime
    "TERMINAL_CMD": "kitty",
    "SESSION_LAYER": "tmux",
    "VCS_ENABLED": "true",
    "SOUFFLEUR_PERMISSIONS": "acceptEdits",
    "MUSICIAN_PERMISSIONS": "acceptEdits",
    "MAX_PARALLEL_MUSICIANS": 4,
    "DEGRADATION_FIX_ATTEMPTS": 5,
    "DEGRADATION_RELAUNCH_LIMIT": 2,
    "HEARTBEAT_POKE_THRESHOLD": 240,
}

ALLOWED_PERMISSIONS = {"acceptEdits", "bypassPermissions"}
ALLOWED_SESSION_LAYERS = {"tmux", "fifo"}
ALLOWED_BOOLEANS = {"true", "false"}

POSITIVE_INT_KEYS = {
    "MAX_PARALLEL_MUSICIANS",
    "DEGRADATION_FIX_ATTEMPTS",
    "DEGRADATION_RELAUNCH_LIMIT",
    "HEARTBEAT_POKE_THRESHOLD",
}


def _find_config_file(project_dir: Path) -> Path | None:
    candidates = [
        project_dir / ".orchestra_configs" / "conductor",
        project_dir.parent / ".orchestra_configs" / "conductor",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


def _parse_config(path: Path) -> tuple[dict[str, str], list[str]]:
    values: dict[str, str] = {}
    warnings: list[str] = []

    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        warnings.append(f"Unable to read config file {path}: {exc}")
        return values, warnings

    for line_no, raw_line in enumerate(lines, start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            warnings.append(
                f"Ignoring malformed config line {line_no} in {path} (missing '=')"
            )
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()

        if key in values:
            warnings.append(
                f"Duplicate key '{key}' on line {line_no} in {path}; last value wins"
            )

        values[key] = value

    return values, warnings


def _resolve(project_dir: Path) -> dict:
    warnings: list[str] = []
    config_path = _find_config_file(project_dir)

    source = None
    raw: dict[str, str] = {}
    if config_path is not None:
        source = str(config_path)
        raw, parse_warnings = _parse_config(config_path)
        warnings.extend(parse_warnings)

    # PROJECT_DIR
    raw_project_dir = raw.get("PROJECT_DIR")
    if raw_project_dir is not None:
        resolved_project_dir = str(Path(raw_project_dir).resolve())
    else:
        resolved_project_dir = str(project_dir)

    # TERMINAL_CMD
    terminal_cmd = raw.get("TERMINAL_CMD", DEFAULTS["TERMINAL_CMD"])

    # SESSION_LAYER
    session_layer = DEFAULTS["SESSION_LAYER"]
    raw_sl = raw.get("SESSION_LAYER")
    if raw_sl is not None:
        if raw_sl in ALLOWED_SESSION_LAYERS:
            session_layer = raw_sl
        else:
            warnings.append(
                f"Invalid SESSION_LAYER='{raw_sl}' "
                f"(allowed: {', '.join(sorted(ALLOWED_SESSION_LAYERS))}); "
                f"using default {DEFAULTS['SESSION_LAYER']}"
            )

    # VCS_ENABLED
    vcs_enabled = DEFAULTS["VCS_ENABLED"]
    raw_vcs = raw.get("VCS_ENABLED")
    if raw_vcs is not None:
        if raw_vcs.lower() in ALLOWED_BOOLEANS:
            vcs_enabled = raw_vcs.lower()
        else:
            warnings.append(
                f"Invalid VCS_ENABLED='{raw_vcs}' (allowed: true, false); "
                f"using default {DEFAULTS['VCS_ENABLED']}"
            )

    # Permission fields
    souffleur_permissions = DEFAULTS["SOUFFLEUR_PERMISSIONS"]
    raw_sp = raw.get("SOUFFLEUR_PERMISSIONS")
    if raw_sp is not None:
        if raw_sp in ALLOWED_PERMISSIONS:
            souffleur_permissions = raw_sp
        else:
            warnings.append(
                f"Invalid SOUFFLEUR_PERMISSIONS='{raw_sp}' "
                f"(allowed: {', '.join(sorted(ALLOWED_PERMISSIONS))}); "
                f"using default {DEFAULTS['SOUFFLEUR_PERMISSIONS']}"
            )

    musician_permissions = DEFAULTS["MUSICIAN_PERMISSIONS"]
    raw_mp = raw.get("MUSICIAN_PERMISSIONS")
    if raw_mp is not None:
        if raw_mp in ALLOWED_PERMISSIONS:
            musician_permissions = raw_mp
        else:
            warnings.append(
                f"Invalid MUSICIAN_PERMISSIONS='{raw_mp}' "
                f"(allowed: {', '.join(sorted(ALLOWED_PERMISSIONS))}); "
                f"using default {DEFAULTS['MUSICIAN_PERMISSIONS']}"
            )

    # Positive integer fields
    int_values = {}
    for key in POSITIVE_INT_KEYS:
        default = DEFAULTS[key]
        raw_val = raw.get(key)
        if raw_val is not None:
            try:
                parsed = int(raw_val)
                if parsed > 0:
                    int_values[key] = parsed
                else:
                    warnings.append(
                        f"Invalid {key}='{raw_val}' (must be positive integer); "
                        f"using default {default}"
                    )
                    int_values[key] = default
            except ValueError:
                warnings.append(
                    f"Invalid {key}='{raw_val}' (must be positive integer); "
                    f"using default {default}"
                )
                int_values[key] = default
        else:
            int_values[key] = default

    # Warn on unknown keys
    known = set(DEFAULTS.keys())
    for key in raw:
        if key not in known:
            warnings.append(f"Ignoring unknown config key '{key}'")

    return {
        "project_dir": resolved_project_dir,
        "project_name": Path(resolved_project_dir).name,
        "terminal_cmd": terminal_cmd,
        "session_layer": session_layer,
        "vcs_enabled": vcs_enabled == "true",
        "souffleur_permissions": souffleur_permissions,
        "musician_permissions": musician_permissions,
        "max_parallel_musicians": int_values["MAX_PARALLEL_MUSICIANS"],
        "degradation_fix_attempts": int_values["DEGRADATION_FIX_ATTEMPTS"],
        "degradation_relaunch_limit": int_values["DEGRADATION_RELAUNCH_LIMIT"],
        "heartbeat_poke_threshold": int_values["HEARTBEAT_POKE_THRESHOLD"],
        "source": source,
        "warnings": warnings,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Conductor config resolver")
    parser.add_argument(
        "--project-dir",
        default=".",
        help="Project directory for .orchestra_configs lookup (default: cwd)",
    )
    args = parser.parse_args()

    project_dir = Path(args.project_dir).resolve()
    result = _resolve(project_dir)

    for warning in result["warnings"]:
        print(f"Warning: {warning}", file=sys.stderr)

    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
