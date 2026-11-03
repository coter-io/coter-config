# Spec Delta

## MODIFIED Requirements

### Requirement: Displayed identity and the agent's own identity agree
The system SHALL declare one canonical identity in the shipped configuration, and the delivered workspace identity file SHALL state the same name, emoji, personality line, and avatar, so that channels and the agent never disagree about who the agent is. The agreement SHALL hold on a running deployment, including one whose workspace already holds an identity file from an earlier version.

#### Scenario: Identity shown on a channel
- **WHEN** the agent's identity is displayed to a user
- **THEN** the name, emoji, and avatar shown match those in the delivered workspace identity file

#### Scenario: Identity changed by a maintainer
- **WHEN** a maintainer changes the agent's identity in the repository
- **THEN** the shipped configuration and the predefined identity file are changed together, and no third location holds a competing value

#### Scenario: Identity changed on a deployment that already has a workspace
- **WHEN** an identity change is released to a deployment whose workspace already holds the previous identity file
- **THEN** the change is not treated as delivered until that workspace states the new identity, because the configuration is replaced on bring-up while no-clobber seeding leaves the existing file untouched

## ADDED Requirements

### Requirement: Releasing a change to the predefined files requires a deliberate delivery step
The system SHALL document that seeding alone does not update a predefined workspace file that already exists, and SHALL state the operator step that makes a changed file take effect on a deployment, so that a released change to identity or operating guidance cannot be silently absent from the running agent.

#### Scenario: Operating guidance is changed and released
- **WHEN** the repository's predefined operating guidance changes and the deployment is updated
- **THEN** the documented procedure names the step that replaces the existing workspace copy, rather than implying the restart is sufficient

#### Scenario: Stale copy is indistinguishable at runtime
- **WHEN** a workspace holds an older copy of a predefined file after an update
- **THEN** the documentation states that no repository gate detects this, because validation compares the repository's own authoring points and never inspects a deployed workspace
