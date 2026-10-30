# Spec Delta

## ADDED Requirements

### Requirement: Inbound voice notes are transcribed
The system SHALL transcribe an inbound voice or audio attachment and deliver the transcript to the reply pipeline, so a voice note reaches the agent as text rather than as a failure marker. Each configured audio entry SHALL name a model id the routing provider actually serves.

#### Scenario: Voice note transcribed
- **WHEN** the allowed user sends a Telegram voice note
- **THEN** the message body the agent receives contains the transcript of that audio

#### Scenario: Configured audio model ids are real
- **WHEN** every `model` value in a `tools.media.models` entry tagged `capabilities: ["audio"]` is looked up in the routing provider's catalog
- **THEN** each one resolves to an existing model

#### Scenario: Primary audio model unavailable
- **WHEN** the first audio entry fails or is skipped
- **THEN** the next audio entry is tried before the attachment is reported as unprocessed

### Requirement: OpenRouter is the only model-provider credential
The system SHALL route every model call, including audio transcription, through OpenRouter, and SHALL NOT require a credential for any other model vendor. A vendor-specific key SHALL NOT be referenced by `config/openclaw.json`, `docker/docker-compose.yml`, or `docker/.env.example`.

#### Scenario: No second model credential is referenced
- **WHEN** `config/openclaw.json`, `docker/docker-compose.yml`, and `docker/.env.example` are inspected
- **THEN** `OPENROUTER_API_KEY` is the only model-provider credential any of them references

#### Scenario: Stack starts with one model credential
- **WHEN** an operator starts the stack having set `OPENROUTER_API_KEY` and no other model-vendor key
- **THEN** compose does not report a missing required variable for a model credential

#### Scenario: Vendor model reached through OpenRouter
- **WHEN** an entry names a model served by a vendor other than OpenRouter, such as an OpenAI transcription model
- **THEN** it is reached as an OpenRouter-routed model and authenticated with the OpenRouter credential

## MODIFIED Requirements

### Requirement: Task-specific model slots
The system SHALL configure distinct models for short internal utility tasks, vision, PDF processing, image generation and audio transcription. Each slot whose schema accepts a fallback list SHALL name at least one fallback. The utility slot accepts a single model ref in the pinned OpenClaw version and SHALL therefore name exactly one model with no fallback.

#### Scenario: Utility tasks use the cheapest tier
- **WHEN** a session title or recap is generated
- **THEN** `utilityModel` is used, and the model it names is priced at or below $0.15 per million input tokens

#### Scenario: Utility slot takes a single ref
- **WHEN** `config/openclaw.json` is inspected
- **THEN** `agents.defaults.utilityModel` is a model ref string, not an object with a fallback list

#### Scenario: PDF processing
- **WHEN** the `pdf` tool runs
- **THEN** it uses `pdfModel`, whose primary accepts file input

#### Scenario: Image generation
- **WHEN** an image is generated
- **THEN** the model comes from `agents.defaults.mediaModels.image` and its primary can output images

#### Scenario: Audio transcription
- **WHEN** an inbound audio attachment is transcribed
- **THEN** the model comes from a `tools.media.models` entry tagged `capabilities: ["audio"]`, and at least one further audio-tagged entry is configured as a fallback

#### Scenario: Audio understanding is enabled explicitly
- **WHEN** `config/openclaw.json` is inspected
- **THEN** `tools.media.audio.enabled` is set rather than left to the default-when-unset behaviour
