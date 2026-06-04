---
name: jsmntl-iterate
description: Run one disciplined iteration of agentic software work — outer spec red bar → inner test red bar → minimum code green → refactor → quality gates → subagent review → commit. The daily-driver workhorse of the JSMNTL methodology. Works standalone with sensible defaults; sharpens when a calibrated JSMNTL.md is present at the repo root. Use when starting any non-trivial chunk of new work.
---

# JSMNTL Iterate

Your goal: walk one disciplined iteration of agentic software work, designed to defeat the AI failure mode where code "looks right" but doesn't satisfy the spec. The loop is universal; calibration sharpens it.

## Step 0 — Read calibration if present

Check for `JSMNTL.md` at the repo root.

- **If present:** read it. Honor the calibrated spec language, ADR policy, forcing-function tag, subagent cadence, push policy, and named single-writer seams. Use the calibrated answers throughout this iteration.
- **If absent:** use the defaults below and silently skip calibration-dependent disciplines (forcing-function commit tag, single-writer seam alerts).

| Decision | With JSMNTL.md | Default |
|---|---|---|
| Spec language | Calibrated | `tck/` or `features/` exists → Gherkin; else use repo's existing test framework |
| ADR? | Calibrated | If `decisions/` dir exists → yes; else propose creating one for architectural changes |
| Forcing-function commit tag | Calibrated tag (e.g. `composes-with-X:`) | None |
| Issue tracker | Calibrated | `.beads/` → beads; else `gh` if remote → GitHub Issues; else inline TODO with stable ID |
| Subagent passes | Calibrated cadence | Code-review at end-of-iteration; red-team only for auth / ingress / secrets / threat-boundary code |
| Push policy | Calibrated | Always ask before any push |
| Single-writer seams | Named in JSMNTL.md → alert before edits | None tracked |

## Step 1 — Orient

Identify what work you're doing. In order of preference:
1. The user's explicit ask in this turn.
2. The next ready issue from the project's tracker (`bd ready` if beads; `gh issue list --assignee @me` if GitHub).
3. Ask the user.

**Confirm the work in one sentence to the user before doing anything.** ("Working on: add S3 sink trait impl for sealer output.") Wait for confirmation if there's any ambiguity.

If this is **architectural work** (new public type, new trait, new schema, new external dependency, new persistence layer, change to a named single-writer seam) and the repo uses ADRs: **draft the ADR first**, in `decisions/<YYYY-MM-DD>-<slug>.md`, Status: Proposed. Include rejection section ("what was on the table, why each alternative was rejected") and "what this does NOT gate" anti-scope-creep clause. Get user sign-off on the ADR shape before writing code.

## Step 2 — Outer spec, red bar

Write the behavioral spec in the repo's spec language. This is *what the change must achieve, expressed from outside the code* — not implementation pseudocode.

- **Gherkin**: write the `.feature` file under `tck/<area>/features/` or wherever the repo's convention is. Scenario should read as observable behavior, not as a Rust/Python/TS call site.
- **Property tests**: write the property statement (e.g. `for any valid input, sink.append(x) followed by sink.read(x.id) returns x`).
- **Doctests / golden files / type-level**: appropriate equivalent.
- **No existing harness**: write a plain integration test in the highest-level form the repo supports.

Run it. **Confirm it fails for the right reason** (missing impl, not syntax error). Show the user the red bar.

## Step 3 — Inner test, red bar

Write the unit/integration test that pins the same claim at the implementation layer. This is the test that lives close to the code; the outer spec lives close to the contract.

Run it. **Confirm it fails for the right reason.** Both red bars must be live before any production code is written.

## Step 4 — Minimum code, green

Implement *only* what's required to turn both red bars green. Resist:
- Premature abstractions ("while I'm here, let me extract a helper")
- Adjacent cleanups ("this nearby code is ugly, let me fix it too")
- Speculative interfaces ("we'll probably want async later, let me prep for it")
- Defensive error handling for cases that can't happen

Run both tests. **Both must be green.**

If a named single-writer seam is being touched (from JSMNTL.md), flag it explicitly to the user: *"This change modifies `<seam>`, a named single-writer surface. Pausing for sign-off."* Wait for explicit go-ahead.

## Step 5 — Refactor with green

Clean up *inside the green*. Tests must stay green throughout. Common moves:
- Extract a function once you can name it from the test
- Rename variables / functions for clarity
- Remove dead code introduced during exploration
- Tighten types / constraints

Skip this step if there's nothing to do. Don't manufacture refactoring to feel productive.

## Step 6 — Quality gates

Run the repo's standard checks. Common shapes:
- Rust: `cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test`
- TypeScript: `pnpm lint && pnpm typecheck && pnpm test`
- Python: `ruff check && mypy && pytest`
- Look for `xtask ci` / `make ci` / `npm run ci` / equivalent first; use it if it exists.

Fix all failures. Do not commit through warnings unless the user has explicitly approved.

## Step 7 — Subagent review

Decide which passes apply (calibrated cadence > defaults):

- **Code-review subagent** at end-of-iteration on non-trivial work. Brief it on what the change does, what spec it satisfies, and what to look for.
- **Red-team subagent** if the change touches: authentication, authorization, data ingress, secrets, threat-model boundaries, anything that holds user data, anything that crosses a trust boundary. Brief it on the threat surface; ask what attacks the design *doesn't* defend against.
- **Skip both** for trivial work (doc typo, dependency bump with green tests, one-line bug fix) unless the user asks.

Report findings; fix or risk-accept each with the user.

## Step 8 — Commit

One commit per concern. Message structure:

```
<area>: <imperative summary>

<one or two paragraphs explaining why, not what>

<calibrated-forcing-function-tag>: <yes | no [rationale] | TBD [what would resolve]>
<closes-issue-ref>
```

The forcing-function tag is only included if JSMNTL.md defines one. Issue ref uses the project's tracker convention (e.g., `Closes thunderdome-XXX`).

**Do not push.** Discipline #9: every push needs explicit user approval per push. If the user wants to push, they'll say so — and you'll confirm before running it.

## Step 9 — Loop or close

- More red bars to chase? → back to Step 2.
- Work complete? → summarize what changed, name any beads/issues filed for deferred work, point at the commit. Stop.

## Anti-patterns to refuse

- **Writing code before both red bars exist.** Non-negotiable. The bar isn't "I have a test"; it's "I have two tests that fail for the right reasons before I write the code."
- **Skipping the outer spec because "the unit test covers it."** They serve different purposes. Outer = contract; inner = implementation.
- **Bundling concerns into one commit.** Split before committing.
- **Pushing without explicit approval.** Even after the user said "commit and ship" — confirm the push separately. Their approval is for scope, not for every successive action.
- **Refactoring outside green.** If tests are red during a refactor, you're not refactoring — you're guessing.
- **Inventing a forcing-function tag.** Only use one if JSMNTL.md says to. Don't slap `composes-with-X:` on commits in repos that haven't named their X.
- **Filing an ADR for non-architectural work.** Bug fixes, refactors, doc changes, dep bumps don't need ADRs. Save them for choices that shape the codebase's future.
