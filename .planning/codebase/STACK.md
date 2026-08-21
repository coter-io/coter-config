# Technology Stack

**Analysis Date:** 2026-08-21

## Project Nature

This repository ("coter-config") is a **configuration and deployment repo** for the OpenClaw AI agent gateway plus a bundled GSD (Get-Stuff-Done) AI coding-agent workflow toolkit. There is no application source tree in the traditional sense — the "product" is:
- Docker images that run the `openclaw` gateway CLI (installed as a global npm package, not built from source here)
- JSON/Markdown configuration consumed by that gateway and by AI coding agents (Claude Code, Cursor, Codex)
- Shell scripts for validation, secret-scanning, and image build/push
- A large tree of Markdown-based "skills"/"agents"/"commands" definitions (`.claude/`, `.codex/`, `.cursor/`) that configure how AI coding assistants behave in this repo, driven by a Node.js CLI toolkit (`gsd-tools.cjs`) and JS hook scripts

## Languages

**Primary:**
- Shell (Bash) — build/deploy/validation scripts: `scripts/validate-config.sh`, `scripts/check-secrets.sh`, `scripts/build-and-push.sh`, `docker/entrypoint.sh`, `docker/workspace-sync/*.sh`
- JavaScript (Node.js, CommonJS) — GSD tooling and Claude Code hooks: `.claude/gsd-core/bin/gsd-tools.cjs`, `.claude/hooks/*.js`, `.cursor/scripts/*.cjs`
- Markdown — configuration-as-prompts for AI agents: hundreds of files under `.claude/`, `.codex/`, `.cursor/` (skills, commands, agent definitions, reference docs)

**Secondary:**
- JSON — structured config: `config/openclaw.json`, `.claude/hooks/package.json`, various `.gsd-runtime`/manifest files
- YAML — `docker/docker-compose.yml`

## Runtime

**Environment:**
- Node.js 22 (Debian Bookworm slim base) inside the gateway Docker image — see `docker/Dockerfile` (`FROM node:22-bookworm-slim`)
- Alpine 3.19 + `bash`/`git` for the lightweight workspace-sync sidecar image — `docker/workspace-sync/Dockerfile`
- No `.nvmrc` / `.node-version` file present; Node version is pinned only via the Docker base image tag

**Package Manager:**
- No root `package.json` / npm lockfile for the repo itself (this is not an npm project)
- `.claude/hooks/package.json`, `.codex/hooks/package.json`, `.cursor/hooks/package.json` each contain only `{"type":"commonjs"}` — used solely to tell Node.js how to interpret adjacent `.js` files, not for dependency management
- Global npm installs happen at Docker build time: `npm install -g openclaw@${OPENCLAW_VERSION}` and `npm install -g clawhub`
- No lockfile present (consistent with "config repo," not an application build)

## Frameworks / Platforms

**Core Runtime Platform:**
- OpenClaw — AI agent gateway, installed globally in the Docker image, pinned via `ARG OPENCLAW_VERSION` in `docker/Dockerfile` (currently `2026.4.29`)
- ClawHub — CLI for installing/managing OpenClaw "skills" (e.g. `agent-browser`), invoked at container startup by `docker/entrypoint.sh` against `config/skills-manifest.txt`

**AI Coding Agent Tooling (GSD):**
- GSD Core — custom workflow/orchestration framework for AI coding agents, vendored per-agent under `.claude/gsd-core/`, `.codex/gsd-core/`, `.cursor/gsd-core/`
  - Version: `1.11.0` (`.claude/gsd-core/VERSION`)
  - Runtime target recorded per directory in `.gsd-runtime` (e.g. `claude`)
  - CLI entrypoint: `.claude/gsd-core/bin/gsd-tools.cjs`, launcher `.claude/gsd-core/bin/gsd_run`
  - Supporting bin scripts: `check-latest-version.cjs`, `verify-reapply-patches.cjs`, `ensure-runtime-build.cjs`
- Claude Code — primary agent runtime, configured via `.claude/` (commands, agents, hooks, skills)
- Cursor and Codex — secondary agent runtimes with parallel configuration trees (`.cursor/`, `.codex/`)

