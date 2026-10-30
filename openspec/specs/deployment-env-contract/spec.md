# deployment-env-contract Specification

## Purpose

Defines the contract between the environment variables the shipped configuration and compose file consume and the variables documented in `docker/.env.example`, so an operator who fills in the documented file gets a working deployment with no silently empty credential.

## Requirements

### Requirement: Every referenced variable is documented
The system SHALL declare in `docker/.env.example` every environment variable referenced by `config/openclaw.json` or `docker/docker-compose.yml`, so the documented file is a complete description of what an operator must supply.

#### Scenario: Variable referenced by the config
- **WHEN** `config/openclaw.json` references a variable as `${VAR}`
- **THEN** `docker/.env.example` declares `VAR`

#### Scenario: Variable referenced by compose
- **WHEN** `docker/docker-compose.yml` interpolates a variable
- **THEN** `docker/.env.example` declares that variable

#### Scenario: New variable introduced
- **WHEN** a change introduces a reference to a variable that is not declared
- **THEN** validation fails and names the undeclared variable

### Requirement: Variable names match across files
The system SHALL use one name per credential across `config/openclaw.json`, `docker/docker-compose.yml`, and `docker/.env.example`, so a value an operator supplies under the documented name reaches the container.

#### Scenario: Documented name reaches the container
- **WHEN** an operator sets a variable in `.env` under the name `docker/.env.example` declares
- **THEN** the compose file passes that same name into the container environment

#### Scenario: Near-miss name
- **WHEN** the documented name and the name compose interpolates differ in any way
- **THEN** validation fails and names both spellings

### Requirement: Required variables are distinguishable from optional ones
The system SHALL interpolate a variable in `docker/docker-compose.yml` without a default only when the deployment cannot function without it, and SHALL supply a default for variables whose absence is tolerable.

#### Scenario: Required variable left unset
- **WHEN** an operator starts the stack without setting a variable that is interpolated with no default
- **THEN** compose reports the missing variable rather than starting with an empty value

#### Scenario: Optional variable left unset
- **WHEN** an operator starts the stack without setting a variable that has a default
- **THEN** the stack starts and the dependent feature is inactive rather than misconfigured

### Requirement: Documented variables carry provisioning guidance
The system SHALL accompany each declared variable in `docker/.env.example` with the source an operator uses to obtain its value, so no variable is documented as a bare name.

#### Scenario: Credential variable
- **WHEN** a declared variable holds a credential for a third-party service
- **THEN** `docker/.env.example` names where that credential is issued

#### Scenario: Identifier variable
- **WHEN** a declared variable holds an operator-specific identifier rather than a credential
- **THEN** `docker/.env.example` states what the identifier refers to and how to find it

### Requirement: The contract is enforced automatically
The system SHALL verify this contract with a repository script rather than by inspection, and that script SHALL run in the pull request gate, the pre-commit hook, and before a release build.

#### Scenario: Drift introduced in a pull request
- **WHEN** a pull request adds a variable reference without documenting it
- **THEN** the pull request gate fails before the change can merge

#### Scenario: Contract satisfied
- **WHEN** every referenced variable is declared under a matching name
- **THEN** the check passes
