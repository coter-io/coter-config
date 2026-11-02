# local-dev-stack Specification

## Purpose

Defines how a developer brings the shipped configuration up as a running gateway on their own machine — what a single command must do, how configuration and secrets reach the container, how local state stays inspectable, and how the local stack stays isolated from the deployed one.

## Requirements

### Requirement: One command brings the stack up
The system SHALL provide a single executable in the project root that brings the gateway up and follows its output, and SHALL perform that bring-up when invoked with no arguments.

#### Scenario: Fit environment
- **WHEN** a developer invokes the executable with no arguments in a checkout whose environment satisfies the preflight
- **THEN** the gateway container is running and its log output is streaming

#### Scenario: No further steps required
- **WHEN** the bring-up completes
- **THEN** no additional manual command is needed to make the gateway reachable

### Requirement: The shipped artifacts run unmodified
The system SHALL run `config/openclaw.json`, `docker/Dockerfile` and `docker/docker-compose.yml` as committed, and SHALL NOT require any edit to them for a local run to work.

#### Scenario: Config edited in the repository
- **WHEN** a developer edits `config/openclaw.json` and starts the stack
- **THEN** the gateway runs with the edited file as written, with no local-only variant of it

#### Scenario: Local run on a clean checkout
- **WHEN** the stack is started from a checkout with no uncommitted changes
- **THEN** it starts without requiring any shipped artifact to be modified first

### Requirement: Configuration reaches the container the way a deployment delivers it
The system SHALL place the repository's configuration files into a host directory the container mounts, refreshed on each bring-up, so that the repository's copy takes precedence over whatever the directory previously held.

#### Scenario: First bring-up
- **WHEN** the stack starts with no prior local state
- **THEN** the gateway reads the repository's `config/openclaw.json` rather than starting unconfigured

#### Scenario: Repository copy wins
- **WHEN** the configuration in the local directory differs from the repository's copy and the stack is restarted
- **THEN** the repository's copy replaces it

#### Scenario: Runtime state outside the configuration files
- **WHEN** the gateway has written session or credential state into its configuration directory and the stack is restarted
- **THEN** that state survives, because only the repository's configuration files are replaced

### Requirement: Local overrides cannot reach a deployment
The system SHALL keep every local-only compose setting in a file that is separate from `docker/docker-compose.yml` and applied only when explicitly requested, so no deployment can pick it up.

#### Scenario: Deployment path
- **WHEN** the deployment copies and starts `docker/docker-compose.yml`
- **THEN** no local-only setting is in effect

#### Scenario: Compose invoked without the local file
- **WHEN** compose is invoked against `docker/docker-compose.yml` alone
- **THEN** the local overrides are absent rather than applied automatically

### Requirement: One environment file at the project root
The system SHALL read every environment variable the local stack needs from a single `.env` file in the project root, and that file SHALL be excluded from version control.

#### Scenario: Value reaches the container
- **WHEN** a developer sets a variable in the root `.env`
- **THEN** the gateway container receives it under that same name

#### Scenario: Environment file absent
- **WHEN** the stack is started and no root `.env` exists
- **THEN** one is created from `docker/.env.example`, the developer is told to fill it in, and nothing is built or started

#### Scenario: Secrets stay untracked
- **WHEN** the repository's tracked files are listed
- **THEN** the root `.env` is not among them

### Requirement: Bring-up is gated on the environment file satisfying the documented contract
The system SHALL verify the root `.env` against the variables declared in `docker/.env.example` before building or starting anything, and SHALL refuse to proceed when a required variable is absent.

#### Scenario: Required variable missing
- **WHEN** the root `.env` omits a variable the deployment cannot function without
- **THEN** the bring-up stops and names that variable

#### Scenario: Variable present under an undeclared name
- **WHEN** the root `.env` sets a name that `docker/.env.example` does not declare
- **THEN** the bring-up reports that name as reaching nothing

### Requirement: Preflight fails closed and names the defect
The system SHALL report each unmet precondition with the defect and its remedy, and SHALL NOT build an image or start a container when any precondition is unmet.

#### Scenario: Container runtime unavailable
- **WHEN** the container runtime is not running
- **THEN** the bring-up stops, says so, and no build is attempted

#### Scenario: Nothing partially started
- **WHEN** a precondition fails
- **THEN** no container of the local stack is left running

### Requirement: Local state is inspectable on the host and excluded from version control
The system SHALL keep the gateway's configuration directory and workspace on the host filesystem where a developer can read them directly, SHALL exclude them from version control, and SHALL provide a way to discard them deliberately.

#### Scenario: Agent output is readable
- **WHEN** the agent writes a file into its workspace
- **THEN** that file is readable on the host without entering the container

#### Scenario: State stays untracked
- **WHEN** the repository's tracked files are listed after a local run
- **THEN** no local state file is among them

#### Scenario: Deliberate reset
- **WHEN** a developer asks to reset local state
- **THEN** the configuration directory and workspace are discarded and the next bring-up recreates them

### Requirement: Repeat starts do not redo completed setup
The system SHALL persist the workspace across restarts so that setup the container performs on startup is not repeated once complete.

#### Scenario: Second start
- **WHEN** the stack is restarted after a start that installed the manifest's skills
- **THEN** those skills are not installed again

### Requirement: The local stack is isolated from the deployed one
The system SHALL give the local stack its own gateway token, its own messaging channel credential and its own state, and SHALL NOT start the workspace git sync sidecar locally.

#### Scenario: Channel credential is surfaced
- **WHEN** the stack starts
- **THEN** the identity of the bot credential it is about to poll with is reported before polling begins, so a credential shared with the deployed stack is visible

#### Scenario: No local workspace push
- **WHEN** the local stack runs
- **THEN** no workspace is committed or pushed to any git remote

#### Scenario: Separate state
- **WHEN** the local stack runs alongside a deployed one
- **THEN** it uses its own state directory rather than sharing the deployed stack's

### Requirement: The locally built image is not a release artifact
The system SHALL build the local image for the developer's host architecture, and SHALL NOT authenticate to or push to a container registry as part of a local run.

#### Scenario: Native architecture
- **WHEN** the image is built on a developer machine
- **THEN** it is built for that machine's architecture and runs without emulation

#### Scenario: No publishing
- **WHEN** a local bring-up completes
- **THEN** no image has been pushed to a registry and no registry credential was required

### Requirement: Full static validation is available but off the bring-up path
The system SHALL expose the repository's existing configuration validation as its own command, and SHALL NOT run it as part of a bring-up, so the inner loop does not pay its cost.

#### Scenario: Bring-up
- **WHEN** the stack is brought up
- **THEN** the pinned-version schema and health validation does not run

#### Scenario: Validation requested
- **WHEN** a developer asks for validation
- **THEN** the repository's existing validation script runs rather than a reimplementation of it
