# Proposal

## Why

Docker images are currently built and pushed only from a developer laptop via `scripts/build-and-push.sh`, which requires a local Docker login and a `GHCR_USERNAME` env var, and tags images with whatever `HEAD` happens to be checked out. There is no reproducible, auditable way to publish an image for a specific released Git tag. The repo already has a `Create tag` workflow that produces `vX.Y.Z` tags, but nothing consumes them.

## What Changes

- Add a manually triggered (`workflow_dispatch`) GitHub Actions workflow that builds and pushes both project images (`openclaw-gateway`, `workspace-sync`) to GHCR from a selected Git tag.
- The tag is chosen with GitHub's native "Use workflow from" ref picker; the workflow fails fast if the selected ref is not a tag.
- Images are built exactly as `scripts/build-and-push.sh` does (same Dockerfiles, build contexts, `linux/amd64`) and are preceded by the same `validate-config.sh` and `check-secrets.sh` checks.
- Each image is pushed with the Git tag name and the short commit SHA. An optional boolean input (default off) additionally moves `:latest`.
- Authentication uses the built-in `GITHUB_TOKEN` with `packages: write`; no PAT is required.
- Update README "Changing the Docker image" section to document the CI path alongside the local script.

Not changing: `scripts/build-and-push.sh`, Dockerfiles, `docker-compose.yml`, or `tag.yml`. Tags `v0.0.1` and `v1.0.0` predate the workflow file and therefore cannot be built with it; only tags created after the workflow reaches the tagged branch are buildable.

## Capabilities

### New Capabilities
- `ghcr-image-publish`: Manually publishing the project's Docker images to GHCR from a selected Git tag, including tag guarding, pre-build validation, image naming/tagging, and opt-in `latest`.

### Modified Capabilities
<!-- None: no existing specs. -->

## Impact

- New file: `.github/workflows/` workflow (build-and-push on tag).
- Docs: `README.md` image-change workflow section.
- Systems: GHCR namespace `ghcr.io/<repository_owner>/openclaw-docker-config/*` (owner is now `coter-io`; package visibility and VPS pull access must be confirmed). `docker-compose.yml` still resolves images through `GHCR_USERNAME`.
- Rollout dependency: the workflow must be on `develop` (default branch) to be dispatchable and on `main` before cutting a new tag with `tag.yml`.
