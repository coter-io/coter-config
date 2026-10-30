# Design

## Context

See proposal.md — Why. Constraints that shape the approach:

- `config/openclaw.json` is not read by anything in this repo; it is SCP'd to the VPS by the infra repo's `make push-config`. There is no runtime here to test against, so validation against the pinned package is the only feedback loop.
- The pinned version is `OPENCLAW_VERSION=2026.10.7` in `docker/Dockerfile`, whose package declares `engines.node >= 24.22.1 < 25 || >= 26.12.1`. The current development machine runs node 24.13.1 and cannot install it, which is why the preceding change settled on running the pinned CLI in a container.
- `scripts/validate-config.sh` is already invoked by `.githooks/pre-commit` and by **Publish image**. Strengthening the script strengthens both callers.
- Every behavior claimed below was measured by running `openclaw@2026.10.7` in `node:24.22-bookworm-slim` against the shipped config and against deliberately broken copies. The measurements are recorded inline because two of them contradict the preceding change's design.

## Goals / Non-Goals

**Goals:**

- A pull request against `main` cannot merge without the same validation the release gate runs.
- Validation judges the shipped file, against the pinned schema, on signals that do not break when output wording changes.
- The environment-variable contract is machine-checked, and the drift that check exposes is cleared in the same change.

**Non-Goals:**

- Bumping `OPENCLAW_VERSION`. The advisory forward-compatibility step reports readiness; acting on it is a separate change with its own image rebuild.
- Changing `config/openclaw.json`. No key is added, removed, or reshaped here.
- Enabling `tools.web.search`. The Brave variable is reconciled by name only (see *Brave is reconciled by name, not by enabling search*).
- Reconciling `docker-compose.yml`'s `:latest` image reference against the Dockerfile pin. Still a real concern, still out of scope, carried forward from the preceding change.
- Replacing `check-secrets.sh`'s pattern-based scanning with a dedicated scanner. Noted under Risks.

## Decisions

### Placeholder values come from the environment; the config is never rewritten

The pinned runtime expands `${VAR}` from the process environment. Measured:

```
$ docker run -e TELEGRAM_USER_ID=123456789 ... npx openclaw@2026.10.7 config get channels.telegram.allowFrom
[
  "tg:123456789"
]
```

With dummy values exported for the five placeholders the config references, `config validate` accepts the real, unmodified file (`Config valid: /cfg/real.json`, exit 0).

So the script exports placeholder values instead of `sed`-substituting a throwaway copy. The classification the old substitution applied to file text now applies to environment values: a variable whose name contains `URL` gets a well-formed URL, everything else gets an opaque token. Only unset variables are defaulted, so a developer with real values in their shell validates against those.

This removes three things at once: the `mcp.servers.*.url` format workaround, a derived file that is validated but never shipped, and a false positive. The substitution turned `${TELEGRAM_BOT_TOKEN}` into the literal string `placeholder`, which the runtime then reported as `core/doctor/security — openclaw.json contains plaintext secret-bearing config fields`. Validating the real file, that finding disappears: the field is env-sourced, and `config get channels.telegram.botToken` returns `__OPENCLAW_REDACTED__`.

Alternative considered: keep substituting and suppress the security finding. Rejected — it suppresses a check that would catch a genuinely hardcoded credential, to hide a problem the substitution itself created.

### `doctor --lint --json` is judged by its payload, never its exit code

The pinned version offers structured health output. Measured exit codes against `ok`:

| Config | Flags | `ok` | Exit |
|---|---|---|---|
| shipped | none | `false` | **1** |
| legacy `agents.list` | mcp check skipped | `false` | **0** |
| shipped | `--severity-min error` + skips | `true` | 0 |

A config with a `severity: error` finding exited 0, and a clean config exited 1 on an unrelated network check. The exit code tracks something other than the verdict, so the gate parses the JSON and fails when `ok` is false or `findings` is non-empty.

This also retires `grep -q "Legacy config keys detected"`, which depends on one English sentence in boxed terminal output and on `COLUMNS` being wide enough not to wrap it mid-phrase. Findings carry `checkId`, `severity`, `path` and `fixHint`, so failure messages can name the path and the remedy from data rather than by echoing a grep window.

Alternative considered: keep the prose grep as a second signal. Rejected — two signals disagreeing on the same condition is a worse failure mode than one well-chosen signal, and the JSON is a superset of what the prose says.

### `config validate` runs before the lint, and both run

The two commands see different things, measured against the pin:

