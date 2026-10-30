# Design

## Context

See proposal.md — Why. The facts the approach rests on, all verified against the pinned
`openclaw@2026.10.7` from `docker/Dockerfile` rather than the live docs site, since docs track the
current release and the gateway runs the pin:

- **OpenRouter is a registered audio media-understanding provider.**
  `dist/extensions/openrouter/openclaw.plugin.json` declares
  `mediaUnderstandingProviderMetadata.openrouter.capabilities: ["image", "audio"]`,
  `defaultModels.audio: "openai/whisper-large-v3-turbo"`, and `autoPriority.audio: 35`.
- **The STT path is implemented, not inferred.**
  `dist/media-understanding-provider-BaQMiawT.mjs` defines `transcribeOpenRouterAudio()`, which
  POSTs to `{baseUrl}/audio/transcriptions` with a JSON body
  `{ model, input_audio: { data: <base64>, format }, language?, temperature? }` — not a multipart
  OpenAI-style form upload. `DEFAULT_OPENROUTER_AUDIO_TRANSCRIPTION_MODEL` is
  `openai/whisper-large-v3-turbo`.
- **Telegram's audio format is accepted.** Voice notes arrive as OGG/Opus; the provider's
  `AUDIO_FORMAT_BY_MIME` map sends `audio/ogg` and `audio/opus` as format `ogg`. An unmappable
  MIME type throws before upload, so the next entry is tried.
- **The config shape passes the pinned schema.** `scripts/validate-config.sh` was run against a
  scratch copy carrying the OpenRouter audio entry and reported `Config valid` plus clean health
  findings.
- **`gpt-4o-transcribe-mini` does not exist.** The pinned package references only
  `gpt-4o-transcribe` (17 times) and `gpt-4o-mini-transcribe` (10 times);
  `openrouter.ai/api/v1/models/openai/gpt-4o-transcribe-mini/endpoints` returns 404.
- **`OPENAI_API_KEY` has exactly one consumer.** Grepping the repo shows it only in the audio
  context: compose, `.env.example`, the CI placeholder env, and the README sentence describing it.

Constraint from the existing repo: `scripts/check-env-vars.sh` enforces a three-way match between
`config/openclaw.json`, `docker/docker-compose.yml` and `docker/.env.example`. Removing a variable
from only some of them fails the gate, so the removal is atomic across all three plus the CI
workflow's placeholder env — which compose interpolation needs while the `:?` guard exists and
must not outlive it.

## Goals / Non-Goals

**Goals:**

- One credential for every model call, audio included.
- Audio keeps the per-capability fallback the other model slots have, without a second credential.
- The change is verifiable by the gates the repo already ships, not by inspection.

**Non-Goals:**

- Choosing a transcription model on quality grounds. No OpenClaw doc ranks audio providers, and no
  measurement is available here; selection is on cost and on being the provider's own default.
- A local CLI fallback. It would need a transcription binary in `docker/Dockerfile`, which is an
  image-build change with its own size and build-time trade-offs.
- Changing `tts.*`, or the image/video/music generation slots.

## Decisions

**Model ids are bare upstream slugs, not `openrouter/`-prefixed refs.** The entry carries
`provider: "openrouter"` as a separate field, so the `model` value is `openai/whisper-large-v3-turbo`.
This differs from everything under `agents.defaults`, where the ref is
`openrouter/<vendor>/<model>`. Prefixing here would produce
`openrouter/openai/whisper-large-v3-turbo` as the upstream slug and 404. Worth a comment in the
README table, because the inconsistency is a trap for the next person editing this block.

**`openai/whisper-large-v3-turbo` primary.** It is the provider's own declared default, and the
cheapest route: DeepInfra at $0.0000033/sec, about $0.012 per audio hour, versus Groq at
$0.040/hour for the same model. Alternatives: `openai/whisper-large-v3` (~$0.027/hr, slower, no
accuracy evidence to justify it here) and `deepgram/nova-3` (~$0.258/hour, 20x the primary).

A caveat on those numbers: the per-second reading is inferred, not documented. Groq's row
(`$0.0000111`) matches their published $0.04/hour exactly, and `completion: 0` only makes sense for
duration billing. The `gpt-4o-*` rows have a nonzero completion price and bill per token.

**`openai/gpt-4o-mini-transcribe` fallback, also via OpenRouter.** A different vendor and a
different endpoint behind OpenRouter, so it covers a DeepInfra/Groq outage — while still using the
one credential. Alternative considered: no fallback, which is what the docs example shows; rejected
because `model-routing-config` already requires a fallback per slot elsewhere, and the current
single-entry config is precisely why a bad model id silently produced no transcript. Its token
billing ($1.25/M in, $5/M out) is a non-issue for a fallback path.

