# Spec Delta

## MODIFIED Requirements

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