| | hard schema errors | renamed legacy keys | schema-valid health concerns |
|---|---|---|---|
| `config validate` | reported, with file line numbers | reported, with canonical replacement | **not reported** |
| `doctor --lint --json` | reported | reported | reported |

`config validate` is the better error reporter — it names locations:

```
Config needs correction: /cfg/bad.json
  - bad.json:103 — agents.defaults.maxConcurrent: Invalid input: expected number, received string
  - bad.json:2 — gateway: Unrecognized key: "prot"
```

But the order is not a stylistic choice. On a config whose validation fails, `doctor` short-circuits: measured `checksRun: 1, checksSkipped: 0`, with only `core/doctor/final-config-validation` reported. A lint result obtained after a validation failure is therefore empty of information about the other 32 checks, and must not be read as a pass. The script runs `config validate` first and stops on its failure.

The strict schema is also what satisfies the "unsupported or incorrectly configured properties" goal with no extra work: unrecognized keys are hard errors, so a typo like `prot` fails rather than being silently ignored.

### The lint gates at `warning`, with three named exclusions

Measured on the shipped config with a dummy gateway token exported and three checks skipped: `ok: true, checksRun: 33, checksSkipped: 33, findings: []`. The clean baseline is zero findings, not zero errors, so the gate can be set at `--severity-min warning` without starting out red.

Excluded checks, each describing the validating environment rather than the config:

| `checkId` | Why it cannot pass in CI |
|---|---|
| `core/doctor/runtime-tool-schemas` | Dials the Composio MCP endpoint. Reports `severity: error` on DNS failure, so it would fail every run. |
| `core/doctor/heartbeat-cadence-migration` | Wants runtime `cron/jobs.json`, which lives on the VPS, not in this repo. |
| `core/doctor/node-hosting-preconditions` | Flags loopback binding; `--bind lan` comes from the compose `command`, not the config. |

`core/doctor/gateway-auth` was initially in this list and is deliberately not: exporting a dummy `OPENCLAW_GATEWAY_TOKEN` clears it, because the token legitimately lives in the environment. The principle is to make the validating environment honest first and suppress a check only when no honest environment would satisfy it. Each exclusion is an explicit `--skip <id>`, so the set is auditable in the script rather than implied by a severity threshold.

Alternative considered: gate at `--severity-min error` and ignore warnings. Rejected on measurement: a hardcoded credential in a secret-bearing field is accepted by `config validate` as a valid string and reported only by the lint, as `core/doctor/security` at `warning` severity. An error-only gate would let a plaintext token through — the one class of defect this repository most needs to catch.

Measured correction to an earlier assumption: `agents.defaults.models` without `modelPolicy.allow` is **not** in this class on the pinned version. That was the legacy implied-allowlist shape the preceding change retired, and 2026.10.7 reports nothing for it — `config validate` accepts it and the lint returns zero findings. The class is real and gated, but this is not one of its members.

### One code path: the container, in CI as well as locally

CI runs `scripts/validate-config.sh` unchanged rather than installing node with `actions/setup-node` and calling `npx` directly. The gate's value is that the pre-commit hook, the pull request gate, and the release gate cannot disagree about whether a config is valid, which only holds if they execute the same code. A GitHub-only fast path would be a second implementation of the most consequential check, diverging first on node version — the dimension that made the container necessary in the first place.

The cost is roughly 90–120s per run for the base image pull plus the `npx` download. Accepted for a gate that runs on pull requests to a configuration repository. If it becomes annoying, the fix is to cache or pre-build an image carrying the pinned CLI, which keeps the single code path; it is not to add a second one.

Alternative considered: `setup-node` with the version parsed from the Dockerfile's `FROM` line. Faster, and the node version would still derive from the pin, but it reintroduces precisely the two-code-path shape the preceding change rejected for this script.

### Checks are ordered cheap-and-offline first

Order: JSON parse → secret scan → env-var contract → `docker compose config -q` → ShellCheck → pinned schema validation → structured lint → advisory newest-release check.

Everything before the schema check runs offline in under a second, so a run whose container step cannot start has still reported every finding it could reach. This is the same reasoning the preceding change used to order the JSON and secret checks ahead of the schema check, extended to the new checks. It also means a contributor with three unrelated defects learns about all three from one run.

The gate stops at the first failing step rather than collecting every failure. Running later checks against a config that failed to parse produces noise, not information.

### The environment-variable contract is checked by comparing three files, ignoring comments

`scripts/check-env-vars.sh` extracts referenced names from `config/openclaw.json` (`${VAR}`) and `docker/docker-compose.yml` (`${VAR}`, `${VAR-}`, `${VAR:-default}`), then compares them against the names declared in `docker/.env.example`.

