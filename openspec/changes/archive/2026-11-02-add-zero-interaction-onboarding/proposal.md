# Proposal

## Why

On a fresh workspace OpenClaw seeds `BOOTSTRAP.md`, and the agent's first turn becomes a setup ritual: it asks what to call it, proposes a vibe, generates a four-option avatar sheet, and offers plugin installs. A user who starts the gateway cannot simply use the agent. Worse, the ritual ends by running `openclaw agents set-identity`, which writes identity into `openclaw.json` — the file this repository ships declaratively and overwrites on every bring-up. That collision has already happened locally: the gateway preserved an `openclaw.json.clobbered.*` copy after `local.sh` replaced the agent-written identity.

The repository already has the delivery channel for predefined workspace files — `workspace-templates/` is copied into the image and seeded by `docker/entrypoint.sh` — but it holds only `.gitkeep`, and no spec or gate covers it.

## What Changes

- Set `agents.defaults.skipBootstrap: true` in `config/openclaw.json` so OpenClaw creates no workspace bootstrap files at all, and `BOOTSTRAP.md` can never exist. Injection of existing workspace files is unaffected.
- Populate `workspace-templates/` with the four predefined workspace files the agent needs — `AGENTS.md`, `SOUL.md`, `IDENTITY.md`, `USER.md` — since with bootstrap creation disabled the gateway supplies none of them.
- Commit a static `workspace-templates/avatars/avatar.png` and reference it from identity, so an avatar is present without any image generation.
- Make `config/openclaw.json` the single authoring point for displayed identity by declaring `name`, `emoji`, `theme`, and `avatar` for the `main` agent, and resolve the current drift between the config's emoji and the one in the workspace identity file.
- Add a fail-closed check to the repository's validation scripts so emptying `workspace-templates/`, dropping a required file, or removing the `skipBootstrap` key cannot silently restore the onboarding ritual.
- Extend the forward-compatibility check so an OpenClaw version bump surfaces drift between the predefined files and the upstream templates they were derived from.

No change to externally observable deployment behavior beyond the agent's first turn: no new environment variable, no compose change, no image-publish change.

## Capabilities

### New Capabilities

- `agent-workspace-provisioning`: How the agent's workspace files and identity are predefined in this repository and delivered to the gateway's workspace, and the guarantee that a first start requires no interaction, generates no avatar, and asks no setup question.

### Modified Capabilities

None. `local-dev-stack` governs how `config/*` reaches the container and says nothing about workspace file provisioning; its "Repeat starts do not redo completed setup" requirement is already satisfied by the entrypoint's no-clobber copy. `config-pr-validation` already requires the gate to apply any check a validation script gains, so strengthening those scripts needs no requirement change. `ghcr-image-publish` and `deployment-env-contract` are untouched: same Dockerfiles and build contexts, no new variables.

## Impact

- `config/openclaw.json` — new `agents.defaults.skipBootstrap` key; `agents.entries.main.identity` gains `theme` and `avatar`, and its `emoji` is corrected.
- `workspace-templates/` — four new Markdown files plus `avatars/avatar.png`; `.gitkeep` becomes unnecessary. This is the first binary committed to the repository.
- `scripts/validate-config.sh` and `scripts/check-forward-compat.sh` — new checks. These run in the pre-commit hook, the pull request gate, and the release gate, so a defect blocks all three.
- `docker/Dockerfile` and `docker/entrypoint.sh` — no change needed; the `COPY workspace-templates/` and no-clobber seeding already do the work.
- `README.md` / `CONTRIBUTING.md` — document that workspace identity is predefined and where to change it.
- Ongoing cost: `AGENTS.md` is derived from the upstream template, so each `ARG OPENCLAW_VERSION` bump must re-diff it rather than inheriting upstream improvements automatically.
