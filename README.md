# OpenClaw Docker Config

Docker configuration and application setup for OpenClaw. Companion repository to [openclaw-terraform-hetzner](https://github.com/andreesg/openclaw-terraform-hetzner).

**Note:** This is a minimal, generic configuration with only essential skills activated. You're encouraged to customize it by adding [ClawHub skills](https://clawhub.ai/) or creating your own custom skills (see [Working with Skills](#working-with-skills)).

```
┌──────────────┐                        ┌──────────────────────┐
│   Laptop     │──── git push ─────────▶│   GitHub             │
│   (develop)  │                        │   (openclaw-config)  │
│              │                        └──────────────────────┘
│              │  
│              │   build-and-push.sh    ┌──────────────────────┐
│              │───────────────────────▶│   GHCR               │
│              │                        │   :latest  :abc1234  │
│              │                        └──────────────────────┘
│              │
│              │  make push-config      ┌──────────────────────┐
│              │  make push-env         │   Hetzner VPS        │
│              │──── (infra repo) ─────▶│   ┌────────────────┐ │
│              │  make deploy           │   │ Docker         │ │
└──────────────┘                        │   │ openclaw-gw    │ │
                                        │   └────────────────┘ │
                                        │   :18789 (loopback)  │
                                        └──────────────────────┘
```

## Prerequisites

- Docker and Docker Compose on the VPS
- SSH access to the VPS (`ssh openclaw@VPS_IP`)
- The infra repo (`openclaw-terraform-hetzner`) set up with `config/inputs.sh` pointing `CONFIG_DIR` to this repo
- API keys (see `docker/.env.example` for the full list; secrets live in the infra repo's `secrets/openclaw.env`)

## How This Repo Connects to the VPS

This repo is **not cloned on the VPS**. Instead, the infra repo's scripts copy
specific files from your local checkout to the VPS:

| What | Pushed by | Lands at (VPS) |
|------|-----------|----------------|
| `docker/docker-compose.yml` | `make bootstrap` (once) | `~/openclaw/docker-compose.yml` |
| `config/*` (openclaw.json, etc.) | `make push-config` | `~/.openclaw/` |
| Docker image | `make deploy` (pulls from GHCR) | Docker image cache |
| Secrets | `make push-env` | `~/openclaw/.env` |

## First-Time Setup

> Provisioning and bootstrap are handled by the infra repo. See its README.

1. **In the infra repo**, set `CONFIG_DIR` in `config/inputs.sh` to point to this repo's directory
2. **Log in to GHCR** (one-time, on your laptop):
   ```bash
   echo "$GHCR_TOKEN" | docker login ghcr.io -u $GHCR_USERNAME --password-stdin
   ```
3. **Build and push the Docker image**:
   ```bash
   bash scripts/build-and-push.sh
   ```
4. Run `make bootstrap` from the infra repo — copies `docker-compose.yml`, config, and secrets to VPS
5. Run `make deploy` from the infra repo — pulls the Docker image from GHCR and starts the container
6. **Complete Telegram pairing:** open Telegram, find your bot, send `/start`

## Models (OpenRouter)

All models are routed through [OpenRouter](https://openrouter.ai) with a single `OPENROUTER_API_KEY`. Prices are approximate USD per million input/output tokens — except where a row says otherwise — and drift, so re-check the [model catalog](https://openrouter.ai/models) before changing them.

| Slot (`agents.defaults`) | Model | ~Price |
|---|---|---|
| `model` (default) | `anthropic/claude-haiku-5.5` | 0.10 / 0.50 |
| `model.fallbacks` | `openai/gpt-6.1-terra`, `google/gemini-3.6-flash` | 1 / 5, 0.75 / 3.75 |
| `utilityModel` (titles, recaps) — single ref, no fallback | `qwen/qwen3.7-flash` | 0.03 / 0.13 |
| `imageModel` (vision, only if the primary lacks image input) | `qwen/qwen3.8-flash` | 0.15 / 0.47 |
| `pdfModel` | `google/gemini-3.1-flash-lite` | 0.25 / 1.5 |
| `mediaModels.image` (image generation) | `google/gemini-3.1-flash-image` | 0.50 / 3 |
| `tools.media.models` † (audio transcription) | `openai/whisper-large-v3-turbo`, fallback `openai/gpt-4o-mini-transcribe` | ~0.012 per audio-hour; 1.25 / 5 |

† This slot is the one exception to the two conventions above. It lives at the config root rather
than under `agents.defaults`, and each entry is tagged `capabilities: ["audio"]`. Its `model` value
is a **bare upstream OpenRouter slug** — `openai/whisper-large-v3-turbo`, not
`openrouter/openai/whisper-large-v3-turbo` — because the entry names `provider: "openrouter"` in a
separate field; prefixing it would send a slug that does not exist. The primary also bills per
second of audio rather than per token, so its price is not comparable to the other rows; the
`gpt-4o-mini-transcribe` fallback bills per token like the rest.

Fallbacks only run when a request fails, not when an answer is weak. `utilityModel` takes a
single ref — the config schema has no fallback list for that slot.

For a hard task, escalate manually in Telegram: `/model sonnet` (Claude Sonnet 5.5, ~2 / 10)
or `/model terra`. Which models `/model` will accept is set by `agents.defaults.modelPolicy.allow`,
which lists the default, its fallbacks, and both aliases — anything outside that list is
refused, so a premium model cannot be selected by accident. `agents.defaults.models` only
defines the aliases; adding an alias there does not make a model selectable unless its ref is
also in the allowlist.

Audio transcription routes through OpenRouter like everything else, so `OPENROUTER_API_KEY` is the
only model credential the deployment needs — there is no second vendor key to provision. Inbound
voice notes are transcribed before the reply pipeline runs, and the transcript is what the agent
sees.

One caveat worth knowing before you send voice notes. The
`models.providers.openrouter.params.provider` routing policy — `data_collection: "deny"` and
`require_parameters: true` — applies to chat-completions requests only. Transcription uses
OpenRouter's separate `/audio/transcriptions` endpoint, whose request body carries just the model,
the audio and an optional language hint, so **voice audio is sent without the `data_collection:
"deny"` preference that text requests carry**. In OpenClaw `2026.10.7` no config key changes this:
the per-entry `providerOptions` accepts only scalar values, and `headers`/`request` affect
transport rather than the request body. Text and images are unaffected.

### Heartbeat model

The heartbeat is an automation job, not an `openclaw.json` key (`agents.defaults.heartbeat` is deprecated). After deploying, set it to the cheapest model on the VPS:

```bash
openclaw automations edit <job-id> --model openrouter/qwen/qwen3.7-flash
openclaw automations show <job-id>
```

Add `--fallbacks <list>` to set per-job fallbacks, or `--clear-model` to revert to the agent default.

## Config Change Workflow

There are two types of changes, and they have different workflows:

### Changing config (openclaw.json, skills, hooks)

Config files are pushed to the VPS via SCP — no image rebuild needed.

```
edit → validate → commit → push → make push-config (infra repo)
```

1. Edit files in `config/`, `skills/`, or `hooks/`
2. Validate: `bash scripts/validate-config.sh` and `bash scripts/check-env-vars.sh`
3. Commit and push to GitHub
4. From the **infra repo**: `make push-config` (SCPs config to VPS and restarts)

### Changing the Docker image (Dockerfile, OpenClaw version)

Image changes require a rebuild and push to GHCR.

```
edit → commit → push → build-and-push.sh → make deploy (infra repo)
```

1. Edit `docker/Dockerfile` (e.g. bump `OPENCLAW_VERSION`, add a binary)
2. Commit and push to GitHub
3. Build and push image: `bash scripts/build-and-push.sh`
4. From the **infra repo**: `make deploy` (pulls new image from GHCR and restarts)

#### Publishing from CI (by Git tag)

The **Publish image** workflow builds and pushes both images (`openclaw-gateway`, `workspace-sync`) to `ghcr.io/<repo owner>/openclaw-docker-config/` from an existing tag, using the same Dockerfiles as `build-and-push.sh`. It runs `validate-config.sh` and `check-secrets.sh` first.

1. Create a tag with the **Create tag** workflow (Actions → Create tag → pick bump).
2. Create a GitHub release for that tag (Releases → *Draft a new release* → choose the tag → *Publish release*). A draft does not count.
3. Actions → **Publish image** → *Run workflow*. Under **Use workflow from**, switch to the **Tags** tab and select the tag. Running it from a branch, or from a tag with no published release, fails immediately.
4. Tick **Also tag and push :latest** only when you want `make deploy` to pick the image up. Unticked, images are pushed as `:<tag>` and `:<short sha>` only.

Notes:
- Only tags that contain the workflow file can be built, so `v0.0.1` and `v1.0.0` are not buildable. The workflow must be on `main` before you cut a new tag.
- Set `GHCR_USERNAME` (in `.env`) to the repo owner (lowercase) so `docker-compose.yml` resolves to the images the workflow pushed.
- New packages are private by default; make sure the VPS can pull them.

## Working with Skills

This repository includes a minimal set of generic skills in `config/skills-manifest.txt`. You can extend OpenClaw by adding ClawHub skills or creating custom skills.

### ClawHub Skills

[ClawHub](https://clawhub.ai/) is the community skill registry for OpenClaw. To add a ClawHub skill:

1. **Find the skill** at [clawhub.ai](https://clawhub.ai/) (e.g., `pdf`, `ms-office-suite`, `jira`)
2. **Add to manifest**: Edit `config/skills-manifest.txt` and add the skill name
   ```
   # PDF processing
   pdf
   ```
3. **Rebuild and deploy**:
   ```bash
   bash scripts/build-and-push.sh
   # Then from infra repo:
   make deploy
   ```

The `entrypoint.sh` script auto-installs skills from the manifest on container startup via `clawhub install`.

### Custom Skills

Custom skills are user-defined commands or workflows. To create one:

1. **Create the skill directory**:
   ```bash
   mkdir -p skills/my-skill
   ```

2. **Write the skill manifest** (`skills/my-skill/skill.json`):
   ```json
   {
     "name": "my-skill",
     "version": "1.0.0",
     "description": "My custom skill",
     "commands": {
       "my-command": {
         "handler": "my-command.sh"
       }
     }
   }
   ```

3. **Write the handler** (`skills/my-skill/my-command.sh`):
   ```bash
   #!/bin/bash
   # Your custom logic here
   echo "Hello from my-skill!"
   ```

4. **Make it executable**:
   ```bash
   chmod +x skills/my-skill/my-command.sh
   ```

5. **Push to VPS**:
   ```bash
   # From the infra repo:
   make push-config
   ```

   Custom skills in `skills/` are copied to `~/.openclaw/workspace/skills/` on the VPS.

6. **Use in OpenClaw**:
   - Via chat: "Run my-command"
   - Via Telegram: `/my-command`

### Skill Structure Reference

OpenClaw skills can include:
- **Slash commands** — callable via `/command-name`
- **Hooks** — triggered on events (e.g., before tool execution)
- **Templates** — prompt templates for common workflows
- **Tools** — custom tool definitions

For detailed skill development documentation, see the [OpenClaw Skill Development Guide](https://docs.openclaw.ai/skills).

### Included Skills

The default configuration includes these generic ClawHub skills:

| Skill | Description | Use Case |
|-------|-------------|----------|
| `yt` | YouTube transcript fetching and video search | "Get transcript for youtube.com/watch?v=..." |
| `agent-browser` | Headless browser for JavaScript-heavy/paywalled pages | Access dynamic content |
| `system-monitor` | CPU/RAM/GPU status check | "What's my server's CPU usage?" |
| `conventional-commits` | Format commit messages per convention | Standardized commit messages |

These are intentionally minimal — add your own skills based on your workflows.

## Workspace Git Sync (Optional)

Back up your `~/.openclaw/workspace` directory to a private git remote automatically. Runs as a Docker sidecar container with built-in cron, pushing to a configurable branch (default: `auto`). You can then manually merge `auto` into `main` via PR whenever you want.

Supports GitHub, GitLab, Bitbucket, and any git remote that accepts HTTPS push with inline authentication.

### Setup

Choose **one** of the two options below — do not set both.

#### Option 1: GitHub shorthand

1. **Create a private GitHub repo** (e.g. `your-username/openclaw-workspace`)
2. **Create a GitHub PAT** at [github.com/settings/tokens](https://github.com/settings/tokens) with `repo` scope
3. **Add to your `.env`** (or infra repo's `secrets/openclaw.env`):
   ```
   GIT_WORKSPACE_REPO=your-username/openclaw-workspace
   GIT_WORKSPACE_TOKEN=ghp_your_personal_access_token
   ```

The token is passed to git via `GIT_ASKPASS` at runtime and is **not** embedded in the remote URL or persisted to `.git/config`.

#### Option 2: Generic git remote

1. **Build the remote URL** with inline authentication for your provider:
   - GitLab: `https://user:token@gitlab.com/username/repo.git`
   - Bitbucket: `https://x-token-auth:token@bitbucket.org/username/repo.git`
2. **Add to your `.env`** (or infra repo's `secrets/openclaw.env`):
   ```
   GIT_WORKSPACE_REMOTE=https://user:token@gitlab.com/username/openclaw-workspace.git
   ```

> **Note:** With this option, the URL (including credentials) is stored in `.git/config` inside the workspace volume. The token is already present in the `.env` file on the VPS, so this does not increase the attack surface.

#### Common settings (both options)

```
GIT_WORKSPACE_BRANCH=auto
GIT_WORKSPACE_SYNC_SCHEDULE=0 4 * * *
```

**Deploy** — the sidecar auto-enables when either `GIT_WORKSPACE_REPO` or `GIT_WORKSPACE_REMOTE` is set:
```bash
# From infra repo:
make push-env && make deploy
```

The sidecar runs an initial sync on startup, then syncs on the configured cron schedule (default: daily at 4 AM UTC).

### Manual Sync

```bash
# From infra repo:
make workspace-sync
```

### Disable

Remove or clear `GIT_WORKSPACE_REPO` / `GIT_WORKSPACE_REMOTE` from your `.env` and redeploy.

## Accessing the Dashboard

The gateway binds to loopback only (`127.0.0.1:18789`). Access it via SSH tunnel:

```bash
ssh -N -L 18789:127.0.0.1:18789 openclaw@VPS_IP
```

Then open `http://localhost:18789` in your browser.

## Managing Secrets

Secrets (API keys, tokens) are managed by the **infra repo**, not this repo.
This repo only contains `docker/.env.example` as documentation of what
variables are required.

In the infra repo:
- Edit `secrets/openclaw.env`
- Run `make push-env` to push to VPS and restart

## Docker Image Versioning

Images are built locally and pushed to GHCR via `scripts/build-and-push.sh`:

- `ghcr.io/YOUR_USERNAME/openclaw-docker-config/openclaw-gateway:latest` — main gateway image
- `ghcr.io/YOUR_USERNAME/openclaw-docker-config/workspace-sync:latest` — workspace git sync sidecar
- Both images also get a `:<sha>` tag pinned to the git commit

**One-time GHCR login (laptop):**

```bash
# Create a PAT at github.com/settings/tokens with write:packages scope
echo "$GH_TOKEN" | docker login ghcr.io -u $GHCR_USERNAME --password-stdin
```

**Rollback to a previous version:**

```bash
# On the VPS, in ~/openclaw/:
# Edit docker-compose.yml, change :latest to the SHA tag (e.g. :abc1234)
docker compose pull && docker compose up -d
```

**Upgrade OpenClaw itself:** bump `OPENCLAW_VERSION` in `docker/Dockerfile`, commit, push, then run `scripts/build-and-push.sh` followed by `make deploy` from the infra repo. A new OpenClaw release can raise its minimum Node version (the install fails with an "requires Node" error); if so, bump the `FROM node:` base image in the same Dockerfile to match.

## Troubleshooting

### Container won't start

```bash
# From the infra repo:
make logs
# Or SSH in:
cd ~/openclaw && docker compose logs openclaw-gateway
```

Check for missing environment variables or invalid config JSON.

### "Permission denied" on config directory

Ensure the host directories exist and are owned by the correct user:

```bash
sudo mkdir -p /home/openclaw/.openclaw/workspace
sudo chown -R 1000:1000 /home/openclaw/.openclaw
```

### Telegram bot not responding

- Check secrets: `make push-env` from infra repo to re-push
- Check that no other process is polling the same bot token
- Restart: `make deploy` from infra repo

### Config validation fails

```bash
bash scripts/validate-config.sh
```

The script runs four checks: JSON syntax, a raw-credential scan, the config schema of
the OpenClaw version pinned in `docker/Dockerfile`, and that version's own health
lint. Both of the last two run inside a throwaway container, because the pinned
version needs Node >= 24.22.1 — so **Docker must be running**, and the checks fail
rather than skipping if it is not. `jq` is required too.

The config's `${ENV_VAR}` placeholders are supplied through the container's
environment, which the runtime expands natively, so the file is validated exactly as
it is committed — nothing is substituted and no copy is made. Values already set in
your shell are used as-is; anything unset gets a well-formed dummy, so validation
needs no real secrets.

Common causes:
- Invalid JSON syntax (missing comma, trailing comma)
- Raw API key accidentally pasted into `openclaw.json`. The credential scan catches
  known key prefixes, and the health lint catches any other hardcoded value sitting in
  a secret-bearing field — the schema accepts it as a string, so this is the check
  that reports it.
- A key whose shape moved in a newer OpenClaw release. The output names each one and
  its canonical replacement, with the line it sits on. Legacy keys fail the script
  even when the gateway would still boot with them, so drift is caught here instead of
  at startup.
- A health finding at `warning` or above. The lint is read as JSON and judged by its
  findings, not by its exit code, which does not track the verdict. Three checks are
  skipped by name because they describe the machine running validation rather than the
  config; each is commented in the script with the reason.

To validate a file other than the committed config — handy when reproducing a failure
— pass it as an argument: `bash scripts/validate-config.sh /tmp/candidate.json`.

### Environment variable contract fails

```bash
bash scripts/check-env-vars.sh
```

Every `${VAR}` referenced by `config/openclaw.json` or `docker/docker-compose.yml` must
be declared in `docker/.env.example` under the same name. The check needs no Docker and
runs offline.

It reports the variable, the file that references it, and — when the name looks like a
misspelling of one already documented — the name to reconcile it with. That pairing is
the case worth watching: a variable documented under one spelling and injected under
another reaches the container empty, so the feature depending on it fails silently
rather than loudly.

Comments are ignored in both files, so the commented-out multi-agent block in
`docker-compose.yml` does not require its per-agent variables to be declared. The check
is one-directional: a variable documented but referenced by neither file is allowed,
since `.env.example` also documents values consumed outside these two files.

### Check VPS health

```bash
# From the infra repo:
make status
```

## Enable Git Hooks

To activate the pre-commit validation hook:

```bash
git config core.hooksPath .githooks
```
