# Requirements: coter-config

**Defined:** 2026-10-24
**Core Value:** The OpenClaw gateway image and config can be validated, built, and pushed to GHCR safely (no leaked secrets) so the infra repo can deploy them to the VPS.

## v1.1 Requirements

Milestone v1.1: GHCR Image Publish Workflow. Each maps to roadmap phases.

### Trigger and tag selection

- [ ] **TRIG-01**: Maintainer can start the workflow manually from the Actions tab (`workflow_dispatch`)
- [ ] **TRIG-02**: Maintainer can pick the Git tag to build when starting the run (run-from-tag selector or a `tag` input)
- [ ] **TRIG-03**: The run fails with a clear message if the chosen ref is not an existing tag
- [ ] **TRIG-04**: The build runs against the checked-out contents of that tag, not the default branch

### Pre-build validation

- [ ] **VAL-01**: `scripts/validate-config.sh` runs on the tag and a failure stops the run before any push
- [ ] **VAL-02**: `scripts/check-secrets.sh` runs on the tag and a failure stops the run before any push

### Image build and publish

- [ ] **IMG-01**: `openclaw-gateway` is built from `docker/Dockerfile` with the repo root as context, `linux/amd64`
- [ ] **IMG-02**: `workspace-sync` is built from `docker/workspace-sync/Dockerfile` with `docker/workspace-sync` as context, `linux/amd64`
- [ ] **IMG-03**: Each image is pushed to `ghcr.io/<owner>/openclaw-docker-config/<image>`, the same path as `scripts/build-and-push.sh`, with owner taken from the repo owner (lowercased)
- [ ] **IMG-04**: Each image gets the git tag and the short commit SHA as tags, and never `:latest`

### Auth and safety

- [ ] **SEC-01**: GHCR login uses `GITHUB_TOKEN` with least-privilege permissions (`contents: read`, `packages: write`) and no new secrets
- [ ] **SEC-02**: Concurrent runs for the same tag don't overlap (a concurrency group, without cancelling in-progress runs)

## Future Requirements

- **FUT-01**: Multi-arch image builds
- **FUT-02**: Build cache (`type=gha`)
- **FUT-03**: Auto-trigger on tag push
- **FUT-04**: Image provenance / signing

## Out of Scope

| Feature | Reason |
|---------|--------|
| Pushing `:latest` | Rebuilding an older tag would silently move `latest` backwards |
| Deploying to the VPS | Owned by the companion infra repo |
| Changing the Dockerfiles | The workflow follows the existing build instructions as-is |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| TRIG-01 | Phase 1 | Pending |
| TRIG-02 | Phase 1 | Pending |
| TRIG-03 | Phase 1 | Pending |
| TRIG-04 | Phase 1 | Pending |
| VAL-01 | Phase 1 | Pending |
| VAL-02 | Phase 1 | Pending |
| SEC-02 | Phase 1 | Pending |
| IMG-01 | Phase 2 | Pending |
| IMG-02 | Phase 2 | Pending |
| IMG-03 | Phase 2 | Pending |
| IMG-04 | Phase 2 | Pending |
| SEC-01 | Phase 2 | Pending |

**Coverage:**
- v1.1 requirements: 12 total
- Mapped to phases: 12
- Unmapped: 0 ✓

---
*Requirements defined: 2026-10-24*
*Last updated: 2026-10-24 after roadmap creation*
