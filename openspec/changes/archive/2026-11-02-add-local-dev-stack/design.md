# Design

## Context

See `proposal.md` — Why. The constraints that shape the approach, all verified against the current tree:

- **Configuration is delivered by copy, not by image or repo mount.** `docker/Dockerfile` bakes in `config/skills-manifest.txt` and `workspace-templates/`, but not `config/openclaw.json`. Compose mounts `${OPENCLAW_CONFIG_DIR}` at `/home/node/.openclaw`; on the VPS that host directory is populated by the infra repo's `make push-config`. There is no local equivalent.
- **The default directory values are VPS paths.** `OPENCLAW_CONFIG_DIR` defaults to `/home/openclaw/.openclaw`. Docker Desktop on macOS shares `/Users`, `/Volumes`, `/private` and `/tmp` only, so that path cannot be bind-mounted from a developer machine.
- **Relative paths in compose resolve against the project directory, not the compose file.** Measured against the renderer during implementation, correcting an earlier assumption in this document that `env_file: .env` necessarily means `docker/.env`. Because `local.sh` passes `--project-directory .` (the repo root), the service's inherited `env_file: .env` already resolves to the project-root `.env`, and no override is needed — an `../.env` override would resolve above the repo. The same rule governs `build.context` and bind-mount sources. `--env-file` at the CLI is still a separate mechanism, controlling only which file `${VAR}` interpolation reads, so both must name the same file.
- **`image:` carries a required variable, and an override cannot remove it.** `ghcr.io/${GHCR_USERNAME:?...}/...` aborts when `GHCR_USERNAME` is unset, independently of whether anything is pulled. Compose interpolates each file as it loads it, *before* merging, so replacing `image:` in the override does not suppress the guard — measured: the error names `services.workspace-sync.image`. `GHCR_USERNAME` therefore stays a required key in `.env`, which costs nothing since `docker/.env.example` already declares it.
- **The release build is cross-architecture.** `scripts/build-and-push.sh` passes `--platform linux/amd64` for the Hetzner host. The developer machine here is `arm64`.
- **Telegram permits one `getUpdates` consumer per bot token.** The config enables Telegram as the only channel, so two gateways sharing a token contend for the long poll.
- **Static validation already exists.** `scripts/validate-config.sh` runs `config validate` and `doctor --lint` in a container at the pinned version. It costs two container starts and two `npx -y openclaw@<version>` installs, which is roughly a minute or two of wall time.

## Goals / Non-Goals

**Goals:**
- One command from a clean checkout to a gateway a developer can hold a conversation with.
- Run the shipped artifacts unmodified — same `openclaw.json`, same `Dockerfile`, same `docker-compose.yml`.
- Deliver configuration locally with the same mechanism and the same overwrite semantics prod uses, so a local pass means something about a deploy.
- Keep local state on the host and inspectable, since reading what the agent actually wrote is most of why local testing is worth having.
- Fail before starting anything, with the defect named, when the environment is not fit.

**Non-Goals:**
- Reproducing the VPS as an environment. The architecture differs, and that is accepted.
- Testing the `workspace-sync` sidecar or the infra repo's deploy path.
- Replacing `validate-config.sh` or the PR gate. This is a runtime complement to checks that already pass.
- Supporting the multi-agent recipe commented out in `docker-compose.yml`.

## Decisions

### A separate local override file, applied explicitly

`docker/docker-compose.local.yml`, passed as a second `-f` by `local.sh`.

Alternatives: `docker-compose.override.yml`, which Compose auto-loads — rejected because an auto-applied file is the wrong default for something that must never influence a deploy, and the infra repo's `make bootstrap` copies a file out of this directory. Adding `build:` to `docker/docker-compose.yml` — rejected because the VPS has no build context (the repo is not cloned there), so a `build:` stanza would break `make deploy`. A standalone local compose file duplicating all services — rejected because it drifts from prod silently; layered overrides inherit prod's service definitions and only state deltas.

The override supplies: `build:` with the repo root as context and `docker/Dockerfile` as the dockerfile, a local image tag so nothing is pulled or pushed, and bind-mount sources under the local state directory. It deliberately supplies no `env_file` and no `GHCR_USERNAME` default — see the two corrected Context bullets above for why neither works as this document first assumed.

### Configuration is copied into local state, not mounted read-only

