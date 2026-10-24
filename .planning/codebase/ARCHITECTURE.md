<!-- refreshed: 2026-08-21 -->
# Architecture

**Analysis Date:** 2026-08-21

## System Overview

This repository is a **configuration and packaging repo**, not an application. It has two largely independent subsystems that share the top-level directory:

1. **OpenClaw deployment config** — `config/`, `docker/`, `scripts/`, `workspace-templates/` — defines the Docker image, runtime config, and deploy scripts for an OpenClaw Telegram gateway running on a Hetzner VPS (deployed by a *companion* infra repo, not this one).
2. **GSD agent tooling** — `.claude/`, `.codex/`, `.cursor/` — a large, self-contained "GSD" (Get-Stuff-Done) workflow framework of slash commands, subagents, hooks, and a Node.js CLI (`gsd-tools.cjs`) that runs *inside* AI coding agent sessions (Claude Code, Codex, Cursor) operating on *other* projects' codebases. It is vendored per-agent-runtime under each dot-directory.

```text
┌─────────────────────────────────────────────────────────────────────┐
│                        Laptop (this repo, git)                       │
├────────────────────────────┬──────────────────────────────────────┤
│   OpenClaw deploy config    │   GSD agent tooling (per-runtime)     │
│  `config/openclaw.json`     │  `.claude/` `.codex/` `.cursor/`      │
│  `docker/Dockerfile`        │   commands + agents + hooks + core    │
│  `docker/docker-compose.yml`│  `.claude/gsd-core/bin/gsd-tools.cjs` │
│  `scripts/*.sh`             │  `.claude/gsd-core/workflows/*.md`    │
│  `workspace-templates/`     │  `.claude/gsd-core/references/*.md`  │
└──────────────┬───────────────┴───────────────────┬──────────────────┘
               │ scripts/build-and-push.sh          │ invoked by Claude/
               ▼                                    │ Codex/Cursor CLI at
┌──────────────────────────────┐                    │ session/command time
│   GHCR (container registry)  │                    ▼
│  openclaw-gateway:latest     │          ┌─────────────────────────┐
│  workspace-sync:latest       │          │  Agent runtime session   │
└──────────────┬────────────────┘          │  (this repo or any repo)│
               │ infra repo: make deploy    └─────────────────────────┘
               ▼
┌──────────────────────────────────────────────────────────────┐
│  Hetzner VPS (not this repo — infra repo owns provisioning)   │
│  ┌────────────────────┐   ┌───────────────────────────────┐ │
│  │ openclaw-gateway    │   │ workspace-sync (sidecar,       │ │
│  │ container           │   │ profile: sync, cron push)      │ │
│  │ :18789 (loopback)   │   │ backs up ~/.openclaw/workspace │ │
│  └────────────────────┘   └───────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| OpenClaw runtime config | Gateway/channel/agent/model/MCP config, pushed via SCP to the VPS | `config/openclaw.json` |
| Skills manifest | Declarative list of ClawHub skills auto-installed at container start | `config/skills-manifest.txt` |
| Security rules doc | Documents secret-handling rules enforced by scripts | `config/security-rules.md` |
| Gateway image | Builds the OpenClaw gateway container (Node 22, gh CLI, chromium, tini) | `docker/Dockerfile` |
| Container entrypoint | Seeds workspace templates, installs ClawHub skills, execs the real command | `docker/entrypoint.sh` |
| Compose stack | Declares `openclaw-gateway` service + optional `workspace-sync` sidecar (profile `sync`) | `docker/docker-compose.yml` |
| Workspace sync sidecar | Separate Docker image/service; cron-pushes the OpenClaw workspace volume to a git remote | `docker/workspace-sync/Dockerfile`, `docker/workspace-sync/workspace-sync.sh`, `docker/workspace-sync/entrypoint.sh`, `docker/workspace-sync/git-askpass.sh` |
| Build/push pipeline | Validates config, scans for secrets, builds+pushes both images to GHCR (multi-arch amd64) | `scripts/build-and-push.sh` |
| Config validator | Checks `openclaw.json` is valid JSON and free of raw API-key patterns | `scripts/validate-config.sh` |
| Secret scanner | Greps all git-tracked files (excluding `.env.example`, `*.md`) for leaked-secret patterns | `scripts/check-secrets.sh` |
| Workspace seed templates | Files copied into a fresh OpenClaw workspace on first container boot (no-clobber) | `workspace-templates/` |
| GSD slash commands (per runtime) | User-facing entry points (`/gsd-*`) that route to workflow definitions | `.claude/commands/*.md`, `.cursor/skills/gsd-*/`, `.codex/prompts/*` (mirrored) |
| GSD subagents | Specialized agent personas dispatched by workflows (planner, executor, verifier, researcher, etc.) | `.claude/agents/*.md` (+ `.toml` variants under `.codex/agents/`) |
| GSD workflow engine (core logic) | Markdown-defined step-by-step workflows the commands execute | `.claude/gsd-core/workflows/*.md` and per-workflow `steps/` subdirs |
| GSD CLI / library | Deterministic Node.js logic (state, git, phase, roadmap, capability, config, health, etc.) invoked by workflows via `gsd_run`/`gsd-tools.cjs` | `.claude/gsd-core/bin/gsd-tools.cjs`, `.claude/gsd-core/bin/gsd_run`, `.claude/gsd-core/bin/lib/*.cjs` |
| GSD reference docs | Shared behavioral/how-to references loaded into agent context on demand (budget-controlled) | `.claude/gsd-core/references/*.md` |
| GSD templates | Output document templates for phases, plans, specs, ADRs, codebase docs, etc. | `.claude/gsd-core/templates/*.md`, `.claude/gsd-core/templates/codebase/*.md` |
| Hooks | Runtime-specific lifecycle hooks (pre/post tool, session start/stop, subagent boundaries) enforcing isolation, write guards, statusline, workflow gating | `.claude/hooks/*.js`, `.cursor/hooks/*.js`, `.claude/hooks/*.sh` |
| Planning state (this repo's own GSD usage) | This repo's own `.planning/` directory, populated by running GSD commands against itself | `.planning/codebase/` (this doc), `.planning/*` |

## Pattern Overview

**Overall:** Two juxtaposed "configuration-as-code" trees with no shared runtime and no shared build step:
- The OpenClaw side is a classic **immutable-image + externalized-config** deployment pattern: Docker image is rebuilt only for binary/version changes; JSON/skill config is pushed separately via SCP with no rebuild.
- The GSD side is a **markdown-defined workflow engine with a thin deterministic CLI**: slash commands are prompt entry points that reference `.md` workflow specs; the workflow specs delegate deterministic bookkeeping (state files, git commits, phase numbering) to `gsd-tools.cjs`/`gsd_run`, keeping "judgment" (planning, verification, code review) in LLM-executed steps and "mechanics" (file I/O, git, state transitions) in Node.js.

**Key Characteristics:**
- No application source code, no build step for "the product" — the product IS the configuration/prompts.
- Multi-runtime duplication by design: the same GSD agent/skill/workflow content is vendored separately for Claude Code (`.claude/`), Codex (`.codex/`, with `.toml` agent wrappers alongside `.md`), and Cursor (`.cursor/`, workflows exposed as `skills/`) — each is a near-mirror of `gsd-core`.
- Secrets are never committed; they live in `docker/.env` (gitignored, `.env.example` is the checked-in template) and in the separate infra repo's `secrets/openclaw.env`.
- Deployment is push-based and asymmetric: this repo never runs the container; a companion infra repo (`openclaw-terraform-hetzner`) pulls the image and applies config to the actual VPS.

## Layers

**Deploy/config layer (`config/`, `docker/`, `scripts/`, `workspace-templates/`):**
- Purpose: Define and validate what runs on the VPS, and package it into container images.
- Location: repo root `config/`, `docker/`, `scripts/`, `workspace-templates/`
- Contains: JSON runtime config, Dockerfiles, shell scripts, seed files.
- Depends on: nothing internal; consumes env vars supplied externally (`docker/.env`, infra repo secrets).
- Used by: the infra repo's `make bootstrap` / `make push-config` / `make deploy` targets (external, not in this repo).

**GSD tooling layer (`.claude/`, `.codex/`, `.cursor/`):**
- Purpose: Provide the AI coding agent (whichever host CLI is active) with slash commands, subagents, hooks, and a deterministic CLI to run structured "GSD" software-delivery workflows (spec → plan → execute → verify → ship) against a target codebase.
- Location: `.claude/gsd-core/` is the canonical source; `.codex/gsd-core/` and `.cursor/gsd-core/` mirror it for their respective runtimes.
- Contains: `commands/` or `skills/` (entry points), `agents/` (subagent personas), `workflows/` (step-by-step `.md` procedures, many split into `steps/` subdirectories for larger workflows), `references/` (on-demand context docs), `templates/` (document templates), `bin/` (Node.js CLI + `lib/*.cjs` modules), `hooks/` (lifecycle enforcement scripts).
- Depends on: Node.js runtime (via `gsd_run`) for the `bin/lib` modules; markdown parsing conventions (frontmatter, section manifests) for workflows/templates.
- Used by: whichever agent host (Claude Code, Codex CLI, Cursor) is active in a session; hooks wire into that host's tool-call lifecycle.

**Project planning artifacts (`.planning/`):**
- Purpose: This repo's own working state when GSD commands are run against itself (e.g. this codebase-mapping task writes to `.planning/codebase/`).
- Location: `.planning/`
- Contains: `codebase/` (this document and siblings), phase/plan/spec artifacts as GSD is used.
- Depends on: GSD tooling layer to populate/read it.
- Used by: GSD workflows (`/gsd-plan-phase`, `/gsd-execute-phase`, etc.) when operating on this repo.

## Data Flow

### Primary Deploy Path (OpenClaw config → VPS)

1. Developer edits `config/openclaw.json`, `config/skills-manifest.txt`, or `docker/Dockerfile`.
2. `bash scripts/validate-config.sh` checks JSON validity and scans for raw API-key patterns (`config/openclaw.json`).
3. `bash scripts/check-secrets.sh` greps all git-tracked files for leaked-secret regexes (`scripts/check-secrets.sh`).
4. Commit + push to GitHub.
5. For image changes: `bash scripts/build-and-push.sh [tag]` — re-runs validation, then `docker buildx build --platform linux/amd64 --push` for both `docker/Dockerfile` (gateway) and `docker/workspace-sync/Dockerfile` (sync sidecar), tagging `latest` and the short git SHA.
6. From the companion infra repo (outside this repo): `make push-config` (SCPs `config/*` to `~/.openclaw/` on VPS) and/or `make deploy` (pulls new image from GHCR, restarts via `docker/docker-compose.yml`).

### Container Boot Path (inside the gateway image)

1. `tini` execs `docker/entrypoint.sh`.
2. Entrypoint copies `/opt/workspace-templates/*` into `/home/node/.openclaw/workspace/` with `cp -rn` (no-clobber) — sourced from `workspace-templates/` at build time (`docker/Dockerfile` `COPY`).
3. Entrypoint reads `/opt/config/skills-manifest.txt` line by line and runs `clawhub install <skill> --workdir <workspace>` for each, skipping already-installed skills.
4. Entrypoint `exec`s the compose-provided `command` (`openclaw gateway --bind lan --port 18789`).

### GSD Workflow Invocation Path (agent session)

1. User (or another agent) invokes a slash command, e.g. `/gsd-map-codebase` (`.claude/commands/gsd-map-codebase.md`).
2. The command markdown references a corresponding workflow spec under `.claude/gsd-core/workflows/` (e.g. `map-codebase.md`), which lays out ordered steps, gates, and references to load.
3. Steps that require deterministic logic shell out to `.claude/gsd-core/bin/gsd_run` / `gsd-tools.cjs`, which dispatches to a `lib/*-command-router.cjs` and then the relevant `lib/*.cjs` module (state, phase, roadmap, git, capability, etc.).
4. Steps that require judgment dispatch specialized subagents defined in `.claude/agents/*.md` (e.g. `gsd-codebase-mapper.md`, the agent type running the current mapping task), each with its own scoped instructions and tool access.
5. Hooks (`.claude/hooks/*.js`) intercept tool calls at various lifecycle points (pre-tool, post-tool, session start/stop, subagent start/stop) to enforce write guards, agent isolation, and state consistency.
6. Output artifacts are written to `.planning/` (or wherever the workflow specifies), not back into `.claude/`.

**State Management:**
- Deploy-side: state lives externally (GHCR tags, VPS filesystem, infra repo) — this repo is stateless config source.
- GSD-side: state is file-based, held in `.planning/` (state documents, phase manifests) and read/written through `bin/lib/state*.cjs`, `bin/lib/phase*.cjs`, `bin/lib/roadmap*.cjs` — no database, no server process.

## Key Abstractions

**Workflow (`.md` step spec):**
- Purpose: Declaratively define an ordered, gated procedure an agent follows (e.g. plan a phase, execute a phase, ship).
- Examples: `.claude/gsd-core/workflows/execute-phase.md` (+ `.claude/gsd-core/workflows/execute-phase/steps/`), `.claude/gsd-core/workflows/plan-phase.md`.
- Pattern: Markdown with embedded instructions, gate checkpoints, and references to `references/*.md`; large workflows split into a `steps/` subdirectory of numbered step files.

**Subagent (agent persona)**:
- Purpose: A narrowly scoped Claude/Codex/Cursor agent definition with its own system prompt, permitted tools, and role (planner, executor, verifier, code reviewer, codebase mapper, debugger, etc.).
- Examples: `.claude/agents/gsd-codebase-mapper.md`, `.claude/agents/gsd-executor.md`, `.claude/agents/gsd-planner.md`; mirrored as `.toml` + `.md` pairs under `.codex/agents/`.
- Pattern: One file per persona; Codex runtime additionally needs a `.toml` wrapper describing invocation metadata.

**Reference doc:**
- Purpose: On-demand context loaded into a workflow/agent's prompt only when relevant, to control context budget.
- Examples: `.claude/gsd-core/references/context-budget.md`, `.claude/gsd-core/references/mandatory-initial-read.md`, `.claude/gsd-core/references/verification-patterns.md`.
- Pattern: Small, focused markdown files; workflows explicitly `Read` the ones they need rather than loading everything.

**lib module (`bin/lib/*.cjs`):**
- Purpose: Single-responsibility Node.js module implementing one deterministic concern (e.g. `phase.cjs`, `roadmap.cjs`, `state.cjs`, `git-base-branch.cjs`, `capability-registry.cjs`).
- Examples: `.claude/gsd-core/bin/lib/state.cjs`, `.claude/gsd-core/bin/lib/phase-lifecycle.cjs`, `.claude/gsd-core/bin/lib/audit.cjs`.
- Pattern: CommonJS modules (note `commonjs-marker.cjs`), often paired with a `*-command-router.cjs` that exposes the module's operations as CLI subcommands.

**Template (`templates/*.md`):**
- Purpose: Fill-in-the-blank document skeletons for GSD-produced artifacts (specs, plans, ADRs, codebase docs).
- Examples: `.claude/gsd-core/templates/codebase/architecture.md` (the template this very document was generated from), `.claude/gsd-core/templates/spec.md`.

## Entry Points

**OpenClaw gateway container:**
- Location: `docker/Dockerfile` → `docker/entrypoint.sh`
- Triggers: `docker compose up` (via `docker/docker-compose.yml`, `command: openclaw gateway --bind lan --port 18789`)
- Responsibilities: seed workspace, install skills, launch the OpenClaw gateway process bound to `127.0.0.1:18789`.

**Workspace-sync sidecar:**
- Location: `docker/workspace-sync/entrypoint.sh` → `docker/workspace-sync/workspace-sync.sh`
- Triggers: compose `profile: sync` service start; internally cron-driven per `GIT_WORKSPACE_SYNC_SCHEDULE`.
- Responsibilities: periodically commit+push the OpenClaw workspace volume to a configured git remote using `git-askpass.sh` for inline token auth.

**Build/push pipeline:**
- Location: `scripts/build-and-push.sh`
- Triggers: manual invocation by a developer (`bash scripts/build-and-push.sh [tag]`).
- Responsibilities: validate config, scan secrets, `docker buildx build --push` both images (gateway + workspace-sync) to GHCR for `linux/amd64`.

**GSD slash commands:**
- Location: `.claude/commands/gsd-*.md` (Claude Code), `.cursor/skills/gsd-*/` (Cursor), Codex equivalents under `.codex/`.
- Triggers: user typing `/gsd-<name>` in an agent session, or another GSD workflow/command dispatching one internally.
- Responsibilities: kick off the corresponding workflow in `.claude/gsd-core/workflows/`.

**`gsd_run` / `gsd-tools.cjs` CLI:**
- Location: `.claude/gsd-core/bin/gsd_run`, `.claude/gsd-core/bin/gsd-tools.cjs`
- Triggers: invoked from within workflow steps (shelled out by the agent) or hooks.
- Responsibilities: deterministic operations — state transitions, phase/roadmap management, git operations, config/capability handling — routed through `bin/lib/*-command-router.cjs` files.

## Architectural Constraints

- **No shared process/runtime between the two subsystems:** the OpenClaw deploy config and the GSD tooling never call into each other; they coexist in the same git tree purely for repo-of-record convenience.
- **Multi-runtime triplication:** GSD content is manually mirrored across `.claude/`, `.codex/`, `.cursor/` (each with its own `gsd-core/`, `agents/`, `hooks/`); there is no single source directory that generates the others — `gsd-file-manifest.json` and `gsd-install-state.json` (present under each runtime dir) track installed-file state per runtime, implying an installer/updater mechanism (`.claude/gsd-core/workflows/update.md`, `.claude/gsd-core/bin/lib/installer-migrations.cjs`) rather than a build step.
- **Runtime-lost-on-restart for the container:** per `docker/Dockerfile` comment, any binary a skill needs must be baked into the image at build time — installing at container runtime does not persist.
- **Secrets boundary:** no secret values are ever meant to live in this repo; `docker/.env` is real but gitignored (only `.env.example` is tracked), and `scripts/check-secrets.sh` / `scripts/validate-config.sh` are the enforcement gates run before every image build (`scripts/build-and-push.sh` calls both first).
- **No test suite / no CI pipeline detected** in this repo for either subsystem — validation is manual via `scripts/validate-config.sh` and `scripts/check-secrets.sh`.

## Anti-Patterns

### Editing a runtime's vendored `gsd-core` copy directly without updating the others

**What happens:** A developer patches `.claude/gsd-core/workflows/foo.md` to fix a bug but leaves `.codex/gsd-core/workflows/foo.md` and `.cursor/gsd-core/workflows/foo.md` untouched.
**Why it's wrong:** The three runtime directories are expected to be kept in sync (each has matching `gsd-file-manifest.json`/`gsd-install-state.json`); drifting them silently breaks parity between Claude Code, Codex, and Cursor sessions.
**Do this instead:** Use the GSD update/install tooling (`.claude/gsd-core/workflows/update.md`, `.claude/gsd-core/bin/lib/installer-migrations.cjs`) rather than hand-editing individual runtime copies, or mirror the edit across all three when hand-editing is unavoidable.

### Committing populated `docker/.env`

**What happens:** Real secret values get written into `docker/.env` and accidentally staged.
**Why it's wrong:** `docker/.env` holds live API keys/tokens (Telegram, Anthropic, OpenAI, GHCR, Composio) — leaking it exposes production credentials; only `docker/.env.example` should ever be committed.
**Do this instead:** Keep secrets in `docker/.env` (gitignored) or the infra repo's `secrets/openclaw.env`; run `scripts/check-secrets.sh` before every commit/push (it's already gated into `scripts/build-and-push.sh`).

## Error Handling

**Strategy:** Shell scripts use `set -euo pipefail` and explicit `exit 1` with a printed `ERROR:` prefix on validation failure (`scripts/validate-config.sh`, `scripts/check-secrets.sh`, `scripts/build-and-push.sh`). Skill installation in `docker/entrypoint.sh` is deliberately non-fatal: a failed `clawhub install` prints a `WARNING:` and continues rather than aborting container boot.

**Patterns:**
- Fail-closed for config/secret validation (any detected issue stops the build).
- Fail-open for optional per-skill installation (one bad skill shouldn't block the gateway from starting).
- GSD Node.js CLI (`bin/lib/*.cjs`) centralizes CLI exit-code handling via `cli-exit.cjs`.

## Cross-Cutting Concerns

**Logging:** OpenClaw gateway logging level set via `config/openclaw.json` (`logging.level`, `logging.consoleLevel`, `logging.redactSensitive: "tools"` — redacts sensitive data in tool-call logs). Shell scripts log via plain `echo` with `[entrypoint]`/`==>` prefixes for traceability.

**Validation:** Two-stage gate before any image build/push — `scripts/validate-config.sh` (structural/pattern checks on `openclaw.json`) then `scripts/check-secrets.sh` (repo-wide tracked-file secret regex scan), both invoked automatically by `scripts/build-and-push.sh`.

**Authentication:** Telegram bot auth via `TELEGRAM_BOT_TOKEN`/`TELEGRAM_USER_ID` env vars (`config/openclaw.json` → `channels.telegram`), allowlist-based DM policy. GitHub auth for workspace-sync via `GIT_ASKPASS`-injected token (`docker/workspace-sync/git-askpass.sh`), never embedded in `.git/config` when using the GitHub-shorthand option. GHCR auth is a one-time `docker login` on the developer's laptop, external to this repo.

---

*Architecture analysis: 2026-08-21*
</content>
