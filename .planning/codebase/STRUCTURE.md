# Codebase Structure

**Analysis Date:** 2026-08-21

## Directory Layout

```
coter-config/
├── config/                       # OpenClaw runtime config (pushed to VPS via SCP, no rebuild needed)
│   ├── openclaw.json             #   Gateway/channel/agent/model/MCP config (env-var refs only, no secrets)
│   ├── skills-manifest.txt       #   List of ClawHub skills auto-installed on container start
│   └── security-rules.md         #   Documents the secret-handling rules the scripts enforce
├── docker/                       # Container packaging
│   ├── Dockerfile                #   OpenClaw gateway image (Node 22, gh CLI, chromium, tini, openclaw+clawhub npm globals)
│   ├── docker-compose.yml        #   `openclaw-gateway` service + `workspace-sync` sidecar (profile: sync)
│   ├── entrypoint.sh             #   Seeds workspace-templates, installs skills from manifest, execs CMD
│   ├── .env / .env.example       #   Real secrets (gitignored) / checked-in template of required env vars
│   └── workspace-sync/           #   Separate sidecar image: cron-backs-up the OpenClaw workspace to a git remote
│       ├── Dockerfile
│       ├── entrypoint.sh
│       ├── workspace-sync.sh
│       └── git-askpass.sh        #   Injects git token via GIT_ASKPASS, avoids persisting to .git/config
├── scripts/                      # Developer-run shell tooling (not run inside containers)
│   ├── build-and-push.sh         #   Validate → scan secrets → buildx build+push both images to GHCR
│   ├── validate-config.sh        #   JSON validity + raw-API-key-pattern check on config/openclaw.json
│   └── check-secrets.sh          #   Regex scan of all git-tracked files (excl. .env.example, *.md) for leaked secrets
├── workspace-templates/          # Files seeded into a fresh OpenClaw workspace volume on first boot (currently empty, .gitkeep only)
├── .claude/                      # GSD tooling for Claude Code runtime (canonical source of gsd-core content)
│   ├── commands/gsd-*.md         #   Slash-command entry points (one file per /gsd-<name> command)
│   ├── agents/gsd-*.md           #   Subagent persona definitions (planner, executor, verifier, mapper, etc.)
│   ├── hooks/*.js, *.sh          #   Lifecycle hooks: pre/post tool, session start/stop, subagent boundaries, guards
│   ├── scripts/                  #   Claude-runtime-specific build/gen scripts (capability registry, slash-command fixups)
│   ├── gsd-core/                 #   Canonical GSD engine content (see below)
│   ├── gsd-file-manifest.json    #   Tracks which files belong to this GSD install (for update/uninstall)
│   ├── gsd-install-state.json    #   Tracks installed GSD version/state for this runtime
│   └── settings.local.json       #   Claude Code local settings (permissions, hooks wiring)
├── .codex/                       # GSD tooling mirrored for Codex CLI runtime
│   ├── agents/gsd-*.md + .toml   #   Same personas as .claude/agents, plus Codex-specific .toml invocation wrappers
│   └── (mirrors .claude/ structure: gsd-core/, gsd-file-manifest.json, gsd-install-state.json, .gsd-profile, .gsd-staging)
├── .cursor/                      # GSD tooling mirrored for Cursor runtime
│   ├── skills/gsd-*/             #   Workflows exposed as Cursor "skills" (one directory per /gsd-<name>)
│   ├── agents/gsd-*.md           #   Same personas as .claude/agents
│   ├── hooks/, hooks.json        #   Cursor-specific hook wiring
│   └── (mirrors gsd-core/, gsd-file-manifest.json, gsd-install-state.json)
├── .planning/                    # This repo's own GSD working state (populated when GSD is run against this repo)
│   └── codebase/                 #   Generated codebase-analysis docs (this document and its siblings)
├── README.md                     # Primary operator doc: deploy workflow, skill-adding guide, workspace git sync setup
├── CONTRIBUTING.md, CODE_OF_CONDUCT.md, LICENSE
```

## Directory Purposes

**`config/`:**
- Purpose: Source of truth for OpenClaw's runtime behavior, deployed by SCP (no image rebuild).
- Contains: one JSON config file, one plaintext skill manifest, one markdown security-rules doc.
- Key files: `config/openclaw.json`, `config/skills-manifest.txt`, `config/security-rules.md`.

