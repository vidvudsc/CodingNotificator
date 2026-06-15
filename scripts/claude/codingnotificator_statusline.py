#!/usr/bin/env python3
import json
import os
import tempfile
import sys

raw = sys.stdin.read()
support_dir = os.path.expanduser("~/Library/Application Support/CodingNotificator")
cache_path = os.path.join(support_dir, "claude-usage.json")
os.makedirs(support_dir, exist_ok=True)

if raw.strip():
    fd, tmp_path = tempfile.mkstemp(prefix="claude-usage.", dir=support_dir)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(raw)
        handle.write("\n")
    os.replace(tmp_path, cache_path)

try:
    payload = json.loads(raw)
except Exception:
    print("Claude Code")
    raise SystemExit(0)

rate_limits = payload.get("rate_limits") or {}


def used_percent(window_name):
    window = rate_limits.get(window_name) or {}
    value = window.get("used_percentage")
    if isinstance(value, (int, float)):
        return max(0, min(100, round(value)))
    return None


parts = []
five_hour = used_percent("five_hour")
seven_day = used_percent("seven_day")

if five_hour is not None:
    parts.append(f"5h {five_hour}%")
if seven_day is not None:
    parts.append(f"7d {seven_day}%")

context = ((payload.get("context_window") or {}).get("used_percentage"))
if isinstance(context, (int, float)):
    parts.append(f"ctx {round(context)}%")

print("Claude " + " / ".join(parts) if parts else "Claude Code")
