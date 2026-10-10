#!/usr/bin/env python3
"""Walk ~/.claude/projects/*.jsonl and dump human-authored prompts in a window.

Claude Code stores every session as a JSONL file under
  ~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl

Each line is one event. We care about `type:"user"` events whose `message.role`
is "user" and whose `message.content` is a real prompt — not a system caveat,
not a slash-command echo, not a `<local-command-stdout>` blob, and not an
`isMeta` line. The goal is to give the agent enough signal to reconstruct what
the human was actually working on each session.

Output is grouped by project (cwd), then by session, then chronological prompts.
Long prompts are truncated with `--max-chars` (default 600).

Differs from the friday-story version by adding:
  --until        upper-bound date (exclusive end-of-day), for closed windows
  --exclude      substring(s) matched against the session cwd; matching
                 projects are skipped entirely (default: src/personal)

Usage:
  pull-cc-history.py --since 2026-05-22
  pull-cc-history.py --since 2026-06-01 --until 2026-06-01      # just that day
  pull-cc-history.py --since 2026-05-22 --max-chars 400
  pull-cc-history.py --since 2026-05-22 --exclude src/personal --exclude src/secret
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

PROJECTS = Path.home() / ".claude" / "projects"

# Substrings that mark a "user" event as harness chatter, not a real prompt.
NOISE_PREFIXES = (
    "<local-command-caveat>",
    "<command-name>",
    "<command-message>",
    "<command-args>",
    "<local-command-stdout>",
    "<local-command-stderr>",
    "<bash-input>",
    "<bash-stdout>",
    "<bash-stderr>",
    "Caveat:",
)


def extract_text(content) -> str:
    """`message.content` is either a string or a list of {type,text|...} blocks."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(block.get("text", ""))
        return "\n".join(parts)
    return ""


def is_real_prompt(text: str) -> bool:
    t = text.strip()
    if not t:
        return False
    if any(t.startswith(p) for p in NOISE_PREFIXES):
        return False
    if t.startswith("<system-reminder>") and t.endswith("</system-reminder>"):
        return False
    return True


def parse_args():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", required=True, help="ISO date YYYY-MM-DD (inclusive)")
    ap.add_argument(
        "--until",
        default=None,
        help="ISO date YYYY-MM-DD (inclusive day); omit for open-ended",
    )
    ap.add_argument("--max-chars", type=int, default=600)
    ap.add_argument(
        "--exclude",
        action="append",
        default=None,
        help="cwd substring to skip (repeatable). Default: src/personal",
    )
    ap.add_argument(
        "--projects-dir",
        default=str(PROJECTS),
        help="override projects dir (default ~/.claude/projects)",
    )
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    excludes = args.exclude if args.exclude is not None else ["src/personal"]
    # Windows are LOCAL days. Session timestamps are stored UTC; comparing
    # tz-aware instants makes "2026-06-01" mean the user's local June 1, not
    # the UTC day (which would drop evening-local work into the next day).
    local_tz = datetime.now().astimezone().tzinfo
    since = datetime.fromisoformat(args.since).replace(tzinfo=local_tz)
    # `until` is an inclusive day -> compare against start of the next local day.
    until = None
    if args.until:
        until = datetime.fromisoformat(args.until).replace(
            tzinfo=local_tz
        ) + timedelta(days=1)

    root = Path(args.projects_dir)
    if not root.exists():
        print(f"(no projects dir at {root})")
        return 0

    # project_cwd -> session_id -> list[(timestamp, text)]
    sessions: dict[str, dict[str, list[tuple[datetime, str]]]] = defaultdict(
        lambda: defaultdict(list)
    )

    for jsonl in sorted(root.rglob("*.jsonl")):
        try:
            mtime = datetime.fromtimestamp(jsonl.stat().st_mtime, tz=timezone.utc)
        except OSError:
            continue
        if mtime < since:
            continue

        try:
            fh = jsonl.open("r", encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if ev.get("type") != "user" or ev.get("isMeta"):
                    continue
                msg = ev.get("message") or {}
                if msg.get("role") != "user":
                    continue
                cwd = ev.get("cwd") or "(unknown cwd)"
                if any(x and x in cwd for x in excludes):
                    continue
                text = extract_text(msg.get("content"))
                if not is_real_prompt(text):
                    continue
                ts_raw = ev.get("timestamp")
                if not ts_raw:
                    continue
                try:
                    ts = datetime.fromisoformat(ts_raw.replace("Z", "+00:00"))
                except ValueError:
                    continue
                if ts < since:
                    continue
                if until is not None and ts >= until:
                    continue
                sid = ev.get("sessionId") or jsonl.stem
                sessions[cwd][sid].append((ts, text.strip()))

    if not sessions:
        win = args.since + (f"..{args.until}" if args.until else " →")
        print(f"(no Claude Code conversations in window {win})")
        return 0

    def cwd_latest(cwd: str) -> datetime:
        return max(
            (t for sid in sessions[cwd] for t, _ in sessions[cwd][sid]),
            default=datetime.min.replace(tzinfo=timezone.utc),
        )

    for cwd in sorted(sessions.keys(), key=cwd_latest, reverse=True):
        print(f"\n### {cwd}")
        sids = sorted(
            sessions[cwd].keys(),
            key=lambda s: sessions[cwd][s][0][0],
        )
        for sid in sids:
            prompts = sorted(sessions[cwd][sid], key=lambda x: x[0])
            first_ts = prompts[0][0].astimezone(local_tz).date().isoformat()
            short = sid[:8]
            print(f"  session {short} — {first_ts} — {len(prompts)} prompt(s)")
            for ts, text in prompts:
                snippet = text.replace("\n", " ⏎ ")
                if len(snippet) > args.max_chars:
                    snippet = snippet[: args.max_chars - 1] + "…"
                local = ts.astimezone(local_tz)
                print(f"    [{local.strftime('%m-%d %H:%M')}] {snippet}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
