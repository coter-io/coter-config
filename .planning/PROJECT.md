# coter-config

## What This Is

Configuration and packaging repo for an OpenClaw AI agent gateway (Telegram) running in Docker on a Hetzner VPS, plus a vendored GSD agent-workflow toolkit (`.claude/`, `.codex/`, `.cursor/`). It is not an application: the "product" is config, Dockerfiles, shell scripts, and prompt/workflow definitions. Companion to the infra repo `openclaw-terraform-hetzner`, which provisions and deploys.

## Core Value

The OpenClaw gateway image and config can be validated, built, and pushed to GHCR safely (no leaked secrets) so the infra repo can deploy them to the VPS.

## Current Milestone: v1.1 GHCR Image Publish Workflow

**Goal:** Publish the Docker images for an existing Git tag to GHCR from a manually triggered GitHub Actions workflow.

**Target features:**
- `workflow_dispatch` with a selectable existing tag (verified to exist, then checked out)
- Run `validate-config.sh` and `check-secrets.sh` on that tag before building
- Build and push `openclaw-gateway` and `workspace-sync` (linux/amd64) following `scripts/build-and-push.sh`
- Tag images `:<git-tag>` and `:<short-sha>` (no `:latest`)
- Authenticate to GHCR with `GITHUB_TOKEN` (`packages: write`)

## Requirements

### Validated

- ✓ Gateway runtime config (`config/openclaw.json`) and ClawHub skills manifest (`config/skills-manifest.txt`) — existing
- ✓ Gateway Docker image (Node 22, gh CLI, chromium, tini) with entrypoint that seeds workspace templates and installs skills — existing
- ✓ Optional `workspace-sync` sidecar that cron-pushes the OpenClaw workspace to a git remote — existing
- ✓ Config validation and secret scanning (`scripts/validate-config.sh`, `scripts/check-secrets.sh`) — existing
- ✓ Multi-arch (linux/amd64) build and push of both images to GHCR tagged `latest` + short SHA (`scripts/build-and-push.sh`) — existing
- ✓ Workspace seed templates copied no-clobber on first boot (`workspace-templates/`) — existing
- ✓ GSD workflow toolkit vendored for Claude Code, Codex, and Cursor — existing
- ✓ Manual SemVer tag CI workflow — existing

### Active

- [ ] Manual GitHub Actions workflow builds and pushes both images to GHCR for a chosen existing Git tag (v1.1)

### Out of Scope

- VPS provisioning, bootstrap, and deploy — owned by the companion infra repo
- Application source code — this repo holds configuration only
- Committing secrets — they live in `docker/.env` (gitignored) and the infra repo's `secrets/openclaw.env`

## Context

- Brownfield: initialized from the existing codebase map in `.planning/codebase/` (ARCHITECTURE, STACK, STRUCTURE, CONVENTIONS, INTEGRATIONS, TESTING, CONCERNS), dated 2026-08-21.
- OpenClaw is pinned via `ARG OPENCLAW_VERSION` in `docker/Dockerfile`; config is pushed by SCP without an image rebuild.
- No automated test suite; validation is shell-script based.
- Known issues are tracked in `.planning/codebase/CONCERNS.md`.

## Constraints

- **Deployment**: Push-based via the infra repo (`make push-config`, `make deploy`) — this repo never runs the container itself
- **Security**: No secrets in git — enforced by `scripts/check-secrets.sh` and `scripts/validate-config.sh`
- **Platform**: Images built for linux/amd64 — matches the Hetzner VPS

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Immutable image + externally pushed config | Rebuild only for binary/version changes | — Pending |
| GSD toolkit vendored per agent runtime | Each runtime needs its own commands/hooks layout | — Pending |
| Initialized with PROJECT.md only (no roadmap) | No new work to define at this time | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-10-24 after starting milestone v1.1*
