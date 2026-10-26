# Proposal

## Why

Images are currently publishable from any tag, including tags that were never released. Releases are the project's signal that a version is intended for distribution, so images should only be published from tags that have a GitHub release. GitHub's dispatch UI can only select branches and tags, not releases, so the guarantee has to be enforced inside the workflow.

## What Changes

- `publish-image.yml` keeps selecting a tag via "Use workflow from", and gains a step that checks a GitHub release exists for that tag.
- If no release exists, the run fails before validation, build, or push, with a message telling the maintainer to create the release first.
- README publishing instructions gain the release step.
- `tag.yml` is unchanged.

## Capabilities

### New Capabilities

### Modified Capabilities
- `ghcr-image-publish`: adds a requirement that publishing is allowed only for tags that have a published GitHub release.

## Impact

- `.github/workflows/publish-image.yml`: new release-check step; the existing `contents: read` permission is sufficient.
- `README.md`: "Publishing from CI" section.
- Existing tags without a release (e.g. `v1.0.1`) can no longer be published until a release is created for them.
