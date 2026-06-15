#!/usr/bin/env python3
import json
import os
import sys
import time

try:
    payload = json.loads(sys.stdin.read() or "{}")
except Exception:
    raise SystemExit(0)

hook_event = payload.get("hook_event_name") or ""
if hook_event == "Notification":
    raise SystemExit(0)
if hook_event not in {"PermissionRequest", "Elicitation", "Stop", "StopFailure"}:
    raise SystemExit(0)

support_dir = os.path.expanduser("~/Library/Application Support/CodingNotificator")
event_path = os.path.join(support_dir, "event.json")
os.makedirs(support_dir, exist_ok=True)

message = payload.get("message") or ""
cwd = payload.get("cwd") or ""
project = os.path.basename(cwd) if cwd else "Claude Code"

if hook_event in {"PermissionRequest", "Elicitation"}:
    event = "needs_input"
    title = "Claude needs input"
    if not message:
        tool = payload.get("tool_name")
        message = f"Claude is waiting on {tool}" if tool else "Claude is waiting for you"
elif hook_event == "StopFailure":
    event = "failed"
    title = "Claude failed"
    message = message or "Claude Code hit an error"
else:
    event = "done"
    title = f"Done: {project}"
    message = message or "Claude Code finished"

notifier_payload = {
    "event": event,
    "source": "claude",
    "title": title,
    "message": message,
    "timestamp": int(time.time()),
    "properties": {
        "hook_event_name": hook_event,
        "session_id": payload.get("session_id"),
        "cwd": cwd,
        "transcript_path": payload.get("transcript_path"),
    },
}

with open(event_path, "a", encoding="utf-8") as handle:
    handle.write(json.dumps(notifier_payload, separators=(",", ":")))
    handle.write("\n")
