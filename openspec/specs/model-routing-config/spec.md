# model-routing-config Specification

## Purpose

Defines how the shipped OpenClaw configuration selects a model for each task through OpenRouter, so cost scales with task difficulty and only documented configuration keys are used.

## Requirements

### Requirement: OpenRouter as chat model provider
The system SHALL reference every chat, utility, vision and PDF model as `openrouter/<vendor>/<model>`, and SHALL read the OpenRouter credential from the `OPENROUTER_API_KEY` environment variable, never from a literal value in the config.

#### Scenario: Model refs
- **WHEN** `config/openclaw.json` is inspected
- **THEN** every model ref under `agents.defaults.model`, `utilityModel`, `imageModel` and `pdfModel` starts with `openrouter/`

#### Scenario: No literal credential
- **WHEN** the config validation script runs
- **THEN** it passes and the config contains no literal OpenRouter key

### Requirement: Low-cost default with cross-vendor fallbacks
The system SHALL use `openrouter/anthropic/claude-haiku-5.5` as the default primary model and SHALL list at least one fallback from a vendor other than Anthropic.

#### Scenario: Primary and fallback chain
- **WHEN** the default model request fails
- **THEN** the configured fallbacks are tried in order, starting with `openrouter/openai/gpt-6.1-terra`

### Requirement: Task-specific model slots
The system SHALL configure distinct models for short internal utility tasks, vision, PDF processing and image generation, each with at least one fallback.

#### Scenario: Utility tasks use the cheapest tier
- **WHEN** a session title or recap is generated
- **THEN** `utilityModel` is used, and its primary is priced at or below $0.15 per million input tokens

#### Scenario: PDF processing
- **WHEN** the `pdf` tool runs
- **THEN** it uses `pdfModel`, whose primary accepts file input

#### Scenario: Image generation
- **WHEN** an image is generated
- **THEN** the model comes from `agents.defaults.mediaModels.image` and its primary can output images

### Requirement: Manual escalation aliases
The system SHALL define `/model` aliases for a stronger model so a user can escalate a hard task without editing config.

#### Scenario: Escalate to Sonnet
- **WHEN** the allowed user sends `/model sonnet`
- **THEN** subsequent turns use `openrouter/anthropic/claude-sonnet-5.5`

### Requirement: Only documented configuration keys
The system SHALL NOT use `agents.defaults.imageGenerationModel`, `agents.defaults.heartbeat`, or OpenAI-specific `params.transport` entries for OpenRouter models.

#### Scenario: Deprecated keys absent
- **WHEN** `config/openclaw.json` is inspected
- **THEN** none of those keys are present

### Requirement: Heartbeat on a cheap model
The system SHALL run the periodic heartbeat as an automation job whose model is the cheapest-tier OpenRouter model, and the repository SHALL document the command that sets it.

#### Scenario: Heartbeat job model
- **WHEN** the operator follows the documented command after deployment
- **THEN** the heartbeat job runs with `openrouter/qwen/qwen3.7-flash`

### Requirement: Privacy-preserving OpenRouter routing
The system SHALL set OpenRouter provider routing defaults of `data_collection: "deny"` and `require_parameters: true`.

#### Scenario: Routing defaults
- **WHEN** `config/openclaw.json` is inspected
- **THEN** `models.providers.openrouter.params.provider` contains both settings
