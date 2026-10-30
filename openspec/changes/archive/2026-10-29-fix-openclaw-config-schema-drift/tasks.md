# Tasks

## 1. Schema validation gate

- [x] 1.1 Add pinned-version resolution to `scripts/validate-config.sh`: extract `OPENCLAW_VERSION` from `docker/Dockerfile` and fail with an explicit message if the line cannot be parsed; verify by running the script and seeing the resolved version echoed, and by temporarily mangling the `ARG` line to confirm the script fails instead of defaulting to an unpinned version
- [x] 1.2 Add the containerized `openclaw config validate` step after the existing JSON and secret-scan checks, mounting the config read-only with `OPENCLAW_CONFIG_PATH`; verify it fails on the current unmigrated config and names `agents.list` among the problems
- [x] 1.3 Treat legacy keys as failures. `openclaw config validate` reports hard schema errors only — it calls a config with legacy-only drift "valid" and exits 0 — so legacy detection must come from `openclaw doctor`, whose output names each legacy key but which also exits 0. Fail on `Legacy config keys detected` appearing in the doctor output; verify with a scratch config that reintroduces a legacy-only key and confirm the script exits non-zero
- [x] 1.4 Fail with an explicit message when Docker is unavailable rather than skipping the check; verify by running the script with `PATH` stripped of `docker` and confirming a non-zero exit that names Docker as the missing requirement
- [x] 1.5 Document the validation step in `README.md` (the troubleshooting section that already lists `bash scripts/validate-config.sh`), stating that it needs Docker and validates against the Dockerfile's pinned version; verify the documented command runs as written
- [x] 1.6 Substitute `${VAR}` placeholders with well-formed dummy values in a throwaway copy before validating, because format-checked fields (`mcp.servers.*.url`) reject a literal placeholder; verify the real config is left unmodified and that the URL error no longer appears

## 2. Config migration

- [x] 2.1 Convert `agents.list[]` to keyed `agents.entries` in `config/openclaw.json` — key `main`, entry keeps `identity`, drops `id` and the retired `default: true`; verify `scripts/validate-config.sh` no longer reports `agents.list`
- [x] 2.2 Add `agents.defaults.modelPolicy.allow` with the haiku default, both fallbacks, and the sonnet alias ref, per design.md; verify the script no longer reports `agents.defaults.models` as legacy and the alias refs in `agents.defaults.models` all appear in the allowlist
- [x] 2.3 Move `tools.media.audio.models[]` to `tools.media.models[]` with `capabilities: ["audio"]`; verify the script no longer reports `tools.media`
- [x] 2.4 Remove `logging.redactSensitive`; verify the script no longer reports it and that `logging` retains `level` and `consoleLevel`
- [x] 2.6 Replace the `agents.defaults.utilityModel` object with a bare model ref string — the pinned schema accepts only a string for that slot and offers no fallback list at any scope, so `openrouter/openai/gpt-oss-20b` is dropped; verify the validator no longer reports `utilityModel`
- [x] 2.7 Convert `channels.telegram.streaming` from the invalid bare string `"partial"` to the canonical object form `{"mode": "partial", "chunkMode": "newline", "preview": {"toolProgress": true}}`. Telegram is a preview-capable channel, so `mode: "partial"` preserves the original intent exactly; only the string shorthand was invalid. `chunkMode: "newline"` splits finalized text on paragraph boundaries instead of mid-sentence, and `preview.toolProgress` pins tool-row visibility; verify the validator passes and `streaming.mode` reads `partial`
- [x] 2.8 Amend the `model-routing-config` delta spec so *Task-specific model slots* scopes the "at least one fallback" rule to the slots whose schema supports fallbacks, recording that the utility slot takes a single ref; verify `openspec validate --strict` passes and the requirement matches the shipped config
- [x] 2.5 Update the `README.md` descriptions of the moved keys — the audio transcription note under the models table and the `/model` escalation paragraph, which must now describe the explicit allowlist; verify no README reference to `tools.media.audio` or to `agents.defaults.models` as the override restriction remains

## 3. Verification

- [x] 3.1 Run `bash scripts/validate-config.sh` end to end and confirm it passes with zero problems and zero legacy keys against the pinned version
- [x] 3.2 Confirm the migration is behavior-preserving by diffing the config: every model ref present before is still present in the same slot, the OpenRouter routing params are untouched, and no key changed outside the four migrations plus the two approved pre-existing fixes (`utilityModel`, `channels.telegram.streaming`). The only model ref dropped is the utility fallback `openrouter/openai/gpt-oss-20b`, which the pinned schema cannot express
- [x] 3.3 Run `openspec validate fix-openclaw-config-schema-drift --strict` and confirm the change validates

## Workflow follow-up

- Deploy order on release: confirm the running gateway is at or after the pinned `2026.10.7` before `make push-config` from the infra repo, per design.md's migration plan.
- Archive the change after the gateway is confirmed booting on the migrated config.
