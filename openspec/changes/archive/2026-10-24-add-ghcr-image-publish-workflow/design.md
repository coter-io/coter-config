# Design

## Context

- `scripts/build-and-push.sh` is the reference build: runs `validate-config.sh` and `check-secrets.sh`, then `docker buildx build --platform linux/amd64 --push` for `docker/Dockerfile` (context = repo root) and `docker/workspace-sync/Dockerfile` (context = `docker/workspace-sync`), tagging `$TAG` and the short SHA.
- Both validation scripts need only `bash`, `jq`, `git`, and `grep`, all present on `ubuntu-latest`. `check-secrets.sh` scans `git ls-files`, so the checkout must be a real git checkout (default `actions/checkout` is fine).
- `.github/workflows/tag.yml` creates `vX.Y.Z` tags from `main` via `workflow_dispatch`. Tags pushed with `GITHUB_TOKEN` do not trigger other workflows, so a separate manual workflow is the consumer.
- `docker-compose.yml` references images as `ghcr.io/${GHCR_USERNAME}/openclaw-docker-config/<name>:latest`.
- The default branch is `develop`; `workflow_dispatch` is only listed when the file exists there.

## Goals / Non-Goals

**Goals:**
- One manual, reproducible path from an existing tag to published GHCR images.
- Behavioral parity with `build-and-push.sh` (images, contexts, platform, validation).

**Non-Goals:**
- Replacing or modifying `build-and-push.sh`.
- Automatic builds on push/tag, multi-arch builds, or build caching tuning.
- Building `v0.0.1` / `v1.0.0` (they lack the workflow file).
- Changing compose to pin versions.

## Decisions

1. **Native ref picker, no tag input.** The tag is `github.ref_name`; a guard step fails unless `github.ref_type == 'tag'`. Alternative: a string input plus `checkout ref:`, which would also build old tags, but the user chose the native picker. Consequence: only tags containing the workflow file are buildable.
2. **Single job, two sequential build steps** (gateway, then workspace-sync) using `docker/setup-buildx-action`, `docker/login-action` (ghcr.io, `github.actor` / `GITHUB_TOKEN`), and `docker/build-push-action`. Alternative: a matrix over the two images; rejected as unnecessary for two images and it would allow one image to publish while the other fails. Sequential steps in one job keep behavior close to the script. Validation runs first so a failure pushes nothing.
3. **Image path:** `ghcr.io/${{ github.repository_owner }}/openclaw-docker-config/<name>`, keeping existing names so compose only needs `GHCR_USERNAME` set to the owner. The owner must be lowercased for GHCR (org names may contain uppercase); compute it with a shell lowercase step.
4. **Tags:** `<git tag>` and 7-char short SHA (matching `git rev-parse --short`, which may vary in length; use `${GITHUB_SHA::7}`). `latest` is added only when the `latest` boolean input (default `false`) is true.
5. **Permissions:** workflow-level `contents: read`, `packages: write`. No PAT.
6. **Concurrency:** group per ref, `cancel-in-progress: false`, so two runs on one tag don't interleave pushes.
7. **OCI labels:** set `org.opencontainers.image.source` to the repo URL so packages link to the repository and inherit its access settings.
8. **Pinned actions:** use major-version tags consistent with `tag.yml` (`actions/checkout@v4`).

## Risks / Trade-offs

- [Old tags unbuildable] → Documented in README; cut a new tag via `tag.yml` after merging.
- [Workflow must reach `main` before tagging, as `tag.yml` tags `main`] → Rollout order documented in tasks.
- [New GHCR packages under `coter-io` start private; VPS may lack pull access] → Source label links packages to the repo; confirm visibility/pull credentials during verification.
- [Owner namespace differs from previous personal-account images] → `GHCR_USERNAME` on the VPS must be updated to the org name before deploying new images.
- [`check-secrets.sh` base64-like pattern may yield false positives in CI] → Same behavior as local; surfaced on first run and fixed separately if hit.
- [`latest` rebuilt from an older tag moves backwards] → Opt-in only.

## Migration Plan

1. Merge workflow to `develop`, then `main`.
2. Run `Create tag` to cut a new tag (e.g. `v1.0.1`).
3. Run the new workflow on that tag, first without `latest`; verify both images and tags in GHCR.
4. Set package visibility / VPS pull access as needed, then re-run with `latest` when ready to deploy.

Rollback: delete the workflow file; published images can be removed from GHCR package settings. Nothing else depends on the workflow.
