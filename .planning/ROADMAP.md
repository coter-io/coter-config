# Roadmap: coter-config

## Overview

Milestone v1.1 adds one deliverable: a manually triggered GitHub Actions workflow (`.github/workflows/*.yml`) that publishes the `openclaw-gateway` and `workspace-sync` images to GHCR for an existing Git tag. The work splits at the one irreversible step. Phase 1 builds the safe front half (manual trigger, tag selection and checkout, config validation, secret scan, concurrency) and can be run end to end on a real tag without writing anything to the registry. Phase 2 adds the publish half (build, authenticate with `GITHUB_TOKEN`, push both images tagged `:<git-tag>` and `:<short-sha>`, never `:latest`), so the first registry write only happens behind a gate that has already been proven.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Tag Selection and Validation Gate** - Manual workflow that checks out a chosen existing tag and runs config validation and secret scanning on it, with no registry writes
- [ ] **Phase 2: Build and Publish to GHCR** - Build both images for the validated tag and push them to GHCR with `GITHUB_TOKEN`, tagged `:<git-tag>` and `:<short-sha>`

## Phase Details

### Phase 1: Tag Selection and Validation Gate
**Goal**: A maintainer can manually start a workflow run for an existing Git tag and get a pass/fail answer on whether that tag's config and contents are safe to publish, without anything being pushed.
**Depends on**: Nothing (first phase)
**Requirements**: TRIG-01, TRIG-02, TRIG-03, TRIG-04, VAL-01, VAL-02, SEC-02
**Success Criteria** (what must be TRUE):
  1. The workflow appears in the repo's Actions tab with a "Run workflow" button, and the maintainer can choose which Git tag to run it against when starting the run.
  2. Starting a run with a ref that is not an existing tag fails early with a clear error message and executes no later steps.
  3. Starting a run on an existing tag checks out that tag's contents (the run log shows HEAD at the tag's commit), not the default branch.
  4. `scripts/validate-config.sh` and `scripts/check-secrets.sh` both run against the checked-out tag, and a non-zero exit from either fails the run.
  5. Two runs started for the same tag execute one after the other instead of overlapping, and the second run is queued rather than cancelling the first.
**Plans**: TBD

### Phase 2: Build and Publish to GHCR
**Goal**: A passing run on an existing tag leaves both images published in GHCR under the same path as `scripts/build-and-push.sh`, ready for the infra repo to deploy by tag or SHA.
**Depends on**: Phase 1
**Requirements**: IMG-01, IMG-02, IMG-03, IMG-04, SEC-01
**Success Criteria** (what must be TRUE):
  1. After a successful run, `ghcr.io/<owner>/openclaw-docker-config/openclaw-gateway` and `ghcr.io/<owner>/openclaw-docker-config/workspace-sync` both exist in GHCR, with the owner lowercased from the repo owner.
  2. Each published image carries exactly two tags, the Git tag that was selected and the short commit SHA of that tag. There is no `:latest` tag, and re-running an older tag does not move any other tag.
  3. Both published images are `linux/amd64`, built from `docker/Dockerfile` (repo root context) and `docker/workspace-sync/Dockerfile` (`docker/workspace-sync` context) respectively.
  4. A run where validation or the secret scan fails pushes nothing to GHCR.
  5. The workflow authenticates to GHCR with the built-in `GITHUB_TOKEN` only, declares just `contents: read` and `packages: write` permissions, and needs no new repository secrets.
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Tag Selection and Validation Gate | 0/TBD | Not started | - |
| 2. Build and Publish to GHCR | 0/TBD | Not started | - |
