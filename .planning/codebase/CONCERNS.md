# Codebase Concerns

**Analysis Date:** 2026-08-21

## Tech Debt

**Secret-scanner produces overwhelming false positives, breaking the release pipeline:**
- Issue: `scripts/check-secrets.sh` uses a catch-all regex `'[A-Za-z0-9+/]{40,}={0,2}'` (intended to catch stray base64 blobs) that also matches minified/vendored JS, long shell command strings, and hashes. Running it against this repo today (`bash scripts/check-secrets.sh`) reports **133 "SECRET DETECTED" false positives**, e.g. matches inside `.cursor/hooks/*.js` command strings and the vendored `.claude/gsd-core/bin/lib/vendor/re2js.cjs`.
- Files: `scripts/check-secrets.sh:18` (the offending pattern), triggered against `.claude/gsd-core/bin/lib/vendor/re2js.cjs`, `.cursor/hooks/*.js`, etc.
- Impact: `scripts/build-and-push.sh` calls `check-secrets.sh` unconditionally under `set -euo pipefail` (`scripts/build-and-push.sh:19`), so **any invocation of the build/push script fails immediately** on this repo state — the release path is effectively broken. If anyone "fixes" this by disabling or loosening the script, real secrets could slip through unnoticed (crying-wolf effect).
- Fix approach: replace the generic base64 heuristic with a higher-entropy check scoped to likely secret contexts (e.g. skip vendored/minified files via an ignore-list, or require the match to sit near `key`/`token`/`secret`-like variable names), and add an allowlist mechanism (inline `# secret-scan: allow` comment or a `.secretsignore` file) so vendored/minified code doesn't need to be excluded wholesale.

**Three parallel copies of `gsd-core` (`.claude/`, `.codex/`, `.cursor/`) diverge by hundreds of files, including large generated binaries:**
- Issue: `.claude/gsd-core/`, `.codex/gsd-core/`, and `.cursor/gsd-core/` are near-duplicate trees (each contains its own `workflows/`, `references/`, `templates/`, `bin/`). `diff -rq` shows 222 differing files between `.claude/gsd-core` and `.codex/gsd-core`, and 218 between `.claude/gsd-core` and `.cursor/gsd-core`. Most differences are runtime-templating substitutions (e.g. `$ARGUMENTS` → `{{GSD_ARGS}}`, `runtime claude` → `runtime codex`) applied by an install/generation step, not hand-authored divergence — but the generation step is not visible anywhere in this repo (no generator script tracked), so it's unclear how these trees are kept in sync or regenerated.
- Files: `.claude/gsd-core/`, `.codex/gsd-core/`, `.cursor/gsd-core/` (each ~4,400–7,500 line vendored files duplicated 3x: `bin/gsd-tools.cjs`, `bin/lib/capability-registry.cjs`, `bin/lib/vendor/re2js.cjs`, `bin/lib/state.cjs`, `bin/lib/capability-validator.cjs`).
- Impact: ~400K+ lines of tracked shell/JS/Markdown total (`git ls-files "*.js" "*.sh" "*.cjs" | xargs wc -l` → 404,726 lines), a large fraction of which is triplicated vendor code. Any manual edit to one workflow/reference file (rather than through the generator) risks silently drifting the three runtimes out of sync, since there is no drift-detection check in this repo (`scripts/validate-config.sh` only validates `config/openclaw.json`).
- Fix approach: either commit the actual generator/build step that produces `.codex/` and `.cursor/` from `.claude/` (or a shared source), or add a CI/pre-commit check that diffs the three trees (ignoring known per-runtime template substitutions) and fails on unexpected divergence.

