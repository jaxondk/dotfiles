---
name: jsmntl-calibrate
description: Interview the user about the current repo and produce a calibrated JSMNTL.md — a per-repo discipline file containing only the practices that earn their keep, with project-specific instantiations. Use when the user wants to adapt JSMNTL (Patrick Beam's "Jane Street's Most Neurotic Tech Lead" methodology) to a new codebase. Refuses to ship a generic checklist; the calibration interview is the point.
---

# JSMNTL Calibrator

Your goal: produce a `JSMNTL.md` at the repo root that contains **only** the disciplines that fit this codebase, with each one calibrated to its specific shape.

**The single most important thing this skill does is be willing to drop disciplines.** A generic JSMNTL.md is theater. A 30-line calibrated JSMNTL.md for a low-gravity repo is more honest — and more in keeping with JSMNTL's own Law VII (no uncritical inheritance) — than a 300-line copy-paste.

## What JSMNTL is (background, kept inline so this skill is self-contained)

JSMNTL stands for **Jane Street's Most Neurotic Tech Lead** — Patrick Beam's name for a discipline refined through the `lemonade` → `given/` → `substrate/` → `thunderdome` lineage. The reference instantiation lives in `~/src/thunderdome/CLAUDE.md` ("Way of working — JSMNTL").

The kernel: **make every load-bearing decision discoverable, reversible, and named, while making every load-bearing invariant mechanically unviolatable.**

The 13 universal disciplines:

1. **Spec-before-code (TCK-first)** — outer behavioral spec (Gherkin/property test/doctest/etc.) red bar → inner unit test red bar pinning the same claim → minimum code to green → refactor with green tests.
2. **ADRs with rejection sections** — every architectural decision recorded in `decisions/<YYYY-MM-DD>-<slug>.md`. Status field (Proposed/Decided/Superseded/Withdrawn). Includes *what was rejected and why*, plus a *"what this does NOT gate"* anti-scope-creep clause.
3. **Issue tracker for every "we'll come back to this"** — file or lose. Tool-agnostic (beads, Linear, GitHub Issues, plain text).
4. **Mechanical enforcement of load-bearing invariants** — if a rule matters, make it physically impossible to violate. Append-only triggers, `#[non_exhaustive]`, object lock, type-system constraints, schema validation in CI. Convention-only invariants are a lie waiting to happen.
5. **Forcing-function commit tag** for the project's load-bearing external commitment (Thunderdome uses `composes-with-substrate: yes/no/TBD`). Only applies if such a commitment exists.
6. **Exact-pin dependencies** on byte/behavior-stable surfaces (`=0.2.0` not `^0.2.0`). Treat upgrades there as explicit campaigns. Only applies where bytes/behavior must be stable.
7. **No uncritical inheritance** — every non-trivial choice carries a *why-we-chose-this* note. Patterns from FAANG/arXiv/popular libraries come in as confirmations, never as canon.
8. **Small PRs, one concern per commit.**
9. **Never push without explicit approval** — `git push` / `gt submit` / `gh pr create --push` always per-push.
10. **Subagent review at meaningful boundaries** — code-review + red-team passes at new public types, traits, migrations, ADRs, end-of-PR.
11. **Single-writer seams named explicitly** — designate which files/paths are sole writers of load-bearing state; PRs touching them need invariant-owner sign-off.
12. **Pay in cheap resource before expensive resource** — name the project's primary tradeoff axis (disk vs speed / latency vs correctness / dev velocity vs reliability) and lean consistently.
13. **Disconfirmation all the way down** — the test apparatus is itself on trial; property-test the test grammar.

The honest caveat: JSMNTL pays for itself on systems where **bytes-on-disk are evidence** (audit logs, financial ledgers, scientific instruments, compilers, distributed-systems coordination, regulated software). On low-gravity systems (CRUD apps, scripts, research notebooks, prototypes) most of it is overhead.

## Step 1 — Check for existing JSMNTL.md

If `JSMNTL.md` exists at the repo root, ask the user: recalibrate (overwrite), update specific sections, or abort. Do not silently overwrite.

## Step 2 — Survey before interviewing

Form a working hypothesis about gravity and shape *before* asking. Don't ask blind. Read at minimum:

- `README.md` — what is this thing?
- `CLAUDE.md` / `AGENTS.md` if present — operating context
- Top-level directory structure
- `package.json` / `Cargo.toml` / `pyproject.toml` / `go.mod` / equivalent — stack, library vs service vs app
- `.github/workflows/` if present — what's already mechanized
- Recent `git log --oneline -20` — pace and shape of changes

Note your hypothesis briefly to the user before the interview ("Looks like a small Python data pipeline with no external consumers — I'm guessing low-to-medium gravity. Let me confirm.")

## Step 3 — The calibration interview

Ask these in tight clusters, letting answers shape follow-ups. Push back on cargo-culted answers; if the user can't give a project-specific reason for a discipline, drop it.

### Gravity (the most important question)
- "What does this project lose if it gets a load-bearing fact wrong? (best→worst: 'fix it next deploy' / 'embarrassing bug report' / 'data corruption' / 'compliance or safety incident' / 'irrecoverable')"
- "Who is harmed when something breaks? (just you / your team / paying customers / regulated parties / the public)"
- "How long does a bug typically live before someone notices?"

**If gravity is low across the board: say so out loud and propose a minimal calibration.** Probably just disciplines 1, 2 (light), 3, 7, 8. Ship a 30-line JSMNTL.md. Resist the urge to fill space.

### Shape
- "What's the durable output that has to be right? (the *artifact*)"
- "Is there an external thing this repo must remain compatible with? A public API, a downstream consumer schema, a sibling project/repo, an RFC, an oncall runbook? Name it concretely or say 'none.'"
- "What rules, if violated, mean the system is broken? (append-only? deterministic? idempotent? type-safe? reproducible builds? schema-stable?)"
- "Are there surfaces where exactly one code path should write? (single-writer seams)"
- "Is there serialization, hashing, signatures, snapshot tests, or wire formats where a silent SemVer bump on a dependency could change observable behavior without your code changing?"
- "What's the project's primary tradeoff axis, and which way does it lean? (disk vs speed / latency vs correctness / dev velocity vs reliability / memory vs simplicity / flexibility vs safety)"
- "What's the natural spec language here? (Gherkin / property tests / doctests / golden files / type-level / 'we don't have one yet')"
- "What's already mechanized vs convention-only?" (Probe specifics — "you said tests run in CI, but is the lint also `-D warnings`? Is the type checker actually failing the build?")

### Cadence
- "What change types warrant a code-review subagent pass?"
- "What change types warrant a red-team subagent pass? (Probably: auth, data ingress, anything that crosses a trust boundary, anything new that holds secrets or PII.)"
- "Is 'never push without approval' the right default for this repo, or are you a solo dev who wants to push freely?"

## Step 4 — Decide per discipline

For each of the 13 disciplines, decide:

- **Keep** — applies cleanly; instantiate with project specifics (file paths, tool names, exact criteria)
- **Adapt** — applies in modified form; describe the modification
- **Drop** — not load-bearing here; record *why* in the "deliberately omitted" section

Be willing to drop. Specifically:

- **#5 (forcing-function tag)** — drop unless there's a *named, concrete* external commitment. Don't invent one.
- **#6 (exact-pin)** — drop unless there's a named byte-stability surface. Don't blanket-pin everything.
- **#10 (subagent review)** — drop or scale down if the user is a solo dev on a low-stakes repo.
- **#11 (single-writer seams)** — drop unless invariants exist that depend on serialization of writes.
- **#13 (disconfirmation)** — drop unless there's a *test apparatus* sophisticated enough to need its own tests.
- **#9 (no push without approval)** — make it a default the user can override per their stated preference.

## Step 5 — Write JSMNTL.md

Use this structure. **Length proportional to gravity** — low-gravity gets 30 lines, high-gravity gets 200+. Resist ceremony.

```markdown
# JSMNTL — Calibrated for <repo name>

**Calibrated:** <YYYY-MM-DD>
**Gravity:** <low | medium | high> — <one-line justification>
**Load-bearing artifact:** <what has to be right>
**External commitments:** <list, or "none">
**Primary tradeoff axis:** <X vs Y, leaning toward Z>
**Spec language:** <choice, or "informal — kept lightweight given gravity">

## Disciplines that apply here

### <N>. <Discipline name>
**Why it applies:** <project-specific reason — not generic>
**How to apply it here:** <concrete instantiation: file paths, tool names, naming conventions, exact criteria>

<... only the disciplines that earned their keep ...>

## Disciplines deliberately omitted

- **<Discipline name>** — <why this repo doesn't need it>
<...>

## Calibration interview answers

<the user's answers verbatim, so future-you can recalibrate against the original premises>
```

## Step 6 — Confirm

Show the file. Ask if anything's miscalibrated. Iterate. Once accepted, suggest:

- Referencing `JSMNTL.md` from `CLAUDE.md` / `AGENTS.md` if those exist (so future Claude sessions pick it up)
- Recalibrating after major architectural shifts (new external commitment, gravity change, new persistence layer)

Do **not** push, commit, or open a PR for the new file without explicit approval — that's discipline #9 in action, and this skill should model it.

## Anti-patterns to refuse

- **Generating JSMNTL.md without an interview.** The interview *is* the point. A skipped interview produces theater.
- **Including a discipline the user can't give a project-specific reason for.** If they say "I guess we should have ADRs" — push back. Either find the reason or drop it.
- **Padding low-gravity repos.** A 30-line JSMNTL.md is a success, not a failure.
- **Verbatim importing of substrate/Thunderdome-specific names** — `composes-with-substrate:`, `sherlock` bucket, RFC 6962 Merkle, `#[non_exhaustive]`. These are *examples* of what discipline X looks like in one specific project. Find the local analog or drop the discipline.
- **Treating the 13-list as a checklist.** It's a template for noticing. The work is finding what fits.
