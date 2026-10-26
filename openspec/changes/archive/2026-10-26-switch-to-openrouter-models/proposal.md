# Proposal

## Why

`config/openclaw.json` routes every model slot to OpenAI directly and uses `agents.defaults.imageGenerationModel`, which the current OpenClaw docs do not list (the documented slot is `agents.defaults.mediaModels.image`), so image generation may be silently ignored. The default model (`openai/gpt-5.2`, ~$1.75/$14 per M tokens) is also far more expensive than needed for a low-volume Telegram assistant. OpenRouter exposes cheaper, multimodal models behind one API key (`OPENROUTER_API_KEY` is already wired in `docker/docker-compose.yml`), so this is the moment to consolidate providers and tier models by task.

## What Changes

- Route all model slots through OpenRouter using `openrouter/<vendor>/<model>` refs.
- Default model: `anthropic/claude-haiku-5.5` (~$0.10/$0.50 per M tokens); fallbacks on other vendors (`openai/gpt-6.1-terra`, `google/gemini-3.6-flash`).
- Add task-specific slots: `utilityModel` (cheapest tier), `imageModel`, `pdfModel`, and `mediaModels.image`.
- **BREAKING**: remove the undocumented `imageGenerationModel` key (replaced by `mediaModels.image`) and the OpenAI-only `params.transport` entries.
- Add `/model` aliases (`sonnet`, `terra`) so hard tasks can be escalated manually; fallbacks only cover failures, not weak answers.
- Set OpenRouter routing defaults (`data_collection: "deny"`, `require_parameters: true`).
- Document the heartbeat as an automation job with a cheap model (`openclaw automations add --model …`), because `agents.defaults.heartbeat` is deprecated and not configurable in `openclaw.json`.
- Add `OPENROUTER_API_KEY` to `docker/.env.example`.

## Capabilities

### New Capabilities
- `model-routing-config`: how the shipped OpenClaw config selects models per task (default, fallbacks, utility, vision, PDF, image generation, heartbeat) through OpenRouter, and which keys it must and must not use.

### Modified Capabilities
<!-- None: the existing ghcr-image-publish spec is unaffected. -->

## Impact

- `config/openclaw.json` (agents.defaults, new `env`/`models.providers` blocks)
- `docker/.env.example` (new `OPENROUTER_API_KEY`)
- `README.md` (model/heartbeat setup note)
- Runtime: one OpenRouter key replaces direct OpenAI model access for chat; audio transcription (`tools.media.audio`) still uses OpenAI directly and keeps `OPENAI_API_KEY` unless verified otherwise (see design).
- Operations: heartbeat job must be created/edited on the VPS after deploy.
