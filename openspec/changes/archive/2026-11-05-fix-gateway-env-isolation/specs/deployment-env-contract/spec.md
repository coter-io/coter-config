# Spec Delta

## ADDED Requirements

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
