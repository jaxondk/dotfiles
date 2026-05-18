#!/usr/bin/env python3
"""Migrate one Claude Code conversation to a new project dir.

Rewrites every `cwd` field in the session's jsonl (and any subagent jsonls)
whose path no longer exists at /Users/jaxon.keeler/src/<X> but does exist at
/Users/jaxon.keeler/src/firecrew-ecosystem/<X>, then relocates the conversation
files into the project dir corresponding to the remapped primary cwd.

Usage:
    migrate_conversation.py <session-jsonl-path> [--dry-run] [--apply]

By default runs in dry-run mode (prints planned actions, no changes).
Pass --apply to perform the move.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
from pathlib import Path

PROJECTS_ROOT = Path.home() / ".claude" / "projects"
SRC_OLD = "/Users/jaxon.keeler/src/"
SRC_NEW_PREFIX = "/Users/jaxon.keeler/src/firecrew-ecosystem/"


def encode_cwd(cwd: str) -> str:
    """Encode a filesystem path the way Claude Code names project dirs.

    Both `/` and `.` are replaced with `-`.
    """
    return re.sub(r"[/.]", "-", cwd)


def remap_cwd(cwd: str) -> str | None:
    """Return remapped cwd, or None if no remap applies."""
    if not cwd.startswith(SRC_OLD):
        return None
    rest = cwd[len(SRC_OLD):]
    # Already under firecrew-ecosystem? nothing to do.
    if rest.startswith("firecrew-ecosystem/") or rest == "firecrew-ecosystem":
        return None
    old_path = Path(cwd)
    new_path = Path(SRC_NEW_PREFIX + rest)
    if old_path.exists():
        # Original still there; don't remap.
        return None
    if not new_path.exists():
        return None
    return str(new_path)


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


def rewrite_file(jsonl_path: Path, cwd_map: dict[str, str], dry_run: bool) -> int:
    """Rewrite cwd fields in-place. Returns number of lines changed."""
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
            if isinstance(cwd, str) and cwd in cwd_map:
                obj["cwd"] = cwd_map[cwd]
                changed += 1
                new_lines.append(json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n")
            else:
                new_lines.append(line)
    if changed and not dry_run:
        tmp = jsonl_path.with_suffix(jsonl_path.suffix + ".tmp")
        tmp.write_text("".join(new_lines))
        tmp.replace(jsonl_path)
    return changed


def migrate(jsonl_path: Path, dry_run: bool) -> bool:
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

    primary_cwd = cwds[0]
    cwd_map: dict[str, str] = {}
    for c in cwds:
        new = remap_cwd(c)
        if new and new != c:
            cwd_map[c] = new

    if not cwd_map:
        print(f"  skip: no remappable cwds in {jsonl_path.name} (cwds: {cwds})")
        return False

    new_primary = cwd_map.get(primary_cwd, primary_cwd)
    new_project_dirname = encode_cwd(new_primary)
    new_project_dir = PROJECTS_ROOT / new_project_dirname

    print(f"  session: {session_id}")
    print(f"  old project: {old_project_dir.name}")
    print(f"  new project: {new_project_dirname}")
    print(f"  primary cwd: {primary_cwd} -> {new_primary}")
    if len(cwd_map) > 1:
        for k, v in cwd_map.items():
            if k != primary_cwd:
                print(f"    extra cwd: {k} -> {v}")

    # Files to rewrite: main jsonl + any subagent jsonls.
    targets = [jsonl_path]
    if sidecar_dir.is_dir():
        for p in sidecar_dir.rglob("*.jsonl"):
            targets.append(p)

    total_changed = 0
    for t in targets:
        n = rewrite_file(t, cwd_map, dry_run)
        total_changed += n
        if n:
            print(f"  rewrite {t.relative_to(old_project_dir.parent)}: {n} cwd lines")

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
            print(f"  [dry-run] no move needed (primary cwd unchanged); only rewrite")
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
        print(f"  rewrite only (primary cwd unchanged, no move)")
    print(f"  done. {total_changed} cwd lines rewritten.")
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("jsonl", help="path to session .jsonl file")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--dry-run", action="store_true", default=True)
    g.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    dry_run = not args.apply
    print(f"{'[DRY-RUN] ' if dry_run else ''}migrating {args.jsonl}")
    ok = migrate(Path(args.jsonl).expanduser(), dry_run=dry_run)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
