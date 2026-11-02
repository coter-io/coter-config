# deployment-env-contract Specification

## Purpose

Defines the contract between the environment variables the shipped configuration and compose file consume and the variables documented in `docker/.env.example`, so an operator who fills in the documented file gets a working deployment with no silently empty credential.

## Requirements

### Requirement: Every referenced variable is documented
The system SHALL declare in `docker/.env.example` every environment variable referenced by `config/openclaw.json` or by the deployment compose file `docker/docker-compose.yml`, so the documented file is a complete description of what an operator must supply. A compose file used only for local development is outside this contract.

#### Scenario: Variable referenced by the config
- **WHEN** `config/openclaw.json` references a variable as `${VAR}`
- **THEN** `docker/.env.example` declares `VAR`

#### Scenario: Variable referenced by compose
- **WHEN** `docker/docker-compose.yml` interpolates a variable
- **THEN** `docker/.env.example` declares that variable

#### Scenario: New variable introduced
- **WHEN** a change introduces a reference to a variable that is not declared
- **THEN** validation fails and names the undeclared variable

#### Scenario: Variable referenced only by a local development compose file
- **WHEN** a compose file that no deployment consumes interpolates a variable
- **THEN** that variable is outside this contract and its absence from `docker/.env.example` is not a failure

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

### Requirement: A filled-in environment file is verified against the contract
The system SHALL provide a check that compares the variables set in an operator's or developer's environment file against the names declared in `docker/.env.example`, so a value supplied under a name nothing consumes is reported rather than silently reaching nothing.

#### Scenario: Required variable absent from the environment file
- **WHEN** the environment file omits a variable that is interpolated without a default
- **THEN** the check fails and names that variable

#### Scenario: Value set under an undeclared name
- **WHEN** the environment file sets a name that `docker/.env.example` does not declare
- **THEN** the check reports that name as consumed by nothing

#### Scenario: Environment file satisfies the contract
- **WHEN** every variable declared as required is set and no undeclared name is present
- **THEN** the check passes
