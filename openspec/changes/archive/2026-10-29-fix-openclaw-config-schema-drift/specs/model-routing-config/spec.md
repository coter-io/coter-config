# Spec Delta

## ADDED Requirements

### Requirement: Config validates against the pinned OpenClaw version
The system SHALL keep `config/openclaw.json` loadable by the OpenClaw version pinned in `docker/Dockerfile`, and the config validation script SHALL verify this against that version's own schema rather than by inspecting for known-bad keys.

#### Scenario: Legacy key shape fails validation
- **WHEN** the config uses a key shape the pinned version reports as legacy or invalid
- **THEN** the validation script fails and names the key and its canonical replacement
- **AND** the **Publish image** workflow fails before building, because it runs that script

#### Scenario: Canonical config passes
- **WHEN** the config uses only shapes the pinned version accepts
- **THEN** the validation script passes

#### Scenario: Environment placeholders are not credentials
- **WHEN** the config references secrets as `${ENV_VAR}` placeholders that are unset in the validating environment
- **THEN** validation still passes, because unresolved placeholders are not a schema error

#### Scenario: Pinned version is the reference
- **WHEN** the version pinned in `docker/Dockerfile` differs from any OpenClaw installed on the machine running validation
- **THEN** validation is performed against the pinned version

### Requirement: Explicit model override allowlist
The system SHALL state the set of model refs a user may switch to in `agents.defaults.modelPolicy.allow`, and SHALL NOT rely on the presence of `agents.defaults.models` to restrict overrides. `agents.defaults.models` SHALL carry aliases and per-model params only.

#### Scenario: Allowlist is stated, not implied
- **WHEN** `config/openclaw.json` is inspected
- **THEN** `agents.defaults.modelPolicy.allow` lists every ref a user may select
- **AND** removing an alias from `agents.defaults.models` does not change what a user may select

#### Scenario: Configured default stays selectable
- **WHEN** the gateway resolves the default model for a session
- **THEN** the primary from `agents.defaults.model` is used, and the allowlist does not cause a different model to be substituted

## MODIFIED Requirements

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

## REMOVED Requirements

### Requirement: Only documented configuration keys
**Reason**: The requirement named three specific keys retired in an earlier release (`agents.defaults.imageGenerationModel`, `agents.defaults.heartbeat`, OpenAI-specific `params.transport`). A fixed list of past mistakes cannot detect the next rename, and did not detect the `agents.list`, `tools.media.audio.models`, `logging.redactSensitive` and `agents.defaults.models` moves that broke gateway startup.

**Migration**: Replaced by *Config validates against the pinned OpenClaw version*, which delegates the judgment of what is documented to the pinned version's own schema. The three keys named here remain absent from the config and are still rejected, now by that validation rather than by inspection.