**`audio.enabled: true` stated explicitly.** With models configured it is already active — the
default is "auto", and only `false` disables. Stating it costs nothing and makes the config say
what it does, which is the spec scenario.

**The delta modifies `Task-specific model slots` rather than `OpenRouter as chat model
provider`.** The latter's text ("every chat, utility, vision and PDF model") is accurate for the
slots it names, and extending it would require either a misleading header or a combined
RENAMED+MODIFIED on one requirement — a shape that risks losing content at archive time. Audio's
slot behavior belongs in the slots requirement; the single-credential property is new, so it is
ADDED. See proposal.md — Capabilities for why `deployment-env-contract` takes no delta.

**No delta for the `data_collection: "deny"` routing policy.** `models.providers.openrouter.params.provider`
is documented for chat-completions routes, and `transcribeOpenRouterAudio()` builds its own JSON
body with no sign of that object being forwarded. Rather than specify behavior that may not exist,
the change carried a task to determine it and record the finding.

**Resolved (task 4.1): the deny policy does NOT reach transcription requests, and no config path
applies it.** Determined by reading the pinned package, not by inference:

- `transcribeOpenRouterAudio()` reads only `params.model`, `mime`, `fileName`, `fetchFn`, `baseUrl`,
  `headers`, `request`, `apiKey`, `query`, `buffer`, `language`, `timeoutMs`, `signal`. It never
  reads a provider-routing object, and the body it sends is exactly
  `{ model, input_audio, language?, temperature? }`.
- The per-entry extension points cannot carry one either. `providerOptions` is
  `Record<string, Record<string, string | number | boolean>>` — scalars only, so the nested
  `provider: { data_collection: "deny" }` object is not expressible. `headers` is
  `Record<string, string>`. `request` resolves through `resolveProviderHttpRequestConfig`, which
  returns only `baseUrl`, `headers`, `allowPrivateNetwork` and a dispatcher policy — transport, no
  body.

So inbound voice audio is sent without the `data_collection: "deny"` preference that every chat
request carries, and in the pinned version that cannot be changed by configuration. This is a
documentation obligation (task 4.2), not a blocker: it is the status quo for audio rather than a
regression — the previous OpenAI path carried no such preference either. Closing it would mean an
upstream change or pinning the route with `provider.only`, which is a separate change.

## Risks / Trade-offs

- [No live transcription has been performed — ids and route are confirmed from shipped code and the
  live catalog, but not end-to-end with a real key] → a task does a one-shot `openclaw infer` style
  check against the deployed gateway before the README claim is finalized; `/status` reports the
  resolved audio model on its `📎 Media:` line.
- [Voice audio does **not** inherit `data_collection: "deny"`, so a recording reaches the upstream
  transcription provider without that preference — confirmed, see Decisions] → documented in the
  README rather than silently accepted. No configuration mitigates it in the pinned version; a
  follow-up change would be needed to pin or restrict the route.
- [DeepInfra is a single upstream for the primary; `provider.require_parameters: true` may narrow
  routing further] → the `gpt-4o-mini-transcribe` fallback is a different vendor and endpoint.
- [Dropping the `:?` guard means a future audio misconfiguration fails at transcription time rather
  than at boot] → accepted: the guard was protecting a credential nothing will read. The real
  protection is the spec scenario asserting configured ids resolve in the catalog.
- [Model ids and prices drift, as the previous OpenRouter change already recorded] → re-check the
  ids at implementation time; the ids are the part that breaks loudly, and the spec scenario makes
  that checkable.
- [An operator's existing `.env` keeps a now-unused `OPENAI_API_KEY`] → harmless, it is simply
  ignored; the release notes mention it can be deleted.

## Migration Plan

1. Land the config, compose, `.env.example`, workflow and README changes together — `check-env-vars.sh`
   fails on a partial removal, which is the intended behaviour.
2. Publish the image per the existing release flow (`ghcr-image-publish`).
3. On the VPS, `make push-config` then redeploy. `OPENROUTER_API_KEY` is already present from the
   earlier change, so no new secret is provisioned; `secrets/openclaw.env` may drop `OPENAI_API_KEY`.
4. Verify with a real Telegram voice note, and with `/status` showing an OpenRouter model on the
   media line.

Rollback: revert the commit and redeploy. The previous state transcribed nothing anyway, so the
rollback target is a known-broken audio path — worth noting, because "roll back if audio misbehaves"
is not a safe instinct here. If the new path fails, fix forward by swapping the primary model id.

## Open Questions

- Which upstream endpoint OpenRouter selects for `openai/whisper-large-v3-turbo` under
  `require_parameters: true` (DeepInfra and Groq both serve it). Deferrable: it affects cost per
  hour, not whether the slot works, and neither the specs nor the task breakdown depend on it.
