# Proposal

## Why

The gateway refuses to boot: `agents.list` moved to keyed `agents.entries` in the pinned OpenClaw version (`2026.10.7`), and three further keys in `config/openclaw.json` are flagged as legacy. The shipped config has drifted behind the schema it is validated against, and nothing in the repo detects that drift — `scripts/validate-config.sh` only checks that the file is JSON and contains no literal credential, so the broken config passed CI and was published.

Fixing only the config leaves the mechanism that produced the outage in place. The documented remedy (`openclaw doctor --fix`) repairs the deployed copy at `~/.openclaw/openclaw.json`, which the next `make push-config` overwrites from this repo — so the gateway would break again on the following config push.

## What Changes

- Migrate `config/openclaw.json` to the canonical shapes accepted by the pinned OpenClaw version:
  - `agents.list[]` → keyed `agents.entries` (the key is the agent id; the entry drops `id`, and the retired `default: true` marker goes with it for the single-agent roster).
  - `tools.media.audio.models[]` → `tools.media.models[]` with `capabilities: ["audio"]` on the entry.
  - `logging.redactSensitive: "tools"` → removed; `"tools"` is now the built-in behavior, so redaction is unchanged.
  - `agents.defaults.modelPolicy.allow` added to state the `/model` override allowlist explicitly. Previously the presence of `agents.defaults.models` implied that restriction; `models` now carries aliases and params only.
- Repair two further keys that the pinned version rejects outright. Both are pre-existing and independent of the renames above; they only became visible once the fatal `agents.list` error stopped masking the rest of the file:
  - `agents.defaults.utilityModel` was a `{primary, fallbacks}` object, and the pinned schema accepts only a model ref string for that slot with no fallback list at any scope. The fallback `openrouter/openai/gpt-oss-20b` is therefore dropped, and the *Task-specific model slots* requirement is amended to scope the fallback rule to the slots that support one.
  - `channels.telegram.streaming` was the bare string `"partial"`, valid only as `{"mode": "partial"}`. It keeps that mode, plus `chunkMode: "newline"` and an explicit `preview.toolProgress`, so incremental reply streaming is preserved rather than silently dropped to the channel's `"progress"` default.
- Extend `scripts/validate-config.sh` to validate the config against the pinned OpenClaw version's real schema, so schema drift fails locally and in the **Publish image** workflow instead of at gateway startup.
- Replace the snapshot blacklist of forbidden keys in `model-routing-config` with a requirement that the shipped config validates against the pinned version. The existing requirement names three keys retired in an earlier cycle; it could not catch this round of renames, and will not catch the next one.
- Update `README.md` where it documents the moved keys: the `tools.media.audio` transcription note and the `/model` escalation description.

No behavior change is intended. The migration preserves the current model routing, the current `/model` allowlist, and the current redaction mode.

**BREAKING**: none for users of the gateway. The migrated config requires OpenClaw at or after the version that introduced `agents.entries`; it is not loadable by a gateway image older than the pinned `2026.10.7`, so a config push must not precede an image rollback.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `model-routing-config`: the requirement *Only documented configuration keys* is replaced by one that requires the shipped config to validate against the pinned OpenClaw version, enforced by the validation script rather than by inspection. The *Manual escalation aliases* requirement gains the explicit `agents.defaults.modelPolicy.allow` allowlist that now carries the restriction formerly implied by `agents.defaults.models`.

## Impact

- `config/openclaw.json` — the four migrations above.
- `scripts/validate-config.sh` — schema validation step; must resolve the OpenClaw version pinned in `docker/Dockerfile` (`OPENCLAW_VERSION`) rather than whatever is installed, and must tolerate the `${ENV_VAR}` placeholders in the config.
- `.github/workflows/` (**Publish image**) — inherits the stronger validation through the existing pre-build step; the `ghcr-image-publish` requirement *Pre-build validation* already mandates running the script, so no workflow requirement changes.
- `README.md` — the models table note on audio transcription and the `/model` escalation paragraph.
- Deployment order — the config push and the image deploy are separate workflows in the infra repo (`make push-config`, `make deploy`). The migrated config needs the pinned image already running.
- Open question for design: `modelPolicy.allow` restricts session/run overrides, and the pinned runtime substitutes the default model when the configured default is not in the allowlist. The two aliased refs do not include the haiku default or its fallbacks, so the allowlist contents need a deliberate decision rather than a verbatim copy of the old implied restriction.