`local.sh` copies `config/*` into the local config directory on every `up`, and the override bind-mounts that directory.

The tidier-looking alternative — bind-mounting `config/openclaw.json` read-only at `/home/node/.openclaw/openclaw.json` — is rejected because it diverges from prod in a way that can only fail locally. On the VPS that file is an ordinary writable file; anything the gateway writes to its own configuration would succeed there and fail under an `:ro` mount. The copy keeps the file writable and reproduces `make push-config`'s overwrite semantics exactly, including that a repo edit wins over whatever is in the local directory.

### Local state is a bind-mounted, gitignored directory inside the repo

A single parent directory holding the config directory and the workspace directory, both bind-mounted.

Named volumes were considered and rejected: inspecting the workspace is a primary use (what the agent wrote, which skills `clawhub install` landed), and a bind mount makes that a plain `ls`. Mounting the developer's real `~/.openclaw` was rejected because it would entangle local test state with any host-level OpenClaw install.

Persistence matters for more than inspection: `docker/entrypoint.sh` runs `clawhub install` for every manifest entry on each start and skips entries already present in the workspace, so a persisted workspace turns repeat starts from a network round-trip into a no-op. A `reset` subcommand exists to discard this state deliberately.

Both mounts are nested (`/home/node/.openclaw` and `/home/node/.openclaw/workspace`), which is how `docker-compose.yml` already declares them; Docker orders mounts by path depth, so the nesting is sound.

### The root `.env` is the only environment source

`local.sh` passes `--env-file .env` with `--project-directory .`, and the override restates `env_file` relative to the compose file. `docker/.env` is deleted rather than left as a stale second source — in its current state it would fail to start the stack anyway.

`docker/.env.example` stays where it is. `scripts/check-env-vars.sh` reads it by path, and the `deployment-env-contract` spec names that path in four requirements; moving it would be a larger change than this one.

### Preflight fails closed, in cheap-first order

`up` refuses to proceed, naming the defect, when: Docker is not running; `.env` is absent (it is seeded from `docker/.env.example` and the developer is told to fill it, rather than being started with empty credentials); or the `.env` key set does not satisfy `docker/.env.example`. Missing keys fail. Keys present in `.env` but undeclared in the example are reported as warnings, since that is the shape the `BRAVE_SEARCH_API_KEY` drift took — a name that looks plausible and reaches nothing.

The key comparison is a new script under `scripts/` rather than inline shell, matching how this repo already factors its checks and so the same comparison can be reused by a hook later.

`validate-config.sh` is **not** run by `up`. It costs a minute or two of container and `npx` work, the pre-commit hook and PR gate already run it, and the cost falls on exactly the inner loop this change exists to shorten. It is reachable as its own subcommand.

### Native-architecture build

No `--platform` in the override; the image builds for the developer's architecture.

Building `linux/amd64` under emulation was rejected: the image installs chromium, the GitHub CLI and two global npm packages, which is slow and unreliable under QEMU. Pulling the published amd64 image was rejected as the default because it cannot test a `Dockerfile` edit, which is a thing this loop needs to cover (adding a binary for a new skill is a documented workflow). The trade-off is explicit: the local image is not the artifact prod runs, and an architecture-specific defect will not be caught here. `scripts/build-and-push.sh` remains the only producer of the deployable image.

### A shell script with subcommands, not a Makefile

`local.sh` in the project root, as requested, with `up`, `down`, `logs`, `shell`, `reset`, and a subcommand for the full static validation. A bare `local.sh` is `up`.

A root `Makefile` would echo the infra repo's interface, but every check in this repo is a script under `scripts/`, and `local.sh` is mostly a preflight sequence plus one long `docker compose` invocation — which is the thing being encapsulated. The script sets an explicit Compose project name so the local stack cannot collide with another project's containers.

### Isolation from the deployed stack is asserted, not verified

The local stack gets its own gateway token, its own bot token and its own state directory. `local.sh` cannot verify that the bot token differs from the deployed one — the infra repo's `secrets/openclaw.env` does not exist on this machine, only its example — so there is nothing to compare against. Instead `up` prints the bot token's leading characters and the Compose project name before starting, so polling with the wrong bot is visible in the first lines of output rather than inferred later from 409s.

