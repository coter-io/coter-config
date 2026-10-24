# Testing Patterns

**Analysis Date:** 2026-08-21

## Test Framework

**No automated test framework is present in this repository.** There is no `package.json` at the repo root, no `jest.config.*`, `vitest.config.*`, `mocha.*`, or `*.test.*`/`*.spec.*` file anywhere in the tree (confirmed via repo-wide search). `.claude/hooks/package.json`, `.codex/hooks/package.json`, and `.cursor/hooks/package.json` contain only `{"type":"commonjs"}` — enough to make Node treat `.js` files in that directory as CommonJS, not a test/build manifest.

Several source comments reference a `tests/` directory and specific test files (e.g. `.claude/hooks/lib/git-cmd.js`: "parity-asserted in tests/token-scanner.test.cjs row 5"; `.claude/gsd-core/bin/check-latest-version.cjs`: "Tests assert on the typed CHECK_REASON enum"). These references describe the **upstream `gsd-core` project's own test suite**, not tests that exist inside this vendored/distributed copy — no such `tests/` directory exists in this repo. Treat those comments as inherited documentation, not as evidence of local test coverage.

**Conclusion:** this repo ships no unit/integration/e2e test suite of its own. Validation is done entirely through operational shell scripts (see below), which act as this repo's closest analog to automated tests.

## Closest Analog: Validation Scripts

These scripts are run manually, via `.githooks/pre-commit`, and via `scripts/build-and-push.sh`. They are the practical "test suite" for this repo's actual deliverable (Docker config + agent tooling config), verifying config correctness and secret hygiene rather than code behavior.

### `scripts/validate-config.sh`

**Purpose:** Validates `config/openclaw.json`.

**What it checks:**
1. Valid JSON — `jq empty "$CONFIG"`
2. No raw API key patterns present in the config (must use `${ENV_VAR}` references instead of plaintext secrets) — regex: `sk-ant-|sk-proj-|bot[0-9]|bsc_|xai-|gsk_`

**Run command:**
```bash
./scripts/validate-config.sh
```

**Exit codes:** `0` on success (prints `✓ Config validation passed`), `1` on JSON parse failure or detected raw key pattern (prints `ERROR:` plus the offending line via `grep -n`).

### `scripts/check-secrets.sh`

**Purpose:** Scans all git-tracked files (excluding `.env.example` and `*.md`) for leaked secret patterns.

**What it checks:** An array of regex patterns for common provider secret formats plus generic high-entropy base64-looking strings and bearer tokens:
```bash
PATTERNS=(
  'sk-ant-[A-Za-z0-9_-]{20,}'
  'sk-proj-[A-Za-z0-9_-]{20,}'
  'bot[0-9]{8,}:[A-Za-z0-9_-]{30,}'
  'bsc_[A-Za-z0-9]{20,}'
  'xai-[A-Za-z0-9]{20,}'
  'gsk_[A-Za-z0-9]{20,}'
  '[A-Za-z0-9+/]{40,}={0,2}'
  'Bearer [A-Za-z0-9._-]{20,}'
)
```

**Run command:**
```bash
./scripts/check-secrets.sh
```

**Exit codes:** `0` and `✓ No secrets detected in tracked files` on success; `1` with a `SECRET DETECTED in <file>:` report per match on failure. Iterates `git ls-files`, so untracked/gitignored files are never scanned.

### `scripts/build-and-push.sh`

Not a test script per se, but runs both validation scripts as a gate before building/pushing Docker images:
```bash
echo "==> Validating config ..."
"$REPO_ROOT/scripts/validate-config.sh"
"$REPO_ROOT/scripts/check-secrets.sh"
```
Then builds and pushes the `openclaw-gateway` and `workspace-sync` Docker images to GHCR, tagged with both `latest` (or a caller-supplied tag) and the short git SHA.

## Test/Validation File Organization

**Location:** Validation scripts live in `scripts/` at repo root, not co-located with the config they validate.

**Naming:** `verb-noun.sh` (`validate-config.sh`, `check-secrets.sh`, `build-and-push.sh`).

**No fixtures directory:** there is no dedicated fixtures/mocks directory for these scripts; they operate directly on the live `config/openclaw.json` and the full `git ls-files` output.

## Local Enforcement: Pre-commit Hook

`.githooks/pre-commit` (must be wired via `git config core.hooksPath .githooks` — not auto-installed) runs both validation scripts sequentially and blocks the commit if either fails:

```bash
if ! "$REPO_ROOT/scripts/validate-config.sh"; then
  echo "Pre-commit check failed: config validation. Fix the errors above and retry."
  exit 1
fi

if ! "$REPO_ROOT/scripts/check-secrets.sh"; then
  echo "Pre-commit check failed: secrets detected. Remove them and retry."
  exit 1
fi
```

This is the only automated "test gate" enforced in this repo, and it is opt-in (developers must configure `core.hooksPath` themselves; `CONTRIBUTING.md` does not currently document this setup step).

## Manual Verification (per CONTRIBUTING.md)

`CONTRIBUTING.md`'s "Development Setup" section documents manual (not automated) verification steps expected of contributors:
```bash
cd docker
docker compose build
# Test deployment on a VPS or local environment
# Verify all configurations work as expected
```
There is no CI workflow file (no `.github/workflows/`) found in the repo, so these manual build/deploy checks and the pre-commit hook are the entirety of this repo's quality gates.

## Recommendations if Automated Testing Is Desired

Since this repo's real logic lives in `.claude/hooks/*.sh` and `.claude/hooks/lib/*.js` / `.claude/gsd-core/bin/**/*.cjs` (git-command classification, injection-pattern scanning, commit-message validation, version checking), and comments already reference a `tests/*.test.cjs` convention from the upstream `gsd-core` project, the natural framework choice — consistent with existing CommonJS/Node conventions (`'use strict'`, `.cjs` extension, `module.exports`) — would be Node's built-in `node:test` runner or a lightweight CommonJS-compatible framework (e.g. `tape`, `ava`) with test files named `*.test.cjs`, colocated in a `tests/` directory mirroring `hooks/lib/` and `gsd-core/bin/lib/` structure. No such setup currently exists; this is a gap, not an established pattern (see CONCERNS.md).

---

*Testing analysis: 2026-08-21*
