# config-pr-validation Specification

## Purpose

Defines how configuration changes are validated automatically on pull requests targeting `main`, so a change that breaks the gateway is rejected before review concludes rather than at release time.

## Requirements

### Requirement: Automatic pull request validation
The system SHALL provide a workflow that runs automatically when a pull request targeting `main` is opened, updated with new commits, or reopened, and SHALL also run on pushes to `main`.

#### Scenario: Pull request opened
- **WHEN** a contributor opens a pull request against `main`
- **THEN** the validation workflow starts without any manual dispatch

#### Scenario: Pull request updated
- **WHEN** new commits are pushed to the head branch of an open pull request against `main`
- **THEN** the validation workflow runs again on the updated head

#### Scenario: Pull request reopened
- **WHEN** a closed pull request against `main` is reopened
- **THEN** the validation workflow runs on its current head

#### Scenario: Direct push to main
- **WHEN** a commit lands on `main` without passing through a pull request
- **THEN** the validation workflow runs on `main`

### Requirement: Validation runs regardless of which files changed
The system SHALL run the validation workflow on every pull request targeting `main`, and SHALL NOT restrict the trigger to a subset of changed paths, so the workflow reports a conclusion on every pull request and can serve as a required status check.

#### Scenario: Pull request touching no configuration file
- **WHEN** a pull request changes only documentation
- **THEN** the validation workflow still runs and reports a conclusion

### Requirement: Read-only execution without secrets
The system SHALL run the validation workflow with read-only repository permissions, and SHALL NOT require any user-provisioned secret or registry credential.

#### Scenario: Fork pull request
- **WHEN** a pull request originates from a fork, where secrets are unavailable
- **THEN** every check in the workflow still runs and reports a genuine result

#### Scenario: Granted permissions
- **WHEN** the workflow runs
- **THEN** it holds no write permission on repository contents, packages, or pull requests

### Requirement: Superseded runs are cancelled
The system SHALL cancel an in-progress validation run for a pull request when a newer commit supersedes it, so the reported conclusion always describes the current head.

#### Scenario: Rapid successive pushes
- **WHEN** a second commit is pushed while validation of the first is still running
- **THEN** the first run is cancelled and only the run for the newer commit reports a conclusion

### Requirement: The gate reuses the repository's validation scripts
The system SHALL perform its checks by invoking the validation scripts the repository already ships, and SHALL NOT reimplement validation logic inside the workflow definition, so the pull request gate, the pre-commit hook, and the release gate cannot disagree about whether a config is valid.

#### Scenario: Script strengthened
- **WHEN** a validation script gains a new check
- **THEN** the pull request gate applies that check with no change to the workflow definition

#### Scenario: Local run matches CI
- **WHEN** a contributor runs the validation scripts locally before pushing
- **THEN** the checks performed are the same ones the pull request gate performs

### Requirement: Offline checks report before environment-dependent checks
The system SHALL run the checks that need neither a container nor network access before those that do, so their findings are reported even when the environment-dependent checks cannot complete.

#### Scenario: Container runtime unavailable
- **WHEN** the schema check cannot run because the container runtime is unavailable
- **THEN** the JSON parse, secret scan, and environment-variable findings have already been reported in the run output

#### Scenario: Multiple defects present
- **WHEN** a pull request contains both a malformed JSON file and an undocumented environment variable
- **THEN** both are reported rather than only the first

### Requirement: A check that cannot run fails the gate
The system SHALL fail the validation workflow when a required check cannot be executed, and SHALL NOT report success on the basis of checks that were skipped.

#### Scenario: Tooling missing
- **WHEN** a required tool or runtime needed by a check is unavailable
- **THEN** the workflow fails with a message naming the missing prerequisite
- **AND** the run is not reported as passing

#### Scenario: Pinned version cannot be resolved
- **WHEN** the pinned OpenClaw version cannot be read from the Dockerfile
- **THEN** the workflow fails rather than validating against an unpinned release

### Requirement: Advisory forward-compatibility signal
The system SHALL report whether the shipped config is also accepted by the most recent published OpenClaw release, and SHALL NOT fail the validation workflow when it is not, so upgrade readiness is visible before the pinned version is bumped.

#### Scenario: Config valid on the newest release
- **WHEN** the config is accepted by both the pinned version and the newest published release
- **THEN** the workflow reports that and passes

#### Scenario: Config rejected by the newest release
- **WHEN** the config is accepted by the pinned version but rejected by the newest published release
- **THEN** the workflow reports the rejection as advisory output
- **AND** the run still passes, because the pinned version is what the gateway runs

### Requirement: Failures name the defect and its remedy
The system SHALL report each validation failure with the file at fault, the configuration path or variable name at fault, and the corrective action, so a contributor can act on the run output without reproducing the run locally.

#### Scenario: Unrecognized configuration key
- **WHEN** the config contains a key the pinned version does not recognize
- **THEN** the failure output names the file, the key, and its location in that file

#### Scenario: Legacy key shape
- **WHEN** the config uses a key shape the pinned version reports as legacy
- **THEN** the failure output names the key and its canonical replacement

#### Scenario: Undocumented environment variable
- **WHEN** a referenced environment variable is not documented
- **THEN** the failure output names the variable, where it is referenced, and the file that must declare it
