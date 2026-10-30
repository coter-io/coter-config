# Proposal

## Why

`tools.media.models` names `gpt-4o-transcribe-mini`, which is not a real model id — OpenAI's
transcription models are `gpt-4o-transcribe` and `gpt-4o-mini-transcribe`, and the words are
transposed. Inbound Telegram voice notes are therefore almost certainly failing today, and with a
single entry and no fallback they produce a failure marker instead of a transcript. The audio slot
is also the last consumer of `OPENAI_API_KEY`: the
`2026-10-26-switch-to-openrouter-models` change left it on OpenAI because whether that slot accepts
an OpenRouter provider was unverified. It does — the pinned `openclaw@2026.10.7` implements
OpenRouter STT — so fixing the model id and moving the slot to OpenRouter can be done together,
which removes the second credential rather than re-establishing it under a corrected name.

## What Changes

- Replace the single broken `tools.media.models` entry with two OpenRouter provider entries:
  `openai/whisper-large-v3-turbo` (primary) and `openai/gpt-4o-mini-transcribe` (fallback). Both use
  `provider: "openrouter"`, so the deployment keeps one model credential while gaining the
  per-capability fallback the other model slots already have.
- Set `tools.media.audio.enabled: true` explicitly, matching the OpenClaw documentation examples,
  rather than relying on the default-when-unset behaviour.
- **BREAKING** (operator-facing): remove `OPENAI_API_KEY` from `docker/docker-compose.yml`,
  `docker/.env.example`, and the `validate-config.yml` placeholder env. An existing `.env` keeps
  working — the variable is simply ignored — but the documented contract no longer includes it, and
  the stack no longer refuses to start without it.
- Correct `README.md`, which states audio "still calls OpenAI directly, so `OPENAI_API_KEY` must
  stay set", and document the audio slot in the models table alongside the other slots.

Out of scope: TTS (`tts.providers`), image/video/music generation slots, and the local
whisper-CLI fallback option — a CLI entry would require installing a transcription binary in
`docker/Dockerfile`, which belongs in its own change.

## Capabilities

### New Capabilities

None. Audio model selection is model routing, which `model-routing-config` already owns.

### Modified Capabilities

- `model-routing-config`: its *OpenRouter as chat model provider* requirement enumerates "every
  chat, utility, vision and PDF model" and deliberately excludes audio, and *Task-specific model
  slots* has no audio scenario. The delta extends both to cover audio transcription, and states
  that `OPENROUTER_API_KEY` is the deployment's only model-provider credential — a claim the
  capability could not previously make.

`deployment-env-contract` is intentionally **not** modified. All five of its requirements are
variable-agnostic ("every referenced variable is documented", "required variables are
distinguishable from optional ones"); dropping `OPENAI_API_KEY` satisfies them unchanged rather
than altering them, and `scripts/check-env-vars.sh` enforces the three-way consistency
automatically. `config-pr-validation` is likewise unmodified: no requirement names which specific
variables the workflow supplies.

## Impact

| File | Change |
|---|---|
| `config/openclaw.json` | `tools.media` — two OpenRouter audio entries, `audio.enabled` |
| `docker/docker-compose.yml` | remove the `OPENAI_API_KEY` line and its `:?` guard comment reference |
| `docker/.env.example` | remove the OpenAI section |
| `.github/workflows/validate-config.yml` | remove `OPENAI_API_KEY: ci-placeholder` |
| `README.md` | audio row in the models table; correct lines 87-88 |
| `openspec/specs/model-routing-config/spec.md` | via the delta, on archive |

Runtime and cost: transcription moves from OpenAI to OpenRouter-routed
`openai/whisper-large-v3-turbo`, served by DeepInfra at roughly $0.012 per audio hour. The
fallback bills per token ($1.25/M in, $5/M out). Telegram voice notes arrive as OGG/Opus, which
the OpenRouter STT path maps to its `ogg` format.

Verification risk: the model ids and the OpenRouter STT route are confirmed against the pinned
version's shipped code and the live OpenRouter catalog, but no transcription request has been made
with a real key. Whether `models.providers.openrouter.params.provider` (`data_collection: "deny"`,
`require_parameters: true`) reaches the STT request is unresolved and is carried as a task —
the STT path builds its own JSON body and that routing object is documented only for
chat-completions routes.
