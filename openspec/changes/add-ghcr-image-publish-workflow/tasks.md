# Tasks

## 1. Workflow skeleton and guards

- [x] 1.1 Create `.github/workflows/publish-image.yml` with `workflow_dispatch` only, a boolean `latest` input (default `false`), `contents: read` + `packages: write` permissions, and per-ref concurrency; verify with `actionlint` (or `yq` parse) that the file is valid and has no other triggers
- [x] 1.2 Add a first step that fails with a "select a tag" message unless `github.ref_type == 'tag'`; verify the condition by inspection and, once on GitHub, by dispatching from a branch (run fails, nothing pushed)
- [x] 1.3 Add checkout, then run `scripts/validate-config.sh` and `scripts/check-secrets.sh`; verify both pass locally with `bash scripts/validate-config.sh && bash scripts/check-secrets.sh`

## 2. Build and push

- [x] 2.1 Add buildx setup and GHCR login (`github.actor` / `GITHUB_TOKEN`), and compute a lowercased owner and 7-char SHA as step outputs; verify outputs by echoing them in a dry run or review
- [x] 2.2 Add gateway build-push step (`docker/Dockerfile`, context `.`, `linux/amd64`) tagged `<git tag>` and `<short sha>`, plus `latest` only when the input is true, with `org.opencontainers.image.source` label; verify locally with `docker buildx build --platform linux/amd64 -f docker/Dockerfile .`
- [x] 2.3 Add workspace-sync build-push step (`docker/workspace-sync/Dockerfile`, context `docker/workspace-sync`) with identical tagging and label; verify locally with `docker buildx build --platform linux/amd64 docker/workspace-sync`
- [x] 2.4 Confirm image names match `ghcr.io/<owner>/openclaw-docker-config/{openclaw-gateway,workspace-sync}` and those referenced in `docker/docker-compose.yml`; verify by grep comparison

## 3. Documentation

- [x] 3.1 Update the README "Changing the Docker image" section to describe the CI workflow (select a tag, `latest` checkbox, old tags `v0.0.1`/`v1.0.0` not buildable, rollout order, `GHCR_USERNAME` must match the owner); verify the steps read correctly against the workflow inputs

## 4. Rollout and end-to-end verification

- [ ] 4.1 After merging to `develop` and `main`, run `Create tag` to cut a new tag, then dispatch the workflow on it with `latest` off; verify both images appear in GHCR tagged `<git tag>` and `<short sha>` and that `latest` was not moved
- [ ] 4.2 Dispatch from a branch and verify the run fails before any build; re-run on the tag with `latest` on and verify `latest` now exists on both images
- [ ] 4.3 Check GHCR package visibility/repo linkage and VPS pull access under `coter-io`; verify `docker pull` of the published image succeeds from the target environment
