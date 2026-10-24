# Coding Conventions

**Analysis Date:** 2026-08-21

## Repository Nature

This repo ("coter-config" / "openclaw-docker-config") is a **configuration and AI-agent-tooling repository**, not an application codebase. It contains:
- `docker/` — Dockerfiles and compose config for deploying "OpenClaw" (gateway + workspace-sync images)
- `config/` — runtime JSON/Markdown config (`config/openclaw.json`, `config/security-rules.md`, `config/skills-manifest.txt`)
- `scripts/` — Bash operational scripts (`scripts/validate-config.sh`, `scripts/check-secrets.sh`, `scripts/build-and-push.sh`)
- `.claude/`, `.codex/`, `.cursor/` — three parallel, near-identical mirrors of the "GSD" (Get Shit Done) agent workflow toolkit: Markdown workflow/skill definitions with embedded Bash/Node snippets, plus hook shell scripts (`.claude/hooks/*.sh`) and Node helper libraries (`.claude/hooks/lib/*.js`, `.claude/gsd-core/bin/**/*.cjs`)

There is no application source tree (`src/`), no `package.json` at repo root, and no build/lint pipeline for a language runtime. Conventions below describe the actual patterns observed across scripts, hooks, and Markdown workflow files.

## Naming Patterns

**Files:**
- Bash scripts: `kebab-case.sh` (e.g. `scripts/validate-config.sh`, `scripts/check-secrets.sh`, `.claude/hooks/gsd-graphify-update.sh`)
- Node helper modules: `kebab-case.cjs` / `kebab-case.js`, always CommonJS (`.cjs` in `gsd-core/bin/lib/`, `.js` in `hooks/lib/`) — e.g. `.claude/gsd-core/bin/lib/normalize-test-command.cjs`, `.claude/hooks/lib/git-cmd.js`
- GSD hook scripts are prefixed `gsd-` (e.g. `gsd-validate-commit.sh`, `gsd-session-state.sh`, `gsd-phase-boundary.sh`) to namespace them among other tools' hooks in a shared `settings.json`
- Skill/workflow Markdown: `SKILL.md` per skill directory (`.cursor/skills/<skill-name>/SKILL.md`), and matching workflow docs in `.claude/gsd-core/workflows/<name>.md`
- Command wrapper docs: `.claude/commands/gsd-<name>.md`

**Directories:**
- Three agent-runtime mirrors use identical internal layout: `.claude/`, `.codex/`, `.cursor/` each contain `gsd-core/{bin,contexts,references,templates,workflows}`, `hooks/`, `skills/` (cursor/codex) or `commands/` (claude) — changes to shared logic must be propagated to all three mirrors (see CONCERNS.md for drift risk)
- `.claude/gsd-core/workflows/<workflow-name>/` subdirectories hold multi-file workflows (e.g. `workflows/execute-phase/`, `workflows/plan-phase/`)
- `.claude/gsd-core/templates/codebase/` holds the very templates this mapper uses (`testing.md`, etc.) — self-referential; do not confuse with actual project output in `.planning/codebase/`

## Code Style

**Formatting (Bash):**
- Every operational script starts with `#!/usr/bin/env bash` and `set -euo pipefail` (see `scripts/validate-config.sh`, `scripts/check-secrets.sh`, `scripts/build-and-push.sh`, `docker/entrypoint.sh`)
- `REPO_ROOT` resolved defensively at top of script: `REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"` — always compute absolute paths from script location, never assume CWD
- Checks emit a leading `==>` or plain descriptive line, and a final `✓`-prefixed success line or `ERROR:`-prefixed failure line with `exit 1`
- No formatter/linter config (no `.shellcheckrc`, no `shfmt` config) is present — style is convention-only, not enforced by tooling

**Formatting (Node/.cjs/.js):**
- `'use strict';` as the first line of every module
- CommonJS only (`require`/`module.exports`), never ESM import/export — confirmed by `.claude/hooks/package.json` containing `{"type":"commonjs"}`
- No Prettier/ESLint config found in `.claude/hooks/` or `.claude/gsd-core/bin/` — formatting is by convention, not tooling

**JSON/YAML:**
- 2-space indentation is the documented standard for YAML/JSON per `CONTRIBUTING.md` "Code Style" section
- `config/openclaw.json` is hand-authored config; must remain valid JSON (validated by `scripts/validate-config.sh` via `jq empty`)

## Import Organization

**Node (.cjs) modules:**
- Relative `require()` from the module's own file location, e.g. `require(path.join(__dirname, '..', '..', 'gsd-core', 'bin', 'lib', 'token-scanner.cjs'))`
- Comments explicitly justify *why* a require path is relative-to-`__dirname` rather than a sibling import — hook scripts are staged as standalone files at install time, so imports must resolve correctly after being copied out of the repo tree (see `.claude/hooks/lib/git-cmd.js` header comment)
- Shared "single source of truth" modules are called out in comments (e.g. `git-cmd.js`, `injection-patterns.js`) to prevent logic duplication/drift across multiple hook scripts

**Bash:**
- Scripts source no external files; each is self-contained. Shared logic between `build-and-push.sh` and pre-commit is achieved by **invoking** `validate-config.sh` / `check-secrets.sh` as subprocesses, not by sourcing shared functions

