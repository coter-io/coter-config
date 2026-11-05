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

### Requirement: The container receives a declared set of variables
The system SHALL pass into the gateway container only variables the deployment compose file names, and SHALL NOT pass the operator's environment file into the container wholesale, so a value the environment file holds for the host reaches the container only when the compose file says it should.

#### Scenario: Environment file holds a host-only value
- **WHEN** the operator's environment file sets a variable the deployment compose file consumes for a bind-mount source or an image reference
- **THEN** that variable is absent from the container's environment

#### Scenario: Environment file holds an undeclared name
- **WHEN** the operator's environment file sets a name `docker/.env.example` does not declare
- **THEN** that name does not reach the container

#### Scenario: Declared variable reaches the container
- **WHEN** the deployment compose file names a variable in the gateway service's environment
- **THEN** the container receives it with the value the environment file supplies

### Requirement: The gateway's writable directories resolve inside the container
The system SHALL give the gateway configuration and workspace directory values that name paths inside the container, equal to the mount targets the deployment compose file declares, so every state write lands in a mounted directory the container's user owns.

#### Scenario: Directory value names a host path
- **WHEN** a variable the gateway reads as its configuration or workspace directory holds a path that exists only on the host
- **THEN** the deployment compose file overrides it with the corresponding in-container mount target

#### Scenario: Message dispatch writes state
- **WHEN** the gateway handles an inbound message and writes session state
- **THEN** the write resolves under a declared mount target rather than an unwritable path, and the message is answered rather than dead-lettered

#### Scenario: Mount target changed
- **WHEN** the deployment compose file changes where a volume is mounted in the container
- **THEN** the directory values the gateway receives name the new target

### Requirement: Every variable the configuration references is passed explicitly
The system SHALL name in the deployment compose file's gateway environment every variable `config/openclaw.json` references as `${VAR}`, so no referenced value depends on a variable arriving by any route other than that file.

#### Scenario: Config references a variable the compose file does not name
- **WHEN** `config/openclaw.json` references a variable that the deployment compose file's gateway environment does not name
- **THEN** validation fails and names that variable

#### Scenario: New reference added to the config
- **WHEN** a change adds a `${VAR}` reference to `config/openclaw.json`
- **THEN** validation fails until the deployment compose file names that variable

#### Scenario: Every reference named
- **WHEN** the deployment compose file names every variable the config references
- **THEN** the check passes

### Requirement: Host-side variables are documented as host-side
The system SHALL state in `docker/.env.example`, for each declared variable whose value describes the host rather than the container, that compose consumes it on the host, so an operator cannot read a host path as a value the gateway will use.

#### Scenario: Declared variable names a bind-mount source
- **WHEN** a declared variable's value is a path compose uses as a bind-mount source
- **THEN** `docker/.env.example` states that the value describes the host filesystem

#### Scenario: Declared variable is consumed by the container
- **WHEN** a declared variable's value is passed into the container
- **THEN** `docker/.env.example` does not describe it as host-side
