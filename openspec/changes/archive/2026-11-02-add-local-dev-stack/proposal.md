# Proposal

## Why

The shipped configuration cannot be exercised before it reaches the VPS. `config/openclaw.json` is neither baked into the gateway image nor mounted from this repo — it only ever arrives on the VPS by SCP from the infra repo (`make push-config`), landing in the host directory that `OPENCLAW_CONFIG_DIR` bind-mounts. A plain `docker compose up` from `docker/` therefore boots a gateway with no configuration at all, so recent work that only shows up at runtime (audio transcription, media models, OpenRouter routing, ClawHub skill installs) can be validated only by deploying it.

`scripts/validate-config.sh` already covers static correctness — it runs `config validate` and `doctor --lint` against the real file at the pinned version. The gap is a live gateway a developer can talk to.

## What Changes

- Add `local.sh` in the project root: a single command that brings the full stack up locally, builds the gateway image from `docker/Dockerfile`, and follows logs. Supporting subcommands for teardown, logs, a container shell, and resetting local state.
- Add `docker/docker-compose.local.yml`, applied explicitly alongside `docker/docker-compose.yml`. It supplies the deltas prod does not need: a `build:` stanza, host paths that exist on a developer machine, and an `env_file` pointing at the root `.env`. `docker/docker-compose.yml` is not modified.
- Read all variables from a `.env` in the project root, seeded from `docker/.env.example` on first run. Already covered by `.gitignore`.
- Deliver configuration locally the way prod delivers it: copy `config/*` into a gitignored local state directory that the container bind-mounts, refreshed on every start.
- Add a preflight that compares the keys present in the developer's `.env` against the keys declared in `docker/.env.example`, reporting both missing and undeclared names before anything starts.
- Remove `docker/.env`. It is incomplete (missing four variables compose marks required), declares `BRAVE_SEARCH_API_KEY` where compose injects `BRAVE_API_KEY`, and becomes a second source of truth once the root `.env` exists. `docker/.env.example` is unaffected.
- Require the local stack to be isolated from the deployed one: its own gateway token, its own Telegram bot token, and its own state directory, with the bot token surfaced at startup so a shared-token mistake is visible.
- Document the local workflow in `README.md` alongside the existing config and image workflows.

## Capabilities

### New Capabilities
- `local-dev-stack`: Bringing the shipped configuration up as a running gateway on a developer machine — what a single command must do, how configuration and secrets reach the container, how local state is kept inspectable, and how the local stack stays isolated from the deployed one.

### Modified Capabilities
- `deployment-env-contract`: Two requirement changes. The existing scan requirement ("every variable `docker/docker-compose.yml` interpolates must be declared") is scoped explicitly to the deployment compose file, so a local-only override file is a deliberate exemption rather than an unnoticed hole in the gate. A new requirement covers verifying a filled-in environment file against the declared contract — the purpose statement already promises "no silently empty credential", but nothing checks the file an operator actually supplies, which is how the `BRAVE_SEARCH_API_KEY` drift went unnoticed.

## Impact

**New files**
- `local.sh` (project root)
- `docker/docker-compose.local.yml`
- a check script for the `.env`-against-`.env.example` comparison, under `scripts/`

**Modified**
- `.gitignore` — the local state directory
- `README.md` — local workflow section
- `scripts/check-env-vars.sh` — state that its compose scan covers the deployment compose file only
- `CONTRIBUTING.md` and `scripts/build-and-push.sh` — re-point their `docker/.env` instructions at the root `.env`
- `docker/docker-compose.yml` — one `:?` message string, which named `docker/.env` as where to set `OPENROUTER_API_KEY`

**Removed**
- `docker/.env` (untracked, and holding no credentials — every credential field in it was empty)

**Not changed**
- `docker/Dockerfile` and `config/openclaw.json`. The point of the exercise is to run the shipped artifacts as shipped; a local run that needs them edited would not be testing them. `docker/docker-compose.yml` is unchanged in behaviour — the one edit is an error-message string that would otherwise send an operator to a deleted file; no key, default, mount or service definition is touched.

**Runtime consequences a developer accepts**
- Real spend on `OPENROUTER_API_KEY`, including per-second audio billing for voice notes.
- Live tool access through `mcp.servers.composio`, so a local agent can cause real side effects on whatever that server has connected. See `design.md` — this is an open decision.
- The image is built for the developer's native architecture, not the `linux/amd64` artifact `scripts/build-and-push.sh` produces for the VPS.
- `workspace-sync` stays behind its `sync` profile and is not started locally.
