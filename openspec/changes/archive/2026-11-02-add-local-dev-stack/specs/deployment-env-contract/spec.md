# Spec Delta

## ADDED Requirements

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

## MODIFIED Requirements

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
