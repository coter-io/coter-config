# Tasks

## 1. Environment file and contract

- [x] 1.1 Add the local state directory to `.gitignore` and verify that creating a file beneath it leaves `git status --porcelain` empty
- [x] 1.2 Add `scripts/check-env-file.sh`, which compares the keys set in a given env file against the names `docker/.env.example` declares, treating a variable `docker/docker-compose.yml` interpolates without a default as required (failure) and an undeclared name as a warning; verify it names the variable when run against a scratch copy with a required key removed, and names the stray key when run against a copy with a bogus one added
- [x] 1.3 Create the root `.env` by carrying `docker/.env`'s values over, renaming `BRAVE_SEARCH_API_KEY` to `BRAVE_API_KEY`, and filling in `OPENROUTER_API_KEY`, `TELEGRAM_USER_ID`, `COMPOSIO_API_KEY` and `COMPOSIO_MCP_URL`; verify `scripts/check-env-file.sh .env` passes and `git status --porcelain` does not list `.env`
- [x] 1.4 Delete `docker/.env`, re-point the three tracked files that named it (`CONTRIBUTING.md`, `scripts/build-and-push.sh`, the `:?` message in `docker/docker-compose.yml`) at the root `.env`, and verify no remaining reference misdirects a reader — the only non-`.env.example` match left outside `openspec/` is `.github/workflows/validate-config.yml`, which deliberately creates an empty one in CI — and that `scripts/check-env-vars.sh` still passes
- [x] 1.5 State in `scripts/check-env-vars.sh`'s header comment that its compose scan covers the deployment compose file only, and that a local-only override file is deliberately outside the contract; verify `scripts/check-env-vars.sh` still passes

## 2. Local compose override

- [x] 2.1 Add `docker/docker-compose.local.yml` supplying the build stanza (repo root as context, `docker/Dockerfile` as dockerfile), `env_file` pointing at the root `.env`, host paths for `OPENCLAW_CONFIG_DIR` and `OPENCLAW_WORKSPACE_DIR` under the local state directory, and a `GHCR_USERNAME` default; verify `docker compose --project-directory . --env-file .env -f docker/docker-compose.yml -f docker/docker-compose.local.yml config` resolves with no required-variable error and renders the expected build context and mount paths
- [x] 2.2 Verify the deployment file is unaffected in isolation: `docker compose -f docker/docker-compose.yml config` still reports `GHCR_USERNAME` as required and renders no build stanza
- [x] 2.3 Verify the root `.env` is the only environment source: a variable set only in the root `.env` appears in the rendered local config, and the rendered config references no `docker/.env`
- [x] 2.4 Verify `workspace-sync` is not started by the local override: the rendered local config leaves it behind its `sync` profile

## 3. Bring-up script

- [x] 3.1 Add `local.sh` in the project root with preflight: container runtime reachable, root `.env` present (otherwise seeded from `docker/.env.example` with instructions to fill it in), and `scripts/check-env-file.sh` passing; verify each failure path names the defect and leaves no image built and no container running
- [x] 3.2 Implement the configuration copy step into the local config directory, run on every bring-up; verify the running container's `/home/node/.openclaw/openclaw.json` matches the repository's copy, and that editing the repository's copy and restarting replaces the local one
- [x] 3.3 Implement `up` — build, start, and follow logs under an explicit Compose project name, printing the project name and the bot token's leading characters before starting; verify invoking `./local.sh` with no arguments brings the gateway up, prints that banner first, and streams logs
- [x] 3.4 Implement `down`, `logs`, `shell` and `reset`; verify `reset` discards the local state directory and that the next `up` recreates it and reaches a running gateway
- [x] 3.5 Implement the validation subcommand delegating to `scripts/validate-config.sh`; verify it runs that script and that a timed `up` does not invoke it
- [x] 3.6 Document the local workflow in `README.md` beside the existing config and image workflows, stating the second-bot prerequisite, real `OPENROUTER_API_KEY` spend including per-second audio billing, live tool access through `mcp.servers.composio` and its consequences, and that the locally built image is native-architecture and not deployable; verify every command in the new section runs as written

## 4. End-to-end verification

- [x] 4.1 From a clean checkout with a filled `.env`, run `./local.sh` and verify the gateway reaches a healthy state and a DM to the second Telegram bot gets a reply routed through OpenRouter, per the logs
- [x] 4.2 Send a voice note and verify the transcription slot handles it and the agent responds to the transcript
- [x] 4.3 Restart and verify idempotence: the manifest's skills are not reinstalled, session state written under the configuration directory survives, and the repository's configuration is re-applied
  - Session state survived a full `down`/`up`: all 10 files under `state/` and `agents/` persisted, `openclaw.sqlite` (3.3 MB) intact, `database integrity verification passed` on the next start. The only entry that disappeared was `openclaw.sqlite.cron-authority.lock`, a lock released at shutdown rather than session state.
  - The repository's configuration was re-applied: md5 of `.local/openclaw/openclaw.json` matched `config/openclaw.json` after the restart, discarding the runtime writes the gateway had made to its own config (an emoji, a theme, an avatar and a `meta.migrations` block) — the overwrite semantics `design.md` specifies.
  - **The skills clause was verified by mechanism, not against the shipped manifest.** `agent-browser` is an ambiguous ClawHub slug, so it never installs and the entrypoint retries it on every start; there is nothing installed for the skip to skip. Placing a directory at `.local/workspace/skills/agent-browser` made the next start print `✓ agent-browser (already installed)` with no network call, which confirms `docker/entrypoint.sh`'s guard works as written. A real install-then-skip cycle can only be observed once the slug is pinned — see the manifest finding below.
- [x] 4.4 Verify isolation: no `workspace-sync` container ran, no registry authentication was required or performed, nothing was pushed to any git remote, and `git status --porcelain` lists no local state after a full session

## Workflow follow-up

- Archive the change once the end-to-end verification above has been run against a real second bot.

### Findings in shipped artifacts, out of scope here

- `config/skills-manifest.txt` lists a bare `agent-browser`, which is ambiguous on ClawHub (five owners publish that slug). `docker/entrypoint.sh` warns and continues, so the skill never installs and the install is retried on every start. This makes task 4.3's "the manifest's skills are not reinstalled" unverifiable as written — there is nothing installed to skip. Fix by pinning an owner (`@<owner>/agent-browser`) in a separate change; the shipped manifest is deliberately unmodified here.
- `OPENCLAW_CONFIG_DIR` and `OPENCLAW_WORKSPACE_DIR` are host-side bind-mount sources in `docker/docker-compose.yml`, but that file also carries `env_file: .env`, so whatever an operator sets for them is injected into the container, where the gateway honours them as its own writable state directory. `docker/.env.example` declares both with VPS values, so an operator who fills in the documented file gets a container whose state directory is `/home/openclaw/.openclaw` — unwritable, since `/home` is root-owned and the process is uid 1000. Every message then dead-letters with `EACCES: permission denied, mkdir '/home/openclaw'`. Neutralised locally in `docker/docker-compose.local.yml` (an `environment:` entry beats `env_file`); the deployment is only safe while its env file omits both keys, which is worth fixing in `docker/docker-compose.yml` as its own change.
