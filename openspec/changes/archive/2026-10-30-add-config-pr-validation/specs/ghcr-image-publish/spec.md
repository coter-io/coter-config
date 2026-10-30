# Spec Delta

## MODIFIED Requirements

### Requirement: Pre-build validation
The system SHALL run the project's config validation, secret scan, and environment-variable contract check against the checked-out tag before building, and SHALL NOT push images if any of them fails.

#### Scenario: Validation failure
- **WHEN** config validation or the secret scan fails on the selected tag
- **THEN** the run fails
- **AND** no image is pushed

#### Scenario: Environment-variable contract failure
- **WHEN** the selected tag references an environment variable that is undocumented or documented under a different name
- **THEN** the run fails
- **AND** no image is pushed

#### Scenario: Same checks as the pull request gate
- **WHEN** a tag is built from a commit that passed the pull request gate unchanged
- **THEN** the pre-build checks are the same ones that gate applied