**`docker/`:**
- Purpose: Everything needed to build and run the two container images (gateway, workspace-sync) and their compose stack.
- Contains: two `Dockerfile`s, one `docker-compose.yml`, entrypoint/shell scripts, `.env`/`.env.example`.
- Key files: `docker/Dockerfile`, `docker/docker-compose.yml`, `docker/entrypoint.sh`, `docker/workspace-sync/*`.

**`scripts/`:**
- Purpose: Developer-invoked (laptop-side) shell tooling for validating config and publishing images. Never copied into the container image itself (except indirectly — `validate-config.sh`/`check-secrets.sh` are called by `build-and-push.sh` pre-build, not baked in).
- Contains: three `.sh` scripts.
- Key files: `scripts/build-and-push.sh`, `scripts/validate-config.sh`, `scripts/check-secrets.sh`.

**`workspace-templates/`:**
- Purpose: Seed content for a new OpenClaw workspace volume; copied in with `cp -rn` (no-clobber) by `docker/entrypoint.sh`.
- Contains: currently only `.gitkeep` — empty placeholder, intended to be populated with default workspace files as needed.

**`.claude/`, `.codex/`, `.cursor/` (GSD tooling, one per agent runtime):**
- Purpose: Provide the "GSD" structured software-delivery workflow (spec → plan → execute → verify → ship, plus many auxiliary flows) to whichever AI coding agent CLI is active.
- Contains: runtime-specific entry-point format (`commands/*.md` for Claude, `skills/*/` for Cursor, `.md`+`.toml` pairs for Codex agents), plus a near-identical `gsd-core/` payload in each.
- Key files: `.claude/gsd-core/bin/gsd-tools.cjs` (canonical CLI), `.claude/gsd-core/workflows/*.md` (workflow specs), `.claude/gsd-core/references/*.md` (on-demand context), `.claude/gsd-core/templates/*.md` (output templates), `.claude/agents/*.md` (subagent personas).

**`.claude/gsd-core/bin/lib/`:**
- Purpose: Deterministic Node.js implementation of GSD mechanics (state, phase/roadmap lifecycle, git integration, capability system, config, health checks, workstreams, etc.) — one `.cjs` module per concern, often paired with a `*-command-router.cjs`.
- Contains: ~200 `.cjs` files, plus subdirectories `health-diagnostic-rules/`, `host-integration-adapters/`, `installer-migrations/`, `observability/`, `vendor/`.

**`.claude/gsd-core/workflows/`:**
- Purpose: Markdown step-by-step procedure definitions that slash commands dispatch into.
- Contains: one `.md` per workflow (e.g. `execute-phase.md`, `plan-phase.md`, `map-codebase.md`); larger workflows additionally have a same-named directory holding a `steps/` subdirectory (e.g. `execute-phase/steps/`, `plan-phase/steps/`).

**`.planning/`:**
- Purpose: Working state when GSD workflows are run against this repository itself.
- Contains: `codebase/` (generated architecture/structure/stack/etc. docs); other GSD artifact subdirectories are created as workflows are used (phases, specs, plans).
- Generated: Yes (by GSD agents).
- Committed: Not verified either way in this pass — treat as repo-tracked working state unless gitignored.

## Key File Locations

**Entry Points:**
- `docker/Dockerfile` + `docker/entrypoint.sh`: container boot sequence for the OpenClaw gateway.
- `docker/docker-compose.yml`: declares services, ports (`127.0.0.1:18789`), volumes, and the sync sidecar profile.
- `scripts/build-and-push.sh`: developer-invoked image publish pipeline.
- `.claude/commands/gsd-*.md` / `.cursor/skills/gsd-*/`: agent-invoked slash-command entry points into GSD workflows.
- `.claude/gsd-core/bin/gsd_run` / `.claude/gsd-core/bin/gsd-tools.cjs`: GSD CLI entry point shelled out to from workflow steps.

**Configuration:**
- `config/openclaw.json`: gateway/agent/model/channel/MCP runtime config.
- `config/skills-manifest.txt`: skill install list.
- `docker/.env.example`: template of required environment variables (`docker/.env` holds real values, gitignored).

**Core Logic:**
- `.claude/gsd-core/bin/lib/*.cjs`: deterministic GSD mechanics (state, phase, roadmap, git, capability system, etc.).
- `.claude/gsd-core/workflows/*.md` (+ `steps/` subdirs): workflow procedure definitions.
- `.claude/agents/*.md`: subagent persona definitions.

**Testing:**
- Not applicable — no application test suite exists in this repo; validation is via `scripts/validate-config.sh` and `scripts/check-secrets.sh` (config/secret linting, not unit tests). No `jest.config.*`/`vitest.config.*` or `*.test.*`/`*.spec.*` files were found.