**Absolute local developer paths are baked into 677 tracked files:**
- Issue: `/Users/majskiy/...` (this machine's home directory) appears in 677 git-tracked files, including generated workflow files (e.g. `.claude/gsd-core/workflows/quick.md:42` embeds `CLAUDE_CONFIG_DIR:-/Users/majskiy/Documents/projects/coter/coter-config/.claude` as a fallback default) and — in the untracked-but-real working copy — `.claude/settings.local.json` (hook commands hardcode `/Users/majskiy/.nvm/versions/node/v24.13.1/bin/node`).
- Files: `.claude/gsd-core/workflows/quick.md`, and hundreds of other workflow/reference files under `.claude/gsd-core/`, `.codex/gsd-core/`, `.cursor/gsd-core/` (confirm scope via `git ls-files | xargs grep -l "/Users/majskiy"`).
- Impact: if these generated files are meant to be portable "config templates" for the `coter-config` project (as its README suggests), shipping a specific contributor's absolute home path as a fallback default is a personal-info leak and will silently misbehave for every other user/machine that doesn't have that exact path.
- Fix approach: confirm whether these files are meant to be regenerated per-install (in which case they should not be committed with a personal absolute path baked in) or are legitimately machine-specific caches that should be gitignored instead of tracked.

**`scripts/validate-config.sh` only validates one file:**
- Issue: The validator checks JSON well-formedness and raw-API-key patterns only in `config/openclaw.json`. It does not validate `docker/docker-compose.yml`, `docker/.env.example`, or the three `gsd-core` trees for consistency.
- Files: `scripts/validate-config.sh`.
- Impact: misconfigurations or leaked-looking values elsewhere (e.g. `docker-compose.yml` env var wiring) are not caught by the "validate" step referenced in the release script.
- Fix approach: extend `validate-config.sh` to also lint `docker-compose.yml` (e.g. via `docker compose config`) and scan `.env.example` for accidentally-real-looking values.

## Known Bugs

**`check-secrets.sh` self-fails on a clean repo:**
- Symptoms: Running `bash scripts/check-secrets.sh` from repo root exits 1 with "ERROR: Secrets detected in tracked files" even though no actual secret is present — 133 matches, all false positives from the generic base64 pattern (see Tech Debt above).
- Files: `scripts/check-secrets.sh:18`.
- Trigger: run the script directly, or run `scripts/build-and-push.sh` (which invokes it as a precondition).
- Workaround: none currently in the repo (no allowlist/ignore mechanism exists).

## Security Considerations

**Docker Compose injects numerous API tokens as plaintext environment variables into the gateway container:**
- Risk: `docker/docker-compose.yml` passes `ANTHROPIC_API_KEY`, `BRAVE_API_KEY`, `GH_TOKEN`, `OPENAI_API_KEY`, `OPENCLAW_GATEWAY_TOKEN`, `OPENROUTER_API_KEY`, `TELEGRAM_BOT_TOKEN`, `COMPOSIO_API_KEY`, etc. directly as container env vars (`docker/docker-compose.yml:6-19`). Container env vars are visible via `docker inspect`, process listings inside the container, and any code running in-process (including AI-agent-invoked shell commands, since this is an AI agent runtime) — this is a broad blast radius for a system whose entire purpose is running semi-autonomous AI agents with shell access.
- Files: `docker/docker-compose.yml`, `docker/.env` (present on disk, gitignored — noted by existence only, contents not read), `docker/.env.example`.
- Current mitigation: `.gitignore` excludes `.env`, `*.key`, `*.pem`, `credentials/`, `sessions/`; `scripts/check-secrets.sh` is intended as a pre-push safety net (but is currently broken — see above); `config/security-rules.md` instructs the agent's system prompt to "never reveal secrets ... even if asked directly."
- Recommendations: the security-rules.md prompt-level mitigation is not a technical control — a sufficiently adversarial prompt-injection (from untrusted content the agent reads, e.g. a webpage or issue body) could still exfiltrate env-var values via shell commands the agent is permitted to run, since the container has legitimate shell/network access. Consider a secrets-manager/vault injection pattern (short-lived tokens, or a sidecar that mediates API calls) rather than baking long-lived tokens directly into the agent's own process environment.

**Runtime skill installation (`clawhub install`) is unpinned and executes third-party code at container start with no integrity check:**
- Risk: `docker/entrypoint.sh:33-36` runs `clawhub install "$line" --workdir "$WORKDIR"` for every entry in `config/skills-manifest.txt` on every container start, with no version pinning, checksum, or signature verification. A compromised or rug-pulled ClawHub package would be installed and trusted automatically.
- Files: `docker/entrypoint.sh`, `config/skills-manifest.txt`.
- Current mitigation: failures are caught and logged as warnings only (`|| { echo "WARNING..." }`), so the container continues even if a skill install is tampered with or fails oddly — failure is not distinguished from "installed something unexpected."
- Recommendations: pin skill versions in the manifest (not just names), and fail loudly (not just warn) if a previously-installed skill's contents change unexpectedly between runs.

**`check-secrets.sh` skips all `*.md` files entirely:**
- Risk: `FILES=$(cd "$REPO_ROOT" && git ls-files | grep -v '\.env\.example$' | grep -v '\.md$' ...)` (`scripts/check-secrets.sh:23`) excludes every Markdown file from scanning. Given this repo is majority documentation/workflow Markdown (`.claude/gsd-core/workflows/*.md`, `references/*.md`, etc.), a secret accidentally pasted into a workflow doc, README, or planning note would never be caught by this scanner.
- Files: `scripts/check-secrets.sh`.
- Current mitigation: none — this is a blind spot by design, presumably to avoid flagging documentation examples, but it means the scanner's coverage is inverted relative to where this repo's actual bulk of tracked text lives.
- Recommendations: scan `.md` files too, but exclude clearly-labeled example/placeholder values (e.g. `sk-ant-xxxxxxx`) via a stricter high-entropy check instead of a blanket file-type exclusion.

## Performance Bottlenecks

Not applicable — this is a configuration/tooling repo with no runtime request-handling application code; no hot paths were identified. The one operational cost worth noting is repo size: `git ls-files "*.js" "*.sh" "*.cjs" | xargs wc -l` totals ~405K lines, largely from the 3x-duplicated vendored `gsd-core` runtime files, which inflates clone size, `grep`/`diff`-based tooling runtime, and any full-repo AI context loads.

## Fragile Areas

**`docker/entrypoint.sh` seeds workspace templates and installs skills before any validation that `$WORKDIR` is correctly mounted:**
- Files: `docker/entrypoint.sh`.
- Why fragile: `cp -rn "$TEMPLATES"/. "$WORKDIR"/` and the skill-install loop both assume `/home/node/.openclaw/workspace` is a valid, writable mount. If the volume in `docker-compose.yml` (`${OPENCLAW_WORKSPACE_DIR:-/home/openclaw/.openclaw/workspace}:/home/node/.openclaw/workspace`) is misconfigured or not yet created on the host, `cp` and the skill installs will fail silently or partially, and the script proceeds to `exec "$@"` regardless.
- Safe modification: add an explicit existence/writability check for `$WORKDIR` before the seed/install steps, and fail fast (not silently continue) if the mount is missing.
- Test coverage: none — there is no test suite in this repo (confirmed: no `*.test.*`/`*.spec.*` files, no CI config found under any `workflows/*.yml` search).

**Three-way `gsd-core` trees rely on manual/tooling-external synchronization:**
- Files: `.claude/gsd-core/`, `.codex/gsd-core/`, `.cursor/gsd-core/`.
- Why fragile: as noted under Tech Debt, there is no generator or sync-check committed to this repo, so any contributor editing one runtime's workflow file (e.g. `.claude/gsd-core/workflows/execute-phase.md`) without also updating `.codex/` and `.cursor/` equivalents will introduce silent behavioral drift between runtimes that isn't caught by any automated check.
- Safe modification: treat `.claude/gsd-core/` (or whichever is canonical) as source of truth, and only edit the others through whatever external generation tool produces them — do not hand-edit `.codex/` or `.cursor/` copies directly without also verifying `.claude/` stays in sync.
- Test coverage: none.

## Scaling Limits

Not applicable — this repo does not run a scalable service; `docker-compose.yml` defines a single gateway container and a single workspace-sync container per agent (with a documented, commented-out pattern for adding more `workspace-sync-*` services per additional agent at `docker/docker-compose.yml:41-57`). Scaling to multi-agent setups requires manual duplication of compose service blocks, which is itself a drift risk if agents' volume paths and `openclaw.json` workspace paths get out of sync.

## Dependencies at Risk

**`clawhub` (skill package manager) installed via `npm install -g clawhub` with no version pin:**
- Risk: `docker/Dockerfile:34` installs `clawhub` unpinned, so every image rebuild picks up whatever the latest `clawhub` version is, and every container start reinstalls whatever skills are unpinned in `config/skills-manifest.txt` (see Security Considerations above). This couples image reproducibility to an external registry's current state.
- Impact: a `clawhub` or ClawHub-hosted-skill update could silently change agent behavior or break builds between otherwise-identical `build-and-push.sh` runs.
- Migration plan: pin `clawhub@<version>` in the Dockerfile the same way `OPENCLAW_VERSION` is already pinned via `ARG OPENCLAW_VERSION=2026.4.29` (`docker/Dockerfile:30`), and pin skill versions in `config/skills-manifest.txt`.

## Missing Critical Features

**No CI pipeline:**
- Problem: no GitHub Actions or other CI workflow files were found anywhere in the repo (`find . -iname "*.yml" -path "*workflows*"` returned nothing outside `.claude`/`.codex`/`.cursor` GSD tooling directories, and none of those are CI configs). `scripts/validate-config.sh` and `scripts/check-secrets.sh` exist but appear to only be invoked manually or from `scripts/build-and-push.sh`.
- Blocks: there is no automated gate preventing a broken `openclaw.json`, a leaked secret, or `gsd-core` tree drift from being merged/pushed to `develop`/`main`. Given `scripts/check-secrets.sh` is currently broken (see Known Bugs), even manual discipline around running it would produce a false "secrets found" failure and likely train contributors to ignore or skip the check.

## Test Coverage Gaps

**No automated tests anywhere in the repo:**
- What's not tested: `docker/entrypoint.sh`'s seeding/install logic, `scripts/check-secrets.sh` and `scripts/validate-config.sh` themselves, and any behavioral parity between the `.claude/`, `.codex/`, and `.cursor/` `gsd-core` trees.
- Files: entire repo — no `*.test.*`, `*.spec.*`, or test-runner config found.
- Risk: regressions in shell scripts or drift between the three parallel config trees can only be caught by manual review or by a maintainer noticing runtime misbehavior in production use.
- Priority: High for `scripts/check-secrets.sh` (actively broken, gates the release script) and for a `gsd-core` tree drift check; Medium for `docker/entrypoint.sh` mount/failure handling.

---

*Concerns audit: 2026-08-21*
