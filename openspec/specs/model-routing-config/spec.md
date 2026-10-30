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
The system SHALL configure distinct models for short internal utility tasks, vision, PDF processing and image generation. Each slot whose schema accepts a fallback list SHALL name at least one fallback. The utility slot accepts a single model ref in the pinned OpenClaw version and SHALL therefore name exactly one model with no fallback.

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

### Requirement: Manual escalation aliases
The system SHALL define `/model` aliases for a stronger model so a user can escalate a hard task without editing config, and SHALL include every aliased ref in the model override allowlist so the alias is selectable.

#### Scenario: Escalate to Sonnet
- **WHEN** the allowed user sends `/model sonnet`
- **THEN** subsequent turns use `openrouter/anthropic/claude-sonnet-5.5`

#### Scenario: Alias is allowed
- **WHEN** an alias is defined in `agents.defaults.models`
- **THEN** its ref also appears in `agents.defaults.modelPolicy.allow`

### Requirement: Explicit model override allowlist
The system SHALL state the set of model refs a user may switch to in `agents.defaults.modelPolicy.allow`, and SHALL NOT rely on the presence of `agents.defaults.models` to restrict overrides. `agents.defaults.models` SHALL carry aliases and per-model params only.

#### Scenario: Allowlist is stated, not implied
- **WHEN** `config/openclaw.json` is inspected
- **THEN** `agents.defaults.modelPolicy.allow` lists every ref a user may select
- **AND** removing an alias from `agents.defaults.models` does not change what a user may select

#### Scenario: Configured default stays selectable
- **WHEN** the gateway resolves the default model for a session
- **THEN** the primary from `agents.defaults.model` is used, and the allowlist does not cause a different model to be substituted

### Requirement: Config validates against the pinned OpenClaw version
The system SHALL keep `config/openclaw.json` loadable by the OpenClaw version pinned in `docker/Dockerfile`, and the config validation script SHALL verify this against that version's own schema rather than by inspecting for known-bad keys. Validation SHALL supply values for the config's `${ENV_VAR}` placeholders through the environment and validate the shipped file unmodified, and SHALL also report drift that the pinned version accepts without a hard schema error.

#### Scenario: Legacy key shape fails validation
- **WHEN** the config uses a key shape the pinned version reports as legacy or invalid
- **THEN** the validation script fails and names the key and its canonical replacement
- **AND** the **Publish image** workflow fails before building, because it runs that script

#### Scenario: Canonical config passes
- **WHEN** the config uses only shapes the pinned version accepts
- **THEN** the validation script passes

#### Scenario: Environment placeholders are not credentials
- **WHEN** the config references secrets and identifiers as `${ENV_VAR}` placeholders
- **THEN** validation supplies a well-formed value for each placeholder through the environment
- **AND** validation passes without any placeholder being treated as a literal credential or as a malformed field value

#### Scenario: The shipped config is validated as written
- **WHEN** validation runs
- **THEN** the file validated is `config/openclaw.json` itself, unmodified
- **AND** validation never rewrites, substitutes into, or leaves a derived copy of that file

#### Scenario: Tolerated drift is still caught
- **WHEN** the config uses a shape the pinned version accepts without a hard schema error but reports as a health finding at warning severity or above
- **THEN** validation fails and names the finding and its remedy

#### Scenario: Findings that describe the validating environment do not fail validation
- **WHEN** a health finding describes the environment validation runs in rather than the config — such as an unreachable MCP endpoint, absent runtime scheduling state, or a bind address supplied at container start
- **THEN** validation does not fail on that finding
- **AND** each such exclusion is stated explicitly rather than inferred from severity alone

#### Scenario: Pinned version is the reference
- **WHEN** the version pinned in `docker/Dockerfile` differs from any OpenClaw installed on the machine running validation
- **THEN** validation is performed against the pinned version
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
