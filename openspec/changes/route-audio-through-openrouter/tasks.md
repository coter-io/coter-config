# Tasks

## 1. Confirm the model ids before editing anything

- [x] 1.1 Re-check both ids against the live catalog —
      `curl -s https://openrouter.ai/api/v1/models/openai/whisper-large-v3-turbo/endpoints` and the
      same for `openai/gpt-4o-mini-transcribe` — and verify each returns `modality: audio->transcription`
      with at least one endpoint; if either 404s, pick a replacement from the audio-capable set and
      record the substitution in design.md before continuing. These ids are absent from the plain
      `/api/v1/models` listing, so a catalog grep is not a valid check.
- [x] 1.2 Confirm the pinned version still ships the OpenRouter STT path by checking that
      `ARG OPENCLAW_VERSION` in `docker/Dockerfile` is unchanged from `2026.10.7`; if it has been
      bumped, re-verify `transcribeOpenRouterAudio` and
      `mediaUnderstandingProviderMetadata.openrouter` exist in the new version's package before
      relying on them

## 2. Route audio through OpenRouter

- [x] 2.1 In `config/openclaw.json`, replace the single `tools.media.models` entry with the
      `openai/whisper-large-v3-turbo` primary and `openai/gpt-4o-mini-transcribe` fallback, both
      `provider: "openrouter"` with `capabilities: ["audio"]`, and add `tools.media.audio.enabled: true`;
      verify with `jq '.tools.media' config/openclaw.json` showing two entries and no `provider: "openai"`
- [x] 2.2 Verify the edited config against the pinned schema with `bash scripts/validate-config.sh`
      and confirm it reports `Config validation passed` (this needs Docker running)
- [x] 2.3 Add an audio row to the README models table naming the slot
      (`tools.media.models`, `capabilities: ["audio"]`), both model ids, and a note that this slot
      takes bare upstream slugs rather than `openrouter/`-prefixed refs; verify the rendered table
      has one row per configured slot

## 3. Remove the second credential

- [x] 3.1 Delete the `OPENAI_API_KEY` line from `docker/docker-compose.yml`, leaving the `:?`
      explanatory comment intact for the remaining guarded variables; verify with
      `grep -c OPENAI_API_KEY docker/docker-compose.yml` returning 0
- [x] 3.2 Delete the OpenAI section from `docker/.env.example`; verify with
      `grep -c OPENAI_API_KEY docker/.env.example` returning 0
- [x] 3.3 Remove `OPENAI_API_KEY: ci-placeholder` from the `Validate compose file` step's `env:` in
      `.github/workflows/validate-config.yml`; verify `docker compose -f docker/docker-compose.yml config -q`
      still succeeds with only the remaining placeholder values exported, and fails if any still-guarded
      variable is unset
- [x] 3.4 Run `bash scripts/check-env-vars.sh` and verify it passes — it compares config, compose and
      `.env.example`, so it is the gate that proves the removal was complete rather than partial
- [x] 3.5 Replace the README sentence stating audio "still calls OpenAI directly, so `OPENAI_API_KEY`
      must stay set" with the single-credential statement, and check the "Models (OpenRouter)" opening
      sentence still reads correctly now that it covers audio too; verify with
      `grep -rn OPENAI_API_KEY README.md` returning nothing

## 4. Resolve the privacy-routing question

- [x] 4.1 Determine whether `models.providers.openrouter.params.provider`
      (`data_collection: "deny"`, `require_parameters: true`) reaches the STT request, by reading
      how `transcribeOpenRouterAudio` builds its body in the pinned package and checking whether
      the provider routing object is passed through; record the finding in design.md either way
- [x] 4.2 If the deny policy does not reach transcription requests, state that in the README audio
      note so the gap is documented rather than implied, and verify the note names what is and is not
      covered; if it does reach them, record that instead and make no README change

## 5. End-to-end verification

- [ ] 5.1 Build and deploy per the existing release flow, then send a Telegram voice note and verify
      the agent's reply shows it received the transcript rather than an unprocessed-attachment marker
- [ ] 5.2 Run `/status` in Telegram and verify the `📎 Media:` line reports audio OK against an
      OpenRouter model, confirming the configured entry ran rather than an auto-detected fallback
- [ ] 5.3 Verify the stack starts with `OPENAI_API_KEY` absent from the VPS environment entirely,
      confirming no remaining required-variable guard references it

## Workflow follow-up

- Archive the change once the deployed transcription has been verified, so the
  `model-routing-config` delta lands in the main spec.
- Note in the release notes that operators may delete `OPENAI_API_KEY` from `secrets/openclaw.env`
  and their local `docker/.env`; a leftover value is ignored rather than harmful.
