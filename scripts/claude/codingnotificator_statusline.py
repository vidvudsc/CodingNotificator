#!/usr/bin/env python3
import json
import os
import tempfile
import sys
import time

raw = sys.stdin.read()
support_dir = os.path.expanduser("~/Library/Application Support/CodingNotificator")
cache_path = os.path.join(support_dir, "claude-usage.json")
os.makedirs(support_dir, exist_ok=True)

try:
    payload = json.loads(raw)
except Exception:
    print("Claude Code")
    raise SystemExit(0)

cached_payload = {}
try:
    with open(cache_path, "r", encoding="utf-8") as handle:
        cached_payload = json.load(handle)
except Exception:
    cached_payload = {}


def valid_window(window):
    return (
        isinstance(window, dict)
        and isinstance(window.get("used_percentage"), (int, float))
        and isinstance(window.get("resets_at"), (int, float))
        and window["resets_at"] > time.time()
    )


def should_accept_window(new_window, old_window):
    if not valid_window(new_window):
        return False
    if not valid_window(old_window):
        return True

    new_reset = new_window["resets_at"]
    old_reset = old_window["resets_at"]
    new_used = new_window["used_percentage"]
    old_used = old_window["used_percentage"]

    if new_reset > old_reset:
        return True
    if new_reset < old_reset:
        return False

    return new_used >= old_used


incoming_rate_limits = payload.get("rate_limits") or {}
cached_rate_limits = cached_payload.get("rate_limits") or {}
merged_rate_limits = dict(cached_rate_limits)

for window_name in ("five_hour", "seven_day"):
    new_window = incoming_rate_limits.get(window_name)
    old_window = cached_rate_limits.get(window_name)
    if should_accept_window(new_window, old_window):
        merged_rate_limits[window_name] = new_window

payload["rate_limits"] = merged_rate_limits
payload["codingnotificator_cached_at"] = int(time.time())

if merged_rate_limits:
    fd, tmp_path = tempfile.mkstemp(prefix="claude-usage.", dir=support_dir)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, separators=(",", ":"))
        handle.write("\n")
    os.replace(tmp_path, cache_path)

rate_limits = merged_rate_limits


def remaining_percent(window_name):
    window = rate_limits.get(window_name) or {}
    value = window.get("used_percentage")
    if isinstance(value, (int, float)):
        return max(0, min(100, round(100 - value)))
    return None


parts = []
five_hour = remaining_percent("five_hour")
seven_day = remaining_percent("seven_day")

if five_hour is not None:
    parts.append(f"5h left {five_hour}%")
if seven_day is not None:
    parts.append(f"7d left {seven_day}%")

context = ((payload.get("context_window") or {}).get("used_percentage"))
if isinstance(context, (int, float)):
    parts.append(f"ctx {round(context)}%")

print("Claude " + " / ".join(parts) if parts else "Claude Code")
