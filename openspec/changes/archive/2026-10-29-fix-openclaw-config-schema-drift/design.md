# Design

## Context

See proposal.md — Why. Constraints that shape the approach:

- `config/openclaw.json` is not read by anything in this repo. It is SCP'd to `~/.openclaw/openclaw.json` by the infra repo's `make push-config`, so this repo has no runtime to test against and no feedback loop other than validation.
- The authoritative schema lives in the `openclaw` npm package at the version pinned by `OPENCLAW_VERSION` in `docker/Dockerfile` (currently `2026.10.7`). That package declares `engines.node >= 24.22.1 < 25 || >= 26.12.1` and refuses to install on older node.
- The config is full of `${ENV_VAR}` placeholders. Any validation must work without real secrets.
- `scripts/validate-config.sh` is already wired into the **Publish image** workflow (`ghcr-image-publish` → *Pre-build validation*), so strengthening the script strengthens CI with no workflow change.

## Goals / Non-Goals

**Goals:**

- Canonical config shapes for the pinned version, with routing, override allowlist, and redaction behavior unchanged.
- Validation that fails on schema drift at edit time and in CI, deriving the version from the Dockerfile pin so the two cannot disagree.

**Non-Goals:**

- Upgrading OpenClaw past the pinned `2026.10.7`. The npm `latest` is `2026.10.9`; bumping it is a separate change with its own image rebuild.
- Changing which models serve which slot, or the OpenRouter routing params.
- Validating the infra repo's push mechanics, or anything about `~/.openclaw` on the VPS.
- Resolving the `:latest` image reference in `docker/docker-compose.yml` against the Dockerfile's build-arg pin. Real, but a separate concern from config schema drift.

## Decisions

### Hand-author the canonical shapes; do not run `doctor --fix`

`doctor --fix` only repairs the copy it is pointed at. Running it on the VPS leaves this repo legacy and the next `push-config` reintroduces the outage. It also writes bookkeeping (`meta.migrations.modelPolicyAllowlist`) into the file, which would then differ between the repo and the deployed copy with nothing comparing them.

Hand-authoring the canonical shapes avoids the marker entirely: the marker exists to record that a legacy map was interpreted, and a config that states `modelPolicy.allow` explicitly is never interpreted.

Alternative considered: run `doctor --fix` on a scratch copy and commit the result. Rejected — it imports the migration marker and `meta` churn into a file that is otherwise hand-maintained, and the four edits are small enough to make deliberately.

### `modelPolicy.allow` lists the full routing set

The legacy restriction was implied by `agents.defaults.models` having entries, which meant only the two aliased refs (sonnet, terra) were selectable. A verbatim copy of that would omit the haiku default and its fallbacks. The pinned runtime's `resolveOperatorModelDefault` substitutes a different default when the configured default is not allowed, so a verbatim copy risks silently moving the default model off haiku.

The allowlist therefore names the default, its fallbacks, and the aliases:

```
openrouter/anthropic/claude-haiku-5.5      (default primary)
openrouter/openai/gpt-6.1-terra            (fallback + "terra" alias)
openrouter/google/gemini-3.6-flash         (fallback)
openrouter/anthropic/claude-sonnet-5.5     ("sonnet" alias)
```

This preserves cost control — arbitrary premium models stay unselectable — while satisfying the delta spec's *Configured default stays selectable*.

The utility, image, and pdf slot models are deliberately absent: `allow` governs user-facing `/model` overrides, and those slots are selected by the runtime per task, not by a user.

Alternatives considered: aliases only (risks default substitution, as above); omit the allowlist entirely (loses the guardrail the README documents).

### Telegram keeps preview streaming, written in canonical form

`channels.telegram.streaming: "partial"` was invalid only as a *bare string*. Telegram is a preview-capable channel whose streaming schema is `{mode, chunkMode, preview, progress, block}`, with `mode` taking `off | partial | block | progress`, so `{"mode": "partial"}` expresses the original intent exactly. Removing the key instead would have moved the channel to its default `"progress"` mode, which suppresses incremental answer text and delivers the answer only at the end — a behavior change dressed as a migration.

The shipped value adds two deliberate refinements: `chunkMode: "newline"` splits finalized text on paragraph boundaries rather than mid-sentence at the character limit, and `preview.toolProgress: true` pins tool-row visibility, which is a default today but a stated requirement worth surviving an upgrade.

What is *not* set, and why:

- `preview.chunk.{minChars,maxChars,breakPreference}` is inert under `mode: "partial"` — `resolveChannelDraftStreamingChunking` is consulted only when `mode === "block"`. Setting it would imply tuning that does not happen.
- First paint (30 chars), draft edit cadence (1000 ms, floor 250) and rotation point (`textChunkLimit`) are hardcoded in the pinned version. The 1 s cadence plus a flood gate that drops superseded edits is what keeps the draft from flickering, so there is nothing to tune.
- `typingIndicator` already resolves to `"instant"` for DMs, and group chats are disabled, so writing it would be a no-op.

Settings that would silently disable preview streaming, all currently unset and worth leaving that way: `reasoningDefault: "on"` (forces block streaming), `block.enabled: true`, `replyToMode` other than `"off"` when a quoted reply is present, and `agents.defaults.humanDelay`.

