# Proposal

## Why

Nothing in this repository runs on a pull request. `scripts/validate-config.sh` and `scripts/check-secrets.sh` exist and are strong, but they are reachable only from the local pre-commit hook and from **Publish image**, which is `workflow_dispatch`-only — so a config change is first checked by CI at release time, after review and merge. The last outage in this repo was a config that passed review and shipped; the guard added in response still cannot see a pull request.

Measuring the pinned OpenClaw version's own CLI also showed that two mechanisms inside `validate-config.sh` do not work the way they were designed to, so wiring the current script to pull requests would propagate a weak gate rather than establish a real one.

## What Changes

- Add a **Validate config** workflow that runs on `pull_request` against `main` (opened, synchronize, reopened) and on `push` to `main`, with read-only permissions and `cancel-in-progress` concurrency. It runs the repository's validation scripts, so the PR gate, the pre-commit hook and the release gate execute the same code.
- Order the gate cheap-checks-first so offline findings are always reported, even when the container-based schema check cannot run: JSON parse → secret scan → env-var contract → `docker compose config` → ShellCheck → pinned-version schema validation → structured health lint.
- Rework how `scripts/validate-config.sh` talks to the pinned runtime, on measured evidence:
  - **Stop rewriting the config before validating it.** OpenClaw expands `${VAR}` from the process environment natively (confirmed: `config get channels.telegram.allowFrom` resolves to `["tg:123456789"]` with `TELEGRAM_USER_ID` exported). Supplying placeholder values as environment variables validates the real file unmodified, and removes the `mcp.servers.*.url` format workaround along with a false-positive `core/doctor/security` "plaintext secret-bearing config fields" finding that the substitution itself was producing.
  - **Stop grepping `doctor`'s prose.** The pinned version offers `doctor --lint --json`, which emits findings carrying `checkId`, `severity`, `path` and `fixHint`. Judge that payload's `ok` and `findings`, never its exit code: a legacy config produced a `severity: error` finding and still exited `0`, while a clean config exited `1` on an unrelated network check. The current `grep -q "Legacy config keys detected"` also breaks on any rewording of that sentence.
  - Keep `config validate` ordered before the lint. When `final-config-validation` fails, `doctor` short-circuits at `checksRun: 1` and skips the other 32 checks, so a lint result after a validation failure carries no information.
  - Gate on findings at `warning` and above. With three environment-dependent checks skipped and a dummy gateway token exported, the shipped config measures `ok: true, checksRun: 33, findings: []`, so the clean baseline is zero findings rather than zero errors.
- Add `scripts/check-env-vars.sh`, which cross-references every `${VAR}` referenced by `config/openclaw.json` and `docker/docker-compose.yml` against the names declared in `docker/.env.example`. CONTRIBUTING.md already requires that every variable be documented there; nothing enforced it.
- Fix the drift that check immediately exposes, so the gate lands green:
  - `docker/.env.example` declares `BRAVE_SEARCH_API_KEY` while `docker-compose.yml` passes `BRAVE_API_KEY: ${BRAVE_API_KEY-}`. A user who fills in the documented name gets an empty value in the container, so Brave search runs unauthenticated. The two names are reconciled.
  - `OPENAI_API_KEY` is interpolated by compose with no default and README states it "must stay set" for audio transcription, but it is absent from `.env.example`.
  - `TELEGRAM_USER_ID`, `COMPOSIO_API_KEY` and `COMPOSIO_MCP_URL` are referenced by the config and by compose, and are absent from `.env.example`.
- Add a non-blocking forward-compatibility step that validates the config against the current npm `latest` OpenClaw. The shipped config already passes against `2026.10.9`, so this reports upgrade readiness before the pin is bumped instead of during a release.
- Extend **Publish image**'s pre-build validation to run the env-var contract check too, so the release gate and the PR gate cannot diverge.
- Update `README.md` (validation section) and `CONTRIBUTING.md` (pull request steps) to describe the PR gate and what it enforces.

The workflow deliberately carries no `paths:` filter: a path-filtered workflow never reports on unrelated pull requests, which makes it unusable as a required status check.

**BREAKING**: none. No runtime behavior changes; `config/openclaw.json` is not modified by this change.

## Capabilities

### New Capabilities

- `config-pr-validation`: pull requests targeting `main` are validated before merge — which checks run, in what order, what makes the gate fail, and that the gate reuses the same scripts as the pre-commit hook and the release gate.
- `deployment-env-contract`: every environment variable the shipped config or compose file references is documented in `docker/.env.example` under the same name, so a user who follows the documented setup gets a working deployment.

### Modified Capabilities

- `model-routing-config`: the requirement *Config validates against the pinned OpenClaw version* changes mechanism. Its *Environment placeholders are not credentials* scenario currently asserts that unresolved placeholders are not a schema error; measured against the pin, an unresolved `${COMPOSIO_MCP_URL}` **is** rejected on URL format, which is why the substitution existed. The amended requirement states that validation supplies placeholder values from the environment and validates the shipped file unmodified, and that drift the pinned version tolerates without a hard error is still caught through structured health findings.
- `ghcr-image-publish`: the *Pre-build validation* requirement extends to the environment-variable contract check, so a tag cannot be published with undocumented or misnamed variables.

## Impact

- `.github/workflows/` — new **Validate config** workflow; one added step in **Publish image**.
- `scripts/validate-config.sh` — placeholder handling via environment, structured `doctor --lint --json` parsing, explicit check skips, warning-level gating.
- `scripts/check-env-vars.sh` — new.
- `docker/.env.example`, `docker/docker-compose.yml` — the Brave name reconciliation and four documented variables.
- `README.md`, `CONTRIBUTING.md` — documentation of the gate.
- `.githooks/pre-commit` — inherits the reworked script; gains the env-var check for parity with CI.
- Developer experience — validation keeps requiring Docker and network access, consistent with the existing single-code-path decision. A PR run costs roughly 90–120s for the image pull and `npx` download; `jq` becomes a hard dependency of the validation script, as it already is for the JSON parse check.
- Not included: bumping `OPENCLAW_VERSION` past the pinned `2026.10.7`, `config/openclaw.json` content changes, and the `docker-compose.yml` `:latest` image reference versus the Dockerfile pin, which remains a known open concern from the preceding change.
