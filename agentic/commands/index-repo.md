---
name: index-repo
type: command
description: Deeply index a repo for AI discoverability by generating nested AGENTS.md reference docs
---

# Index Repo for AI Discoverability

Your goal: make this repository maximally understandable to AI coding agents by generating a hierarchy of `AGENTS.md` reference docs — one at the root plus one per major subsystem.

These docs are **architectural references**, not behavioral instructions. They describe how the code fits together so future agents (and the user) can quickly build an accurate mental model of the codebase.

## Step 1 — Detect existing AGENTS.md files

Run:

```
find . -type f \( -name "AGENTS.md" -o -name "agents.md" \) \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/.venv/*" \
  -not -path "*/venv/*" \
  -not -path "*/dist/*" \
  -not -path "*/build/*" \
  -not -path "*/target/*" \
  -not -path "*/.next/*"
```

**If ANY files are found: STOP. Do NOT generate anything.** These are likely user-authored and must not be clobbered. Inform the user what you found and present these options, then wait for their choice:

---

### Option A — Pointer in root `AGENTS.md` → separate `CODEMAP.md` files

Generate a separate hierarchy of `CODEMAP.md` files (machine-owned architectural reference), and append a delimited section to the root `AGENTS.md` pointing agents at them. Doesn't touch existing content.

```md
<!-- CODEMAP-INDEX-START -->
## Architectural Reference

Machine-generated architectural docs live in `CODEMAP.md` files throughout
this repo. When working in a subdirectory, load the nearest `CODEMAP.md`
(walking upward) for structural context. Regenerate via `/index-repo`.
<!-- CODEMAP-INDEX-END -->
```

**Pros**: zero conflict with user content. **Cons**: relies on agent following the pointer.

---

### Option B — Harness-specific config only

Generate `CODEMAP.md` files and wire each harness natively. No `AGENTS.md` modifications.

Detect which harnesses the user uses (ask or infer from existing config files), then write:

- **Claude Code** → `.claude/settings.json` with a SessionStart hook that lists or injects `CODEMAP.md` paths
- **Cursor** → `.cursor/rules/codemap.mdc` with `alwaysApply: true` frontmatter, pointing at `CODEMAP.md` files
- **OpenCode** → `opencode.json` with `"instructions": ["**/CODEMAP.md"]`
- **Pi** → `.pi/APPEND_SYSTEM.md` with a pointer

**Pros**: guaranteed auto-load per harness, no content duplication. **Cons**: config per harness.

---

### Option C — Append delimited indexing section to each existing `AGENTS.md`

For each existing `AGENTS.md`, append a delimited `<!-- CODEMAP-INDEX-START -->` / `<!-- CODEMAP-INDEX-END -->` section containing the architectural reference for that directory. Idempotent (re-running replaces only the delimited block).

**Pros**: single file per location, guaranteed auto-load via standard discovery. **Cons**: mixes machine-generated content into user-authored files.

---

After the user picks an option, execute it. For CODEMAP-based options (A, B), generate the same hierarchical reference content described in Step 2 but using the filename `CODEMAP.md` instead of `AGENTS.md`.

## Step 2 — If NO AGENTS.md files exist, do deep indexing

Generate a hierarchy of `AGENTS.md` files (uppercase — per the [spec](https://agents.md/)):

1. **Explore broadly first**
   - Read the repo root: `README.md`, any `CLAUDE.md`, top-level configs (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, etc.), the main entry points
   - Identify top-level subsystem directories (anything that looks like a distinct module/package)

2. **Spawn parallel Explore subagents** — one per major top-level directory. Each should:
   - Read every source file in that subtree (or sample intelligently if huge)
   - Note: key classes, their inheritance chains, core methods, design patterns, how they connect to other subsystems
   - Return a detailed report (not just a file list)

3. **Synthesize a root `AGENTS.md`** covering:
   - What the system IS (one clear sentence) and what it ENABLES (not superficial)
   - High-level architecture diagram (ASCII block diagram is fine)
   - How the major subsystems fit together — the actual wiring
   - Key shared primitives/concepts
   - Entry points and the "singleton pattern" if one exists
   - An index of subdirectory `AGENTS.md` files with one-line descriptions each

4. **Write per-subsystem `AGENTS.md`** files. Each should cover:
   - What this subsystem does
   - Core classes and their relationships
   - Key methods/APIs
   - How it connects to other subsystems
   - Notable design patterns

5. **Verify case-sensitivity**: on macOS (case-insensitive FS), if any existing `agents.md` collides with the new `AGENTS.md`, use the `git mv agents.md agents.md.tmp && git mv agents.md.tmp AGENTS.md` two-step to force git to track the rename.

## Style rules for the generated docs

- **Architectural, not behavioral** — these describe the code, not how to work with it. Don't duplicate `CLAUDE.md`/`README.md` content.
- **Dense and specific** — real class names, real method names, file paths. Avoid fluff.
- **Terse headers, prose where it matters** — explain the *why* of non-obvious design choices.
- **Mark machine-generated files** with a header comment at the top:
  ```md
  <!-- Auto-generated by /index-repo. Safe to regenerate. -->
  ```
- **No emojis.** Clean markdown.

## Important constraints

- Do NOT modify any source code.
- Do NOT create docs for trivial directories (e.g., `__pycache__`, empty `__init__.py`-only dirs, test fixtures).
- Prefer nesting depth of 1-2 (root + subsystem). Only go deeper if a subsystem is genuinely complex.
- If a file would be shorter than ~15 lines of real content, roll it up into the parent instead.
- Work in parallel wherever possible (parallel subagent exploration, parallel file writes).
