#!/usr/bin/env python3
"""Migrate one Claude Code conversation to a new project dir.

Rewrites `cwd` metadata fields whose value equals the session's *primary*
cwd (the top-level agent's starting working directory) to `--to`, then moves
the conversation files into the project dir corresponding to that path.
Lines where the agent genuinely worked in a different cwd (e.g. it cd'd into
a subdir) are left untouched — the session keeps its real per-turn cwd
history; only the "session home" identity changes.

Usage:
    migrate-conversation.py <session-jsonl> --to <NEW_CWD> [--from <OLD_CWD>] [--dry-run|--apply]

`--to` is an absolute filesystem path. If `--from` is omitted, the script
uses the first cwd seen in the jsonl. Defaults to dry-run; pass --apply to
perform the move.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

PROJECTS_ROOT = Path.home() / ".claude" / "projects"


def encode_cwd(cwd: str) -> str:
    """Encode a filesystem path the way Claude Code names project dirs.

    Both `/` and `.` are replaced with `-`.
    """
    return re.sub(r"[/.]", "-", cwd)


def collect_cwds(jsonl_path: Path) -> list[str]:
    cwds: list[str] = []
    seen: set[str] = set()
    with jsonl_path.open() as f:
        for line in f:
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            cwd = obj.get("cwd")
            if isinstance(cwd, str) and cwd not in seen:
                seen.add(cwd)
                cwds.append(cwd)
    return cwds


def rewrite_file(jsonl_path: Path, old_cwd: str, new_cwd: str, dry_run: bool) -> int:
    """Rewrite cwd fields equal to old_cwd, replacing with new_cwd. Returns lines changed."""
    changed = 0
    new_lines: list[str] = []
    with jsonl_path.open() as f:
        for line in f:
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                new_lines.append(line)
                continue
            cwd = obj.get("cwd")
            if isinstance(cwd, str) and cwd == old_cwd and cwd != new_cwd:
                obj["cwd"] = new_cwd
                changed += 1
                new_lines.append(json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n")
            else:
                new_lines.append(line)
    if changed and not dry_run:
        tmp = jsonl_path.with_suffix(jsonl_path.suffix + ".tmp")
        tmp.write_text("".join(new_lines))
        tmp.replace(jsonl_path)
    return changed


def migrate(jsonl_path: Path, old_cwd: str | None, new_cwd: str, dry_run: bool) -> bool:
    if not jsonl_path.is_file():
        print(f"  ERROR: not a file: {jsonl_path}")
        return False
    session_id = jsonl_path.stem
    old_project_dir = jsonl_path.parent
    sidecar_dir = old_project_dir / session_id  # may hold subagents/

    cwds = collect_cwds(jsonl_path)
    if not cwds:
        print(f"  skip: no cwd in {jsonl_path.name}")
        return False
    if old_cwd is None:
        old_cwd = cwds[0]
        print(f"  inferred --from (primary cwd): {old_cwd}")
    elif old_cwd not in cwds:
        print(f"  ERROR: --from {old_cwd} not found in session cwds: {cwds}")
        return False
    new_project_dirname = encode_cwd(new_cwd)
    new_project_dir = PROJECTS_ROOT / new_project_dirname

    print(f"  session: {session_id}")
    print(f"  old project: {old_project_dir.name}")
    print(f"  new project: {new_project_dirname}")
    print(f"  rewrite: {old_cwd} -> {new_cwd}")
    other = [c for c in cwds if c != old_cwd]
    if other:
        print(f"  preserving other cwds (untouched): {other}")

    # Files to rewrite: main jsonl + any subagent jsonls.
    targets = [jsonl_path]
    if sidecar_dir.is_dir():
        for p in sidecar_dir.rglob("*.jsonl"):
            targets.append(p)

    total_changed = 0
    for t in targets:
        n = rewrite_file(t, old_cwd, new_cwd, dry_run)
        total_changed += n
        if n:
            rel = t.relative_to(old_project_dir.parent)
            print(f"  rewrite {rel}: {n} cwd lines")

    # Compute destinations.
    dest_jsonl = new_project_dir / jsonl_path.name
    dest_sidecar = new_project_dir / session_id

    move_needed = new_project_dir.resolve() != old_project_dir.resolve()

    if move_needed:
        if dest_jsonl.exists():
            print(f"  ERROR: destination already exists: {dest_jsonl}")
            return False
        if sidecar_dir.is_dir() and dest_sidecar.exists():
            print(f"  ERROR: destination sidecar already exists: {dest_sidecar}")
            return False

    if dry_run:
        if move_needed:
            print(f"  [dry-run] would mkdir {new_project_dir}")
            print(f"  [dry-run] would move {jsonl_path.name} -> {dest_jsonl}")
            if sidecar_dir.is_dir():
                print(f"  [dry-run] would move {sidecar_dir.name}/ -> {dest_sidecar}")
        else:
            print(f"  [dry-run] no move needed (already in target project dir); only rewrite")
        print(f"  [dry-run] total cwd lines that would be rewritten: {total_changed}")
        return True

    if move_needed:
        new_project_dir.mkdir(parents=True, exist_ok=True)
        shutil.move(str(jsonl_path), str(dest_jsonl))
        print(f"  moved -> {dest_jsonl}")
        if sidecar_dir.is_dir():
            shutil.move(str(sidecar_dir), str(dest_sidecar))
            print(f"  moved -> {dest_sidecar}")
    else:
        print(f"  rewrite only (already in target project dir)")
    print(f"  done. {total_changed} cwd lines rewritten.")
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("jsonl", help="path to session .jsonl file")
    ap.add_argument("--to", dest="dst", required=True, help="target cwd (absolute path)")
    ap.add_argument("--from", dest="src", default=None,
                    help="cwd to rewrite (absolute path); defaults to the first cwd seen in the jsonl")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--dry-run", action="store_true", default=True)
    g.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    dry_run = not args.apply
    from_str = args.src if args.src else "<primary cwd>"
    print(f"{'[DRY-RUN] ' if dry_run else ''}migrating {args.jsonl}: {from_str} -> {args.dst}")
    ok = migrate(Path(args.jsonl).expanduser(), args.src, args.dst, dry_run=dry_run)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