Comments are excluded on both sides, which is what makes the check correct rather than merely strict. `GIT_WORKSPACE_REPO_SECOND` and `GIT_WORKSPACE_REMOTE_SECOND` appear only inside the commented-out multi-agent block in `docker-compose.yml`, and only as commented examples in `.env.example`. Reading comments on one side but not the other would report drift that does not exist; ignoring them on both sides keeps the documented multi-agent recipe working without listing per-agent variables as live references.

The check is one-directional: every referenced name must be declared. A declared-but-unreferenced name is not a failure, because `.env.example` legitimately documents values consumed by neither file — `ANTHROPIC_API_KEY` reaches the container for fallback model access, and `GHCR_USERNAME` is consumed by compose's image reference rather than by a container.

Alternative considered: also fail on declared-but-unreferenced names. Rejected for now — it would fail on the legitimate cases above, and tightening it would mean classifying each variable by consumer, which is more machinery than the problem warrants.

### Required variables are marked `:?`, because "no default" does not mean required

An earlier assumption in this design was that interpolating `${VAR}` without a default makes a variable required. Compose does not work that way. Measured with `docker compose config -q` and `OPENAI_API_KEY` unset:

| Form | Unset at startup | Exit |
|---|---|---|
| `${OPENAI_API_KEY}` | warning, substitutes a blank string | 0 |
| `${OPENAI_API_KEY:?message}` | `required variable OPENAI_API_KEY is missing a value: message` | 15 |