## Naming Conventions

**Files:**
- GSD commands/workflows/agents/templates: `gsd-<kebab-case-name>.md` (e.g. `gsd-execute-phase.md`, `gsd-planner.md`).
- GSD `bin/lib` modules: `<kebab-case-concern>.cjs`, frequently paired as `<concern>.cjs` + `<concern>-command-router.cjs`.
- Shell scripts: `<kebab-case-verb-noun>.sh` (e.g. `build-and-push.sh`, `validate-config.sh`, `check-secrets.sh`).
- Codex agent pairs: identical basename with both `.md` (prompt) and `.toml` (invocation metadata) extensions (e.g. `gsd-executor.md` + `gsd-executor.toml`).

**Directories:**
- Per-agent-runtime top-level dot-directories: `.claude/`, `.codex/`, `.cursor/` — each mirrors the same internal layout (`agents/`, `hooks/`, `gsd-core/`, `gsd-file-manifest.json`, `gsd-install-state.json`, `.gsd-profile`, `.gsd-staging/`).
- Workflow step subdirectories: `<workflow-name>/steps/` (e.g. `execute-phase/steps/`) for workflows too large for a single file.
- Reference/template categorization by suffix or subfolder rather than strict taxonomy (e.g. `references/debugger-*.md` cluster, `templates/codebase/*.md` cluster, `references/edge-probe-fixtures/*` fixture data).

## Where to Add New Code

**New OpenClaw skill:**
- Add the ClawHub skill name to `config/skills-manifest.txt` (auto-installed at container boot), or scaffold a custom skill under a `skills/` directory pushed to the VPS (see README's "Custom Skills" section) — not committed to this repo's tree directly, per the documented workflow.

**New Docker/image behavior:**
- Edit `docker/Dockerfile` for build-time binaries/packages; edit `docker/entrypoint.sh` for boot-time behavior. Rebuild via `bash scripts/build-and-push.sh`.

**New OpenClaw runtime config:**
- Edit `config/openclaw.json`; validate with `bash scripts/validate-config.sh` before committing.

**New GSD slash command:**
- Add `.claude/commands/gsd-<name>.md` (entry point) + `.claude/gsd-core/workflows/<name>.md` (procedure) as the canonical pair; then mirror into `.codex/` (add `.toml` wrapper) and `.cursor/skills/gsd-<name>/`. Reuse existing `references/*.md` where possible instead of inlining context.

**New GSD subagent:**
- Add `.claude/agents/gsd-<name>.md`; mirror to `.codex/agents/gsd-<name>.md` + matching `.toml`, and reference it from `.cursor/agents/` if the Cursor runtime dispatches subagents there too.

**New deterministic GSD logic:**
- Add a module to `.claude/gsd-core/bin/lib/<concern>.cjs`; if it needs a CLI surface, pair it with `<concern>-command-router.cjs` and wire it into `gsd-tools.cjs`'s router table.

**Utilities:**
- Shared shell logic for deploy scripts: keep in `scripts/` following the existing `set -euo pipefail` + `REPO_ROOT` resolution pattern used by all three existing scripts.
- Shared GSD Node helpers: `.claude/gsd-core/bin/lib/core-utils.cjs`, `io.cjs`, `text-lines.cjs`.

## Special Directories

**`docker/workspace-sync/`:**
- Purpose: A second, independent Docker image/service (not part of the main gateway image) that syncs the OpenClaw workspace volume to a git remote on a cron schedule.
- Generated: No (hand-authored source).
- Committed: Yes.

**`.gsd-staging/user-artifacts/` (under each of `.claude/`, `.codex/`, `.cursor/`):**
- Purpose: Staging area for user-provided artifacts consumed by GSD workflows during import/onboarding.
- Generated: Partially — directory structure is part of the install, contents accumulate at runtime.
- Committed: Unclear — treat as runtime scratch space, verify `.gitignore` before adding files here.

**`gsd-file-manifest.json` / `gsd-install-state.json` (per runtime dir):**
- Purpose: Track which files belong to the installed GSD payload and its version state, enabling update/uninstall/migration tooling (`.claude/gsd-core/workflows/update.md`, `bin/lib/installer-migrations.cjs`) to reconcile each runtime independently.
- Generated: Yes, by the GSD installer/updater.
- Committed: Yes (part of the tracked install state).

---

*Structure analysis: 2026-08-21*
</content>
