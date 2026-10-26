# Tasks

## 1. Pre-flight checks

- [x] 1.1 Re-check every chosen model id and price against `https://openrouter.ai/api/v1/models` (jq filter on the ids in design.md), and verify all ids exist and Haiku 5.5 is still ~$0.10/$0.50; adjust design.md if not
- [x] 1.2 Confirm the `alias` key and the `mediaModels.image` / `utilityModel` shapes with `openclaw config schema` and verify the output lists them

## 2. Config rewrite

- [x] 2.1 In `config/openclaw.json`, replace `agents.defaults.model`, add `utilityModel`, `imageModel`, `pdfModel` with the OpenRouter refs from design.md, and verify with `jq '.agents.defaults' config/openclaw.json`
- [x] 2.2 Replace `imageGenerationModel` with `mediaModels.image`, drop the OpenAI `params.transport` entries, and verify with `jq 'paths|join(".")' config/openclaw.json | grep -E 'imageGenerationModel|transport'` returning nothing
- [x] 2.3 Add `models` aliases (`sonnet`, `terra`) and `models.providers.openrouter.params.provider` (`data_collection: "deny"`, `require_parameters: true`), and verify with `jq`
- [x] 2.4 Keep `tools.media.audio` unchanged; verify with `git diff` that only the intended blocks changed
- [x] 2.5 Run `bash scripts/validate-config.sh` and `bash scripts/check-secrets.sh` and verify both pass

## 3. Secrets and docs

- [x] 3.1 Add `OPENROUTER_API_KEY` (with a `openrouter.ai/keys` hint) to `docker/.env.example`, and verify with `grep OPENROUTER_API_KEY docker/.env.example docker/docker-compose.yml`
- [x] 3.2 Add a README section on model tiers, `/model sonnet` escalation, and the heartbeat command `openclaw automations add|edit --model openrouter/qwen/qwen3.7-flash …`, and verify the documented command syntax against the automation docs

## 4. Deploy verification

- [x] 4.1 After `make push-env` and `make push-config`, run `openclaw doctor` on the VPS and verify no deprecated-key or unknown-key warnings
- [x] 4.2 Create or edit the heartbeat job with the cheap model and verify with `openclaw automations show <job-id>`
- [x] 4.3 Via Telegram, verify a normal reply, a PDF summary, an image-generation request and a `/model sonnet` switch each succeed, and check OpenRouter's activity page for the expected models

## Workflow follow-up

- Archive the change after the deployment is verified.
