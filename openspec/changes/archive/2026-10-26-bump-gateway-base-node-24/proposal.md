# Proposal

## Why

The gateway image fails to build. `docker/Dockerfile` pins `openclaw@2026.10.7`, whose preinstall check requires Node `>=24.22.1 <25 || >=26.12.1`, but the base image is `node:22-bookworm-slim` (Node 22.23.4). `npm install -g openclaw@2026.10.7` exits 1 at step 4/9, so the `v0.1.0` publish run pushed nothing to GHCR.

## What Changes

- Change the gateway base image from `node:22-bookworm-slim` to a Node 24 `bookworm-slim` image that satisfies `>=24.22.1 <25`.
- Pin the base image tightly enough that a Node bump is a deliberate change, like the existing `OPENCLAW_VERSION` pin.
- Note in the README upgrade instructions that bumping `OPENCLAW_VERSION` may also require a Node bump.
- Keep `OPENCLAW_VERSION=2026.10.7`.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
<!-- None. Publish behaviour in ghcr-image-publish is unchanged; this fixes a build input. -->

## Impact

- `docker/Dockerfile` (base image line).
- `README.md` (OpenClaw upgrade notes).
- Runtime of the gateway container moves from Node 22 to Node 24; `clawhub`, `chromium`, `gh`, the `node` user and `entrypoint.sh` must still work.
- A new Git tag is needed to republish, because the failed `v0.1.0` run published nothing.