`allowFrom` is `["tg:${TELEGRAM_USER_ID}"]`, and the same human runs both bots, so the shipped config needs no change to accept DMs to a second bot — only a different `TELEGRAM_BOT_TOKEN` value.

`workspace-sync` is left behind its `sync` profile and is not referenced by the override, so no local run can push a test workspace to a real remote.

## Risks / Trade-offs

**Shared bot token degrades the deployed bot** → Two gateways on one token contend for `getUpdates`; traffic splits non-deterministically and the deployed bot drops messages. Cannot be detected automatically (above), so: a second BotFather bot is a prerequisite, and `up` prints the token prefix it is about to poll with.

**The local agent has live tool access** → `mcp.servers.composio` is wired with a real URL and key, both required by compose, and the gateway rejects its config without a well-formed URL. A local agent can therefore act for real on whatever that Composio server has connected. This is an operator decision the design does not force, because it is a `.env` value either way: reuse the deployed credentials and accept real side effects, or point `COMPOSIO_MCP_URL` and `COMPOSIO_API_KEY` at a second Composio server with a narrower set of connections. The README section should state the consequence rather than leave it implicit.

**Real spend** → Every local conversation bills `OPENROUTER_API_KEY`, and voice notes bill per second of audio on the transcription slot rather than per token. The default model is the cheapest in the routing table, so ordinary testing is inexpensive; `/model sonnet` is not.

**Architecture divergence** → The local image is native-arch, so an amd64-only defect passes locally and fails on the VPS. Accepted deliberately; mitigated by `validate-config.sh` and the PR gate being architecture-independent, and by the deployable image having exactly one producer.

**Agent-written files inside the repo tree** → The workspace bind mount puts agent output under the checkout, where it could be committed. Mitigated by gitignoring the state directory; `scripts/check-secrets.sh` scans tracked files only, so untracked state is outside its reach and must not become tracked.

**Config copy discards runtime writes to `openclaw.json`** → Re-copying on every `up` means anything the gateway wrote into that file is lost. This matches `make push-config` on the VPS, so it is the same semantics prod has, not a new hazard. Credentials and session state live elsewhere under `~/.openclaw` and are untouched, because only `config/*` is copied.

**Local overrides escape the environment-variable gate** → `scripts/check-env-vars.sh` scans `docker/docker-compose.yml` only, so a variable introduced by the override file is undocumented without failing anything. Mitigated by making the exemption explicit in the `deployment-env-contract` spec and in the script's comments, and by keeping the override's new variables to local directory paths that no deployment consumes.

## Migration Plan

Additive; nothing deployed changes. In order: add the state directory to `.gitignore`; add the override file and the key-comparison script; add `local.sh`; delete `docker/.env`; scope the compose-scan comment in `check-env-vars.sh`; document the workflow in `README.md`.

Deleting `docker/.env` turned out not to be destructive: measured during implementation, every credential field in it was empty, and only five non-secret values were set (`GHCR_USERNAME`, `GIT_WORKSPACE_BRANCH`, `GIT_WORKSPACE_SYNC_SCHEDULE` and the two directory paths). Those five are carried into the root `.env`, which is otherwise seeded from `docker/.env.example` so it keeps the provisioning comments, with the `BRAVE_SEARCH_API_KEY` → `BRAVE_API_KEY` correction applied by construction. The file was never tracked, so no CI step depended on the repository copy — `.github/workflows/validate-config.yml` already creates an empty one when absent, and that line must stay.

Deleting it does leave three tracked files pointing at it (`CONTRIBUTING.md`, `scripts/build-and-push.sh`, and a `:?` message in `docker/docker-compose.yml`). All three are re-pointed at the root `.env`; see the amended Impact list in `proposal.md`.

Rollback is deleting the three new files and the `.gitignore` entry, and reverting those three references; `docker/.env` is reconstructible from `docker/.env.example`. Nothing on the VPS is touched at any point.

## Open Questions

- Should the pre-commit hook also run the `.env` key comparison? It cannot run in CI (no `.env` exists there), and it checks a developer's machine rather than the commit, so it is defensible either way. Deferrable: it changes no spec and no file this change creates.
- Should `up` offer an opt-in flag to pull and run the published amd64 image under emulation, for the rare case of confirming the actual deployable artifact? Additive to `local.sh` later; no other artifact depends on the answer.
