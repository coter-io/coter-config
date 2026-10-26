# Design

## Context

`config/openclaw.json` is pushed to the VPS by the infra repo (`make push-config`), validated locally by `scripts/validate-config.sh` (JSON validity plus raw-key patterns). `docker/docker-compose.yml` already passes `OPENROUTER_API_KEY`; `docker/.env.example` does not list it. Schema facts come from the OpenClaw docs (config-agents/models, heartbeat-compaction-and-streaming, providers/openrouter, automation/cron-jobs). Prices are USD per million input/output tokens from OpenRouter's `/api/v1/models` on 2026-10-26 and will drift. See proposal.md for motivation.

## Goals / Non-Goals

**Goals:**
- One provider key for chat, utility, vision, PDF and image generation.
- Cost tiers: cheapest model for housekeeping, cheap-but-capable default, manual escalation.
- Only documented keys.

**Non-Goals:**
- Changing channels, MCP servers, gateway, or the Docker image.
- Migrating audio transcription off OpenAI.
- Automated quality benchmarking of the chosen models.

## Decisions

| Slot | Choice | Price | Why |
|---|---|---|---|
| `model.primary` | `anthropic/claude-haiku-5.5` | 0.10 / 0.50 | text+image+file, 1M context; cheapest model trusted for MCP tool-calling |
| `model.fallbacks` | `openai/gpt-6.1-terra`, `google/gemini-3.6-flash` | 1 / 5, 0.75 / 3.75 | different vendors survive a single-vendor outage; rarely invoked |
| `utilityModel` | `qwen/qwen3.7-flash` → `openai/gpt-oss-20b` | 0.03 / 0.13, 0.018 / 0.09 | titles and recaps need no quality |
| `imageModel` | `qwen/qwen3.8-flash` → `google/gemini-3.1-flash-lite` | 0.15 / 0.47, 0.25 / 1.5 | only fires if the primary lacks image input |
| `pdfModel` | `google/gemini-3.1-flash-lite` → `anthropic/claude-haiku-5.5` | 0.25 / 1.5 | native file input, 1M context |
| `mediaModels.image` | `google/gemini-3.1-flash-image` → `google/gemini-3.1-flash-lite-image` | 0.50 / 3, 0.25 / 1.5 | cheapest Gemini image generators; token-priced |
| `compaction.model` | unset | | follows the primary (already cheap) |
| Heartbeat | automation job, `qwen/qwen3.7-flash` | 0.03 / 0.13 | runs every ~30 min |
| Aliases | `sonnet` → `claude-sonnet-5.5` (2 / 10), `terra` → `gpt-6.1-terra` | | manual escalation |

**Cheap default over a stronger one.** Alternative: `gpt-6.1-terra` or Sonnet 5.5 as primary (10–20x cost). Chosen because fallbacks don't fire on weak answers, so escalation is manual via `/model`; revisit if Haiku mis-handles tool calls in practice.

**`mediaModels.image` instead of `imageGenerationModel`.** The old key is absent from the docs; the documented slot is `mediaModels.image`. Alternative of keeping both was rejected to avoid ambiguous precedence.

**No `modelPolicy.allow`.** Omitting it allows any model, which keeps the heartbeat job's model and `/model` overrides valid. Alternative `["openrouter/*"]` would also work but adds nothing for a single-user bot.

**Heartbeat outside `openclaw.json`.** `agents.defaults.heartbeat` is deprecated; the job is created with `openclaw automations add|edit --model … --fallbacks …` on the VPS and documented in the README.

**Audio unchanged.** `tools.media.audio` keeps `openai/gpt-4o-transcribe-mini`, and `OPENAI_API_KEY` stays in compose. Whether that slot accepts an OpenRouter provider is unverified, and changing it is out of scope.

**Routing defaults.** `data_collection: "deny"` and `require_parameters: true` under `models.providers.openrouter.params.provider`. Alternative `sort: "price"` rejected as it can pick slow or low-quality providers.

## Risks / Trade-offs

- [Haiku 5.5 price ($0.10/$0.50) is unusually low vs. Haiku 4.5] → confirm on OpenRouter's model page before deploy; swap primary to `gpt-6.1-terra` if wrong.
- [Weak tool-calling on the cheap default] → use `/model sonnet`; change primary if it recurs.
- [`data_collection: "deny"` narrows the provider pool] → drop it if requests fail with no available provider.
- [`alias` key name taken from memory, not fetched docs] → verify with `openclaw config schema` / `openclaw doctor` before pushing.
- [Model IDs and prices drift] → re-check the OpenRouter catalog at deploy time.
- [Image-generation cost is token-based, so per-image cost varies] → monitor OpenRouter usage after rollout.

## Migration Plan

1. Edit `config/openclaw.json`, `docker/.env.example`, `README.md`; run `bash scripts/validate-config.sh`.
2. Put `OPENROUTER_API_KEY` in the infra repo's `secrets/openclaw.env`; `make push-env`.
3. `make push-config` (restarts the gateway).
4. On the VPS: `openclaw doctor`, then create/edit the heartbeat job with the cheap model.
5. Send a test message, a PDF, and an image-generation request via Telegram.

Rollback: restore the previous `config/openclaw.json` from git and `make push-config`.
