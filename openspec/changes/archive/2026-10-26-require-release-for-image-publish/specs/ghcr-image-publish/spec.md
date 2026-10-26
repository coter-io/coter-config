# Spec Delta

## ADDED Requirements

### Requirement: Require a published release
The system SHALL fail before validating, building, or pushing anything when the selected tag has no published GitHub release.

#### Scenario: Tag with a published release
- **WHEN** a maintainer dispatches the workflow from a tag that has a published GitHub release
- **THEN** the release check passes and the workflow continues to validation and build

#### Scenario: Tag without a release
- **WHEN** a maintainer dispatches the workflow from a tag that has no GitHub release
- **THEN** the run fails with a message instructing the maintainer to create a release for that tag
- **AND** no image is built or pushed

#### Scenario: Draft release only
- **WHEN** the only release for the selected tag is an unpublished draft
- **THEN** the run fails as if no release existed

#### Scenario: Pre-release
- **WHEN** the selected tag has a published release marked as a pre-release
- **THEN** the release check passes