Plain `${VAR}` therefore boots the stack half-broken with an empty credential — the exact failure the *Required variables are distinguishable from optional ones* requirement forbids. Every credential the deployment cannot run without is marked `${VAR:?<how to obtain it>}`: `OPENROUTER_API_KEY`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_USER_ID`, `OPENCLAW_GATEWAY_TOKEN`, `GHCR_USERNAME`, `OPENAI_API_KEY`, and both Composio variables. `ANTHROPIC_API_KEY`, `BRAVE_API_KEY` and `GH_TOKEN` keep their empty defaults, since each only disables a feature.

Composio is in the required set on evidence, not preference. With `COMPOSIO_MCP_URL` empty, the placeholder is not expanded at all and the literal survives into the config, which the pinned version then rejects:

```
openclaw.json:133 — mcp.servers.composio.url: Invalid URL, got: "${COMPOSIO_MCP_URL}"
```

So the gateway cannot boot without it. Failing at `docker compose up` with a named variable is strictly better than failing later inside the container on a config error that does not mention the environment.

This is a deliberate behavior change: a deployment missing a credential now refuses to start instead of starting degraded. Accepted on the grounds that every variable in the required set is one the stack cannot actually function without, so the previous behavior only delayed the failure and detached it from its cause.

Alternative considered: document the distinction in `.env.example` and leave compose untouched. Rejected — it leaves the blank-string boot in place, which is how `OPENAI_API_KEY` could silently disable audio transcription while the stack reported itself healthy.

### Brave is reconciled by name, not by enabling search

`docker/.env.example` declares `BRAVE_SEARCH_API_KEY`; `docker-compose.yml` passes `BRAVE_API_KEY: ${BRAVE_API_KEY-}`. An operator who fills in the documented name therefore ships an empty value into the container.

The pinned schema does not settle which name is right: it contains no Brave Search provider at all (its only "Brave" mention is a browser-profile note about user data directories), and `tools.web.search.provider` is documented as *"auto-detected from available API keys if omitted"*, with detection living in the runtime rather than the schema.

The documented name is therefore changed to `BRAVE_API_KEY`, matching what compose already injects. This makes a documented value actually reach the process that might auto-detect it, and changes nothing about whether search is enabled. Enabling `tools.web.search` explicitly is left out of scope; the variable keeps its `-` default in compose, so it stays optional.

Alternatives considered: changing compose to pass `BRAVE_SEARCH_API_KEY` (preserves the documented spelling but bets on an auto-detection name that could not be confirmed); removing the variable from both files (defensible, since search is never enabled, but discards an operator-facing option).

### The forward-compatibility check is advisory and cannot fail the run

A final step validates the config against the newest published release, resolved at run time from the registry. Measured: the shipped config is accepted by `2026.10.9` (current `latest`) as well as by the pinned `2026.10.7`.

It never fails the gate. The gateway runs the pinned version, so the newest release's opinion is information about a future upgrade, not a verdict on this pull request. Letting a `latest` publish turn every pull request red would be an outage caused by the gate. Its output is a readiness signal to consult when bumping the pin.

### No `paths:` filter, and the release gate gains the same env check

The workflow triggers on every pull request targeting `main`. A `paths:`-filtered workflow does not report a conclusion on pull requests that miss the filter, so making it a required status check would leave unrelated pull requests permanently unmergeable. The checks are cheap enough that always running them is simpler than the alternatives.

`push: main` is included as well, so a commit that reaches `main` outside the pull request flow is still validated.

**Publish image** gains a `check-env-vars.sh` step alongside its existing two. Without it, the two gates would enforce different contracts, and a tag could publish with the exact drift the pull request gate rejects.

## Risks / Trade-offs

- **Skipped `checkId`s could be renamed or retired by a future OpenClaw release** → A stale `--skip` is silently inert, which could let a real finding through on a pin bump. Mitigation: the skip list lives in one place in the script with a comment naming why each exists, and a pin bump should re-measure the clean baseline. Not solvable from inside the script, since `doctor` does not report unknown skip ids.
- **Validation requires Docker and network access** → The offline checks are ordered first and still run; a missing container runtime fails loudly rather than skipping, per the existing principle. CI has both.
- **`npx -y` re-downloads the pinned package every run** → 90–120s per pull request. Accepted; the mitigation if it bites is a cached image, not a second code path.
- **The advisory step depends on the registry's `latest` tag** → It is non-blocking by construction, so a registry hiccup or an unparseable newest version degrades to no signal rather than a failed run.
- **`check-secrets.sh` carries the pattern `[A-Za-z0-9+/]{40,}={0,2}`** → Matches any 40-character alphanumeric run, so a long hash or base64 blob would fail the gate as a "secret". Wiring the script to pull requests raises the cost of that false positive from a local annoyance to a blocked pull request. Left as-is here to keep this change's scope on config validation; flagged as a follow-up, and it fails closed rather than open.
- **The compose check needs a file the repository deliberately does not contain** → `docker-compose.yml` declares `env_file: .env`, and Compose refuses to parse the file at all when it is absent, so the check fails in CI while passing on any developer machine that has completed setup. The gate creates an empty `docker/.env` when none exists; interpolation values come from the step's `env:` block, not from that file. This one escaped local verification because the working copy had a real `docker/.env` — the reliable way to test a gate step is against `git archive HEAD` extracted to a clean directory, not against the working tree.
- **`jq` becomes a hard dependency of the validation script** → Already required for the existing JSON parse check, and present on GitHub runners; the script fails with a named prerequisite if it is missing.
- **Reconciling Brave by name does not prove the name is correct** → Auto-detection could use a different spelling. The variable is optional either way, so the downside is unchanged from today: search without a key. Settling it properly means enabling `tools.web.search` with an explicit provider, which is out of scope.

## Migration Plan

1. Rework `scripts/validate-config.sh` and add `scripts/check-env-vars.sh`. Run both locally; `validate-config.sh` must pass against the pinned version, and `check-env-vars.sh` must fail, naming the five drifted variables.
2. Clear the drift in `docker/.env.example` and `docker/docker-compose.yml`, then re-run `check-env-vars.sh` until it passes. The env fixes land in the same change as the check so the gate is green on arrival.
3. Add the **Validate config** workflow and the `check-env-vars.sh` step in **Publish image**. Add the env check to `.githooks/pre-commit` for parity.
4. Update `README.md` and `CONTRIBUTING.md`.
5. Open the pull request and confirm the workflow runs on it, fails on a deliberately broken config, and passes on the real one.
6. Optionally make **Validate config** a required status check on `main` once it has passed on a real pull request.

**Rollback:** the workflow and the new script are additive — deleting the workflow file restores the previous state with no runtime effect, since nothing here is consumed by the gateway. The `.env.example` and compose edits are independent of the gate and should be kept; reverting them would restore the Brave mismatch. The `validate-config.sh` rework is the only piece a revert would regress, and it regresses to a weaker gate, not a broken one.

## Open Questions

- Whether `core/doctor/security` would flag any field in the shipped config once validation stops substituting placeholders. Measured clean today, so the gate's baseline is unaffected; if a future config hardcodes a credential, this check catches it, which is the intended behavior rather than a question to resolve.
- Which search-provider environment variable the runtime's auto-detection actually reads. Deferred deliberately: the variable is optional, nothing in the shipped config enables web search, and answering it belongs to a change that configures `tools.web.search` explicitly.
