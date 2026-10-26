## Context

`openclaw@2026.10.7` declares `node >=24.22.1 <25 || >=26.12.1` and enforces it in a preinstall script, so the failure is a hard error and not only an `EBADENGINE` warning. The Dockerfile uses `FROM node:22-bookworm-slim`. Only the gateway image is affected; `workspace-sync` has its own Dockerfile.

## Goals / Non-Goals

**Goals:**
- The gateway image builds locally and in the Publish image workflow.
- The container still starts through `tini` and `entrypoint.sh`.

**Non-Goals:**
- Changing `OPENCLAW_VERSION`.
- Changing `workspace-sync`.
- Adding build caching or changing the publish workflow.
- Moving to Node 26.

## Decisions

- **Node 24 over Node 26.** Node 24 is the lower of the two supported lines and matches the `>=24.22.1 <25` branch, so it is the smallest jump. Alternative: pin an older openclaw that supports Node 22; rejected because the user chose to stay on `2026.10.7`.
- **Pin the base by Node minor version, for example `node:24.22-bookworm-slim`, or by digest.** The floor is 24.22.1, so the `24` tag alone could in principle resolve below it. The exact tag is confirmed during implementation against Docker Hub and must be at or above 24.22.1. Alternative: floating `node:24-bookworm-slim`; simpler, but a base change then lands without a commit.
- **Keep the Debian bookworm base.** The apt packages (`chromium`, `gh`, `tini`) installed fine on the current base, so changing the Debian release would add risk for no reason.

## Risks / Trade-offs

- [Steps 5-9 never ran, so `clawhub` install and later steps are unverified on any Node] -> Build locally and smoke-start the container before tagging.
- [Node 24 could change behaviour of openclaw or skills at runtime] -> Smoke-start with the real entrypoint and check the skills install loop completes.
- [A pinned minor drifts behind security patches] -> Bumping it is a one-line change, documented in the README note.

## Migration Plan

1. Land the Dockerfile change.
2. Build locally for `linux/amd64` and smoke-start.
3. Create a new tag (for example `v0.1.1`) and dispatch the Publish image workflow from it. Do not move `v0.1.0`; CI already built from it.
4. Roll back by redeploying the previous `latest` or SHA tag from the infra repo.

## Open Questions

- Whether to move or delete the failed `v0.1.0` tag. Default: leave it and cut a new tag.
