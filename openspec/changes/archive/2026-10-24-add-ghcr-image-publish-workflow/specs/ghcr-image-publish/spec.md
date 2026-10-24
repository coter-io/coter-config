# Spec Delta

## Purpose

Defines how the project's Docker images are published to GitHub Container Registry from a manually selected Git tag, so released versions can be built reproducibly without a developer laptop.

## ADDED Requirements

### Requirement: Manual tag-based trigger
The system SHALL provide a workflow that runs only on manual dispatch, and SHALL build from the Git ref chosen in the dispatch ref picker.

#### Scenario: Dispatch from a tag
- **WHEN** a maintainer dispatches the workflow with a tag selected as the ref
- **THEN** the workflow checks out that tag and builds from its contents

#### Scenario: No automatic trigger
- **WHEN** a commit or tag is pushed
- **THEN** the workflow does not run

### Requirement: Reject non-tag refs
The system SHALL fail before building or pushing anything when the selected ref is not a Git tag.

#### Scenario: Dispatch from a branch
- **WHEN** a maintainer dispatches the workflow with a branch selected as the ref
- **THEN** the run fails with a message instructing the maintainer to select a tag
- **AND** no image is built or pushed

### Requirement: Pre-build validation
The system SHALL run the project's config validation and secret scan against the checked-out tag before building, and SHALL NOT push images if either fails.

#### Scenario: Validation failure
- **WHEN** config validation or the secret scan fails on the selected tag
- **THEN** the run fails
- **AND** no image is pushed

### Requirement: Published images
The system SHALL build and push both the gateway image and the workspace-sync image for `linux/amd64`, using the same Dockerfiles and build contexts as the local build script, to `ghcr.io/<repository owner>/openclaw-docker-config/<image name>`.

#### Scenario: Successful publish
- **WHEN** validation passes for the selected tag
- **THEN** `openclaw-gateway` and `workspace-sync` are each pushed to GHCR under the repository owner's namespace

#### Scenario: One image fails to build
- **WHEN** either image fails to build
- **THEN** the run fails and the failing image is not pushed

### Requirement: Image tagging
The system SHALL tag each pushed image with the selected Git tag name and the short commit SHA of that tag.

#### Scenario: Tags applied
- **WHEN** the workflow publishes from tag `v1.0.1`
- **THEN** each image is available as `:v1.0.1` and `:<short sha>`

### Requirement: Opt-in latest tag
The system SHALL move the `latest` tag only when the maintainer explicitly enables a dispatch option, which SHALL default to disabled.

#### Scenario: Default dispatch
- **WHEN** the workflow is dispatched without enabling the latest option
- **THEN** `latest` is not created or moved on either image

#### Scenario: Latest enabled
- **WHEN** the workflow is dispatched with the latest option enabled
- **THEN** `latest` is also pushed for both images

### Requirement: Built-in authentication
The system SHALL authenticate to GHCR using the workflow's built-in token with only the permissions required to read contents and write packages, and SHALL NOT require a personal access token.

#### Scenario: Push without secrets
- **WHEN** the workflow runs in a repository with no user-provisioned registry secrets
- **THEN** it authenticates and pushes successfully