## Error Handling

**Bash:**
- `set -euo pipefail` at the top of every script — fail fast on any error, unset variable, or pipe failure
- Explicit `ERROR: <message>` lines printed to stdout before `exit 1` (not written to stderr) — e.g. `scripts/validate-config.sh`: `echo "ERROR: $CONFIG is not valid JSON"; exit 1`
- Required env vars are checked explicitly before use with a clear failure message, e.g. `scripts/build-and-push.sh`:
  ```bash
  if [[ -z "${GHCR_USERNAME:-}" ]]; then
      echo "ERROR: GHCR_USERNAME environment variable is not set"
      exit 1
  fi
  ```
- Pre-commit hook (`.githooks/pre-commit`) chains validation scripts and surfaces which check failed:
  ```bash
  if ! "$REPO_ROOT/scripts/validate-config.sh"; then
    echo "Pre-commit check failed: config validation. Fix the errors above and retry."
    exit 1
  fi
  ```

**GSD hook scripts (`.claude/hooks/*.sh`):**
- Hooks that are opt-in gate immediately: read `.planning/config.json` via Node one-liner, `exit 0` silently if the relevant flag (`hooks.community`, `graphify.enabled` + `graphify.auto_update`) is not `true`. This "no-op unless explicitly enabled" pattern is applied consistently and documented in each script's header comment.
- Hooks return `0` in effectively all cases for non-blocking hooks (e.g. `gsd-graphify-update.sh` "Never blocks the user-facing tool call"); only `gsd-validate-commit.sh` is a true blocking gate (`exit 2` on non-conforming commit message)
- JSON parsing from stdin payloads always goes through Node (`node -e "..."`), never `jq`, with comments noting this is "always available in GSD projects, no jq dependency"

**Node (.cjs):**
- Enum-style constants (`Object.freeze({...})`) define exhaustive result/reason codes rather than raw strings, e.g. `CHECK_REASON` in `check-latest-version.cjs` (`OK`, `FAIL_NPM_FAILED`, `FAIL_INVALID_OUTPUT`) — callers and tests assert on these typed values, not on printed prose

## Comments

**When to Comment:**
- Heavy use of block header comments at the top of every non-trivial script/module explaining: purpose, why a particular (sometimes non-obvious) implementation choice was made, and references to originating GitHub issue/ADR numbers (e.g. `#3347`, `#2992`, `#3212`, `#498`)
- Inline comments cite issue numbers as historical justification for edge-case handling (e.g. `git-cmd.js`: "missed by regex" annotations per case; `gsd-phase-boundary.sh`: "#2304... #2752...")
- Comments frequently state an explicit prohibition/rule for future editors, e.g. "Deliberately NOT unified with src/security.cts's scanForInjection set", "Keep this file free of literal 'gsd:' text — the stager rewrites that marker"

**JSDoc/TSDoc:**
- Node modules use JSDoc-style block comments (`/** ... */`) at module and function level, but this is not enforced by a linter — the module in `.claude/gsd-core/bin/check-latest-version.cjs` is a representative example

## Function Design

**Size:** Bash scripts are short and single-purpose (one script = one validation/build concern); Node modules extract one classifier/utility per file (e.g. `git-cmd.js` = git-subcommand detection only, `injection-patterns.js` = pattern list only) — a "single source of truth" module-per-concern discipline is explicit in comments.

**Parameters:** Bash scripts take positional args with defaults via `${1:-default}` (see `TAG="${1:-latest}"` in `build-and-push.sh`).

**Return Values:** Bash uses exit codes as the primary return channel (0 success, 1 error, 2 for the blocking pre-commit-style hook). Node CLI helpers print structured JSON to stdout for machine consumption (referenced via `--json` flag pattern in `check-latest-version.cjs`) rather than free-form text, explicitly to avoid "Raw Text Matching on Test Outputs" (see `CONTRIBUTING.md` cross-reference in that file's header comment).

## Module Design

**Exports:** Node `.cjs` files use `module.exports = { ... }` with named exports (e.g. `{ isGitSubcommand }`, `{ packageName: PACKAGE_NAME }`).

**Shared library placement:** Cross-cutting hook logic lives in `hooks/lib/*.js` (per-runtime, staged alongside hooks) or `gsd-core/bin/lib/*.cjs` (canonical implementation, re-exported by staged hook libs) — the split exists because hook scripts are copied out as standalone files during install and cannot rely on a sibling package structure being present.

**Markdown workflow "modules":** GSD workflows/skills are structured as Markdown documents with a strict frontmatter/section contract (name, description, numbered `<step>` sections) — treat these as the primary "source files" for this repo's actual product (agent behavior), not the Bash/JS which is comparatively small in volume.

## Commit Conventions

- Conventional Commits format is enforced (when `hooks.community: true` is set) by `.claude/hooks/gsd-validate-commit.sh`, which blocks non-conforming `git commit` messages before they land.
- `CONTRIBUTING.md` asks for present-tense commit messages ("Add feature" not "Added feature") and issue references where relevant.

---

*Convention analysis: 2026-08-21*