**Build/Dev Tooling:**
- Docker Buildx — multi-platform image builds (`linux/amd64` pinned), driven by `scripts/build-and-push.sh`
- `jq` — used by `scripts/validate-config.sh` for JSON validation of `config/openclaw.json`
- `tini` — init process in the gateway container (`docker/Dockerfile` ENTRYPOINT)

**Testing:**
- No automated test framework detected in this repo (no test runner config, no `*.test.*`/`*.spec.*` files found). Validation is done via shell scripts (`scripts/validate-config.sh`, `scripts/check-secrets.sh`) rather than a unit-test suite.

## Key Dependencies

**Critical (installed at image build time, not vendored):**
- `openclaw` (npm, global) — the agent gateway itself; version pinned via `OPENCLAW_VERSION` build arg
- `clawhub` (npm, global) — skill package manager for OpenClaw
- `gh` (GitHub CLI, apt via custom repo) — required by the "github" OpenClaw skill
- `chromium` (apt) — headless browser dependency, likely for the `agent-browser` skill
- `git`, `curl`, `ca-certificates`, `gnupg` (apt) — base build/runtime utilities

**Infrastructure:**
- `alpine:3.19` + `git`/`bash` — minimal base for the `workspace-sync` sidecar that syncs the OpenClaw workspace to a git remote

## Configuration

**Environment:**
- Runtime configuration is environment-variable driven; see `docker/docker-compose.yml` for the full set consumed by the gateway service (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `BRAVE_API_KEY`, `GH_TOKEN`, `OPENCLAW_GATEWAY_TOKEN`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_USER_ID`, `COMPOSIO_API_KEY`, `COMPOSIO_MCP_URL`)
- `docker/.env` and `docker/.env.example` exist (contents not read — treated as secret/forbidden per policy); `.env` is present and gitignored
- Sync sidecar variables: `GIT_WORKSPACE_REPO`, `GIT_WORKSPACE_REMOTE`, `GIT_WORKSPACE_BRANCH`, `GIT_WORKSPACE_TOKEN`, `GIT_WORKSPACE_SYNC_SCHEDULE`
- `GHCR_USERNAME` — required shell env var for `scripts/build-and-push.sh` (used to compute the GHCR image prefix)

**Application Config:**
- `config/openclaw.json` — main OpenClaw gateway configuration (gateway mode/port, channels, plugins, agent model defaults/fallbacks, MCP servers, logging). References secrets only via `${ENV_VAR}` interpolation, never literals — enforced by `scripts/validate-config.sh`
- `config/security-rules.md` — documented security rules/policy for the config repo
- `config/skills-manifest.txt` — list of ClawHub skills auto-installed on container startup

**Validation/Security tooling:**
- `scripts/validate-config.sh` — validates `config/openclaw.json` is well-formed JSON and free of raw API-key patterns (regex allowlist: `sk-ant-|sk-proj-|bot[0-9]|bsc_|xai-|gsk_`)
- `scripts/check-secrets.sh` — scans all git-tracked files (excluding `*.env.example`, `*.md`) against a broader set of secret-pattern regexes (Anthropic/OpenAI keys, Telegram bot tokens, base64 blobs, Bearer tokens)
- `.githooks/` — local git hook(s) directory (likely wiring the above scripts into pre-commit/pre-push; not read in detail due to permission)

## Platform Requirements

**Development:**
- Docker + Docker Buildx (for building/pushing images)
- `jq`, `git`, `bash` on the host for running the validation/build scripts
- GitHub Container Registry (GHCR) access with `GHCR_USERNAME` set for pushing images

**Production:**
- Deployment target: a Docker host running `docker compose` with two services — `openclaw-gateway` (the agent gateway, bound to `127.0.0.1:18789`) and an optional `workspace-sync` sidecar (profile `sync`) that periodically syncs the workspace to a git remote via a cron-style schedule
- Images published to `ghcr.io/${GHCR_USERNAME}/openclaw-docker-config/{openclaw-gateway,workspace-sync}`, built for `linux/amd64`
- Multi-agent setups scale by duplicating the `workspace-sync` service per agent (documented inline in `docker/docker-compose.yml`)

---

*Stack analysis: 2026-08-21*
