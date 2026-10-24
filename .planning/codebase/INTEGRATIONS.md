# External Integrations

**Analysis Date:** 2026-08-21

## APIs & External Services

**LLM Providers (via OpenClaw agent config, `config/openclaw.json`):**
- OpenAI — primary chat model `openai/gpt-5.3-chat`, fallbacks `openai/gpt-5.2`, `openai/gpt-5.4-mini`; also used for image generation (`gpt-image-2`), PDF processing (`gpt-5.4-mini`), and audio transcription (`gpt-4o-transcribe-mini`)
  - Auth: `OPENAI_API_KEY` (env, injected into gateway container via `docker/docker-compose.yml`)
- Anthropic — available to the gateway/agents (Claude models)
  - Auth: `ANTHROPIC_API_KEY` (env)
- OpenRouter — fallback provider for image generation and PDF model (`openrouter/openrouter/auto`)
  - Auth: `OPENROUTER_API_KEY` (env)

**Search:**
- Brave Search API — provided as an env var to the gateway, presumably backing a search skill
  - Auth: `BRAVE_API_KEY` (env)

**Messaging / Bot Channel:**
- Telegram Bot API — the primary user-facing channel for the OpenClaw agent (`channels.telegram` in `config/openclaw.json`)
  - Auth: `TELEGRAM_BOT_TOKEN` (env); DM allowlist keyed off `TELEGRAM_USER_ID`
  - Policy: `dmPolicy: allowlist`, `groupPolicy: disabled`, `streaming: partial`

**Source Control / Dev Tooling:**
- GitHub CLI (`gh`) — installed in the gateway image for a "github" skill
  - Auth: `GH_TOKEN` (env)
- Git remotes — used both by the `agent-browser`/GSD tooling and by the `workspace-sync` sidecar for syncing the agent's workspace directory

**Skill Marketplace:**
- ClawHub — package registry/CLI for OpenClaw skills; skills declared in `config/skills-manifest.txt` (currently just `agent-browser`) are installed automatically by `docker/entrypoint.sh` on container start via `clawhub install <skill> --workdir <workspace>`

**Automation / Integration Platform:**
- Composio — connected via MCP (Model Context Protocol), configured under `mcpServers.composio` in `config/openclaw.json`
  - Transport: HTTP
  - URL: `${COMPOSIO_MCP_URL}` (env)
  - Auth header: `x-consumer-api-key: ${COMPOSIO_API_KEY}` (env)

## Data Storage

**Databases:**
- None detected. No database client libraries, connection strings, or ORM configuration found anywhere in the repo.

**File Storage:**
- Local filesystem only, via Docker volume mounts:
  - `${OPENCLAW_CONFIG_DIR:-/home/openclaw/.openclaw}` → `/home/node/.openclaw` (gateway config/state)
  - `${OPENCLAW_WORKSPACE_DIR:-/home/openclaw/.openclaw/workspace}` → `/home/node/.openclaw/workspace` (agent working directory)
  - The same workspace volume is shared read/write with the `workspace-sync` sidecar container

**Caching:**
- None detected.

## Authentication & Identity

**Gateway auth:**
- `OPENCLAW_GATEWAY_TOKEN` (env) — token used to authenticate access to the OpenClaw gateway's control UI/API (`gateway.controlUi.allowedOrigins` restricted to `http://localhost:18789`; gateway bound to `127.0.0.1:18789` only, i.e. not exposed externally by default)

**Channel-level allowlisting:**
- Telegram DM access restricted to `tg:${TELEGRAM_USER_ID}` (`config/openclaw.json` → `commands.allowFrom.telegram`, `channels.telegram.allowFrom`)

**No traditional user auth/identity provider** (no OAuth, no session store, no user database) — this is a single-operator gateway, not a multi-tenant app.

## Monitoring & Observability

**Error Tracking:**
- None detected (no Sentry/Bugsnag/etc. integration found).

**Logs:**
- OpenClaw gateway logging configured directly in `config/openclaw.json`: `logging.level: "info"`, `logging.consoleLevel: "info"`, `logging.redactSensitive: "tools"` (redacts sensitive data from tool-call logs)
- No external log aggregation service configured.

## CI/CD & Deployment

**Hosting:**
- Self-hosted Docker host (referred to as "VPS" in `config/skills-manifest.txt` comments) running `docker compose` with services `openclaw-gateway` and (optionally, via the `sync` profile) `workspace-sync`

**CI Pipeline:**
- No `.github/workflows/` directory or other CI config detected. Build/push is manual via `scripts/build-and-push.sh`, which:
  1. Validates `config/openclaw.json` (`scripts/validate-config.sh`)
  2. Scans tracked files for leaked secrets (`scripts/check-secrets.sh`)
  3. Builds and pushes `linux/amd64` images for both `openclaw-gateway` (`docker/Dockerfile`) and `workspace-sync` (`docker/workspace-sync/Dockerfile`) to GHCR, tagged with both a version tag (default `latest`) and the short git SHA

**Container Registry:**
- GitHub Container Registry (GHCR) — `ghcr.io/${GHCR_USERNAME}/openclaw-docker-config/{openclaw-gateway,workspace-sync}`

## Environment Configuration

**Required env vars (gateway service, `docker/docker-compose.yml`):**
- `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` (required, no default), `OPENROUTER_API_KEY`, `BRAVE_API_KEY`, `GH_TOKEN`
- `OPENCLAW_GATEWAY_TOKEN`
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_USER_ID`
- `COMPOSIO_API_KEY`, `COMPOSIO_MCP_URL`
- `GHCR_USERNAME` (build/push only, not container runtime)

**Required env vars (workspace-sync service):**
- `GIT_WORKSPACE_REPO`, `GIT_WORKSPACE_REMOTE`, `GIT_WORKSPACE_BRANCH` (default `auto`), `GIT_WORKSPACE_TOKEN`, `GIT_WORKSPACE_SYNC_SCHEDULE` (default `0 4 * * *`, cron-style)

**Secrets location:**
- `docker/.env` (gitignored; not read per forbidden-files policy) — populated from `docker/.env.example` template
- `.gitignore` also excludes `*.key`, `*.pem`, `credentials/`, `sessions/`
- Secret-leak prevention enforced pre-build via `scripts/check-secrets.sh` and `scripts/validate-config.sh`, and locally via hooks under `.githooks/`

## Webhooks & Callbacks

**Incoming:**
- Telegram Bot API delivers messages to the OpenClaw gateway (long-poll or webhook depending on OpenClaw internals — not configured explicitly here beyond `channels.telegram`)
- Composio MCP server (outbound HTTP connection initiated by the gateway, not an inbound webhook)

**Outgoing:**
- None explicitly configured beyond the LLM provider API calls and the Composio MCP HTTP transport described above.

---

*Integration audit: 2026-08-21*
