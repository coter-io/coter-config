# agent-workspace-provisioning Specification

## Purpose

Defines how the agent's workspace files and identity are predefined in this repository and delivered into the gateway's workspace, so that a first start requires no interaction from the user, generates no avatar, and asks no setup question.

## Requirements

### Requirement: A first start asks the user nothing
The system SHALL reach a state in which the gateway's first conversation with a user contains no setup or onboarding question, so that the user's first message is answered as ordinary work.

#### Scenario: First message on a fresh workspace
- **WHEN** the gateway starts with no prior workspace state and the user sends their first message
- **THEN** the agent answers that message and asks nothing about its name, personality, avatar, or which plugins to install

#### Scenario: No onboarding instructions reach the agent
- **WHEN** the workspace is inspected after a first start
- **THEN** it holds no onboarding instruction file for the agent to follow, and none appears on any later start

### Requirement: No avatar is generated
The system SHALL supply the agent's avatar as a predefined image committed to the repository, and SHALL NOT cause image generation for avatar purposes at any point.

#### Scenario: Image generation is available but unused
- **WHEN** the configured image model is capable of generating images and the gateway starts on a fresh workspace
- **THEN** no image is generated for the avatar and the user is never shown avatar options to choose between

#### Scenario: Avatar is in effect immediately
- **WHEN** the agent's identity is displayed on a channel after a first start
- **THEN** the predefined avatar is already in effect without the user having selected one

### Requirement: The agent's workspace files are predefined in the repository
The system SHALL commit the workspace files the agent requires — its workspace conventions, its personality, its identity, and its user model — and SHALL deliver them into the gateway's workspace without the agent or the gateway authoring them.

#### Scenario: Fresh workspace receives the predefined files
- **WHEN** the gateway starts with an empty workspace
- **THEN** each predefined workspace file is present in the workspace with the repository's content

#### Scenario: Agent reads its own identity
- **WHEN** the agent reads who it is
- **THEN** it finds the repository's predefined identity rather than a starter template awaiting completion

### Requirement: Predefined files state real values rather than placeholders
The system SHALL ensure every delivered workspace file states real values, and SHALL NOT ship a placeholder that the gateway would treat as unset or that the agent would read as a live instruction.

#### Scenario: Identity holds no unset value
- **WHEN** the agent's identity is resolved from the delivered files
- **THEN** no identity field holds a value the gateway treats as not yet chosen

#### Scenario: User model holds no placeholder directive
- **WHEN** the delivered user model file is read
- **THEN** it contains no example or placeholder directive presented as active guidance

### Requirement: The gateway creates no workspace bootstrap file
The system SHALL configure the gateway so that it does not create workspace bootstrap files, so no onboarding ritual file can be introduced on any start. Injection of workspace files the workspace already holds SHALL be unaffected.

#### Scenario: A predefined file is absent
- **WHEN** a start finds one of the predefined workspace files missing from the workspace
- **THEN** the gateway does not substitute a starter template of its own, and the repository's validation is what guarantees the file was there

#### Scenario: Existing files still reach the agent
- **WHEN** the gateway prepares a session and the workspace holds the predefined files
- **THEN** their contents are still provided to the agent as session context

### Requirement: Delivery preserves what the workspace already holds
The system SHALL deliver predefined workspace files without overwriting a file the workspace already contains, so that content the agent or an operator has written survives every restart.

#### Scenario: Agent has evolved a delivered file
- **WHEN** the agent has changed one of the delivered files and the stack is restarted
- **THEN** the agent's version survives rather than being replaced by the repository's copy

#### Scenario: Deliberate reset
- **WHEN** local state is discarded and the stack is started again
- **THEN** the repository's predefined content is delivered afresh and the first start again asks nothing

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

### Requirement: Identity is never written back into the shipped configuration
The system SHALL NOT require the gateway or the agent to write identity into the configuration file the repository ships, so that a bring-up which replaces that file cannot discard a value the user relies on.

#### Scenario: Restart after a bring-up replaces the configuration
- **WHEN** the stack is restarted and the repository's configuration replaces the copy in the gateway's configuration directory
- **THEN** no identity value is lost, because the repository's copy already states the canonical identity

#### Scenario: Agent asked to change its own identity
- **WHEN** a user asks the agent to change its displayed identity at runtime
- **THEN** the change is understood to be transient unless it is made in the repository, and the operator is pointed at the repository as the authoring point

### Requirement: A fail-closed gate protects the zero-interaction guarantee
The system SHALL verify with a repository script that the shipped configuration disables workspace bootstrap creation and that every predefined workspace file and the avatar are present, and SHALL refuse to pass when any of them is missing.

#### Scenario: Predefined file removed
- **WHEN** one of the predefined workspace files is deleted and validation runs
- **THEN** validation fails and names the missing file

#### Scenario: Bootstrap creation re-enabled
- **WHEN** the shipped configuration no longer disables workspace bootstrap creation and validation runs
- **THEN** validation fails and reports that the onboarding ritual would return

#### Scenario: The same checks run at every gate
- **WHEN** validation runs in the pre-commit hook, in the pull request gate, or in the release gate
- **THEN** the same checks apply, so no path can publish an image whose first start asks questions

### Requirement: A version bump surfaces drift from the upstream starter templates
The system SHALL report, when the pinned OpenClaw version is raised, where the predefined workspace files differ from that version's starter templates, so that upstream changes are reviewed deliberately rather than missed.

#### Scenario: An upstream starter template changed
- **WHEN** the pinned version is raised and a starter template the predefined files derive from has changed
- **THEN** the forward-compatibility check reports that file as drifted and the bump is not silently accepted

#### Scenario: Upstream introduces a new workspace file
- **WHEN** the new version expects a workspace file the repository does not predefine
- **THEN** the check reports that file as unprovided

### Requirement: Releasing a change to the predefined files requires a deliberate delivery step
The system SHALL document that seeding alone does not update a predefined workspace file that already exists, and SHALL state the operator step that makes a changed file take effect on a deployment, so that a released change to identity or operating guidance cannot be silently absent from the running agent.

#### Scenario: Operating guidance is changed and released
- **WHEN** the repository's predefined operating guidance changes and the deployment is updated
- **THEN** the documented procedure names the step that replaces the existing workspace copy, rather than implying the restart is sufficient

#### Scenario: Stale copy is indistinguishable at runtime
- **WHEN** a workspace holds an older copy of a predefined file after an update
- **THEN** the documentation states that no repository gate detects this, because validation compares the repository's own authoring points and never inspects a deployed workspace