### Validation runs the pinned binary in a container

The script resolves `OPENCLAW_VERSION` from `docker/Dockerfile` and runs `openclaw config validate` in a throwaway container on the same node base image, with the repo config mounted read-only and `OPENCLAW_CONFIG_PATH` pointing at it:

```
PIN=$(grep -oE 'OPENCLAW_VERSION=[^ ]+' docker/Dockerfile | cut -d= -f2)
docker run --rm \
  -v "$CONFIG:/cfg/openclaw.json:ro" \
  -e OPENCLAW_CONFIG_PATH=/cfg/openclaw.json \
  node:24.22-bookworm-slim \
  npx -y "openclaw@$PIN" config validate
```

One code path, identical locally and in CI, and immune to whatever node the developer's machine has — relevant because the current laptop node (24.13.1) is below the package's floor and cannot install it at all.

Alternatives considered: host `npx` (fastest, but unusable on the current machine and lets local and CI results diverge with node version); host-with-Docker-fallback (best ergonomics, two code paths and a subtler failure surface for a script that runs in a release gate).

### The schema check is a hard gate, and legacy keys need a second command

The delta spec requires failing on shapes the pinned version reports as *legacy or invalid*. A legacy key is drift that has not yet become fatal — exactly what went undetected this time — so the script must not pass merely because the gateway would still boot.

One command cannot see both. Measured against the pinned version:

| | hard schema errors | legacy keys | exit code |
|---|---|---|---|
| `config validate` | reported | **not reported** — prints `Config valid` | 1 on errors, 0 otherwise |
| `doctor` | reported | reported, with the canonical replacement | **0 either way** |

`config validate` called a config carrying legacy `agents.defaults.models` "valid" and exited 0. The legacy list the gateway prints at startup comes from its config guard, which `config validate` does not run. So the gate runs both commands: `config validate` for hard errors, judged by exit code, then `doctor` for legacy keys, judged by `Legacy config keys detected` appearing in its output. `doctor` is run with a wide `COLUMNS` so its boxed output does not wrap mid-phrase.

Alternative considered: exit code from `config validate` alone. Rejected on evidence — it is blind to precisely the drift class this change exists to catch, which would have left the recurrence guard decorative.

### Placeholders are substituted before validating

`mcp.servers.*.url` is format-validated, so the literal `${COMPOSIO_MCP_URL}` fails as a malformed URL. The schema check is about config shape, not secret resolution, so the script validates a throwaway copy with every `${VAR}` replaced by a well-formed dummy — URL-named vars get a URL, everything else a plain token. The real config is never written to.

Alternative considered: allowlisting the URL error. Rejected — it would mask a genuinely malformed URL in the same field.

### Docker absence fails, it does not skip

A validation gate that silently skips when its tool is missing is how this drift reached a published image. If Docker is unavailable the script exits non-zero with an explicit message. The JSON and secret-scan checks still run first, so their findings are reported before the schema gate reports that it could not run.

## Risks / Trade-offs

- **Validation now requires Docker and network access** → The first two checks (JSON parse, secret scan) are ordered before the schema check and still run offline, so the cheap checks keep working. CI already has both.
- **`node:24.22-bookworm-slim` could resolve to 24.22.0, below the package floor** → The failure is loud (npm refuses to install, non-zero exit), not silent. Noted as a latent fragility of the existing Dockerfile pin rather than fixed here.
- **`npx -y` downloads the package on every run** (tens of seconds) → Acceptable for a pre-commit/pre-release gate. A cached local image is a later optimization if it becomes annoying.
- **Parsing `OPENCLAW_VERSION` out of the Dockerfile is textual** → If the `ARG` line is reformatted, extraction breaks. The script fails rather than falling back to an unpinned version, so a break is visible, not silently wrong.
- **The migrated config cannot be loaded by a pre-`agents.entries` gateway** → Ordering constraint, not a bug: deploy the image before pushing the config. Stated in the migration plan.

## Migration Plan

1. Migrate `config/openclaw.json`, strengthen `scripts/validate-config.sh`, update `README.md`.
2. Run `bash scripts/validate-config.sh` locally — it must pass against the pinned version.
3. Commit, push, tag, release, and publish the image if the pin changed. The pin does not change in this change, so the currently published `2026.10.7` image is already correct.
4. From the infra repo, confirm the running gateway is at or after `2026.10.7` (`make deploy` if not), **then** `make push-config`.
5. Confirm the gateway boots: the startup log reaches `cli.bootstrap.admission.config-guard` without the `OpenClaw config is invalid` block, and no `Legacy config keys detected` lines appear.

**Rollback:** `git revert` the config commit and `make push-config` again. The legacy config is loadable only by a gateway older than the breaking change, so a rollback of the config alone returns to the current broken state — the real rollback is forward. Keep the previous config out of production rather than reverting to it.

## Open Questions

- Whether the pinned `config validate` exits non-zero for legacy-only findings. The design works either way (the string check covers the gap), and the answer is observable the first time the script runs against a legacy config. It changes no spec, approach, or task.
