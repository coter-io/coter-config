# Design

## Context

See `proposal.md` — Why. The constraints that shape the approach:

**Identity is one string in four places.** `scripts/validate-config.sh` check 5 fails closed, in the pre-commit hook, the PR gate and the release gate:

```
  config/openclaw.json                     workspace-templates/IDENTITY.md
    agents.entries.main.identity             - Name:     <- must equal
      name   <--------------------------->   - Emoji:    <- must equal
      emoji  <--------------------------->   - Theme:    <- must equal
      theme  <--------------------------->   - Avatar:   <- must equal
      avatar <--------------------------->   - Vibe:     <- must equal Theme
                                                   ^
                                           SOUL.md "## Vibe", first
                                           non-blank line <- must equal Theme
```

`- Creature:` is parsed but unchecked: `Theme` outranks it at runtime.

**Templates are baked into the image.** `docker/Dockerfile` does `COPY workspace-templates/ /opt/workspace-templates/`, so a template edit is the image workflow (rebuild → GHCR → `make deploy`), not `make push-config`.

**Seeding is no-clobber.** `docker/entrypoint.sh` runs `cp -rn "$TEMPLATES"/. "$WORKDIR"/`. A file the workspace already holds is skipped.

**The tool surface is a single MCP server.** `mcp.servers.composio` is wired from `${COMPOSIO_MCP_URL}` and `${COMPOSIO_API_KEY}`; `config/skills-manifest.txt` installs nothing. Which toolkits that server exposes is an account-level fact outside this repository.

## Goals / Non-Goals

**Goals:**

- Guidance that stays true across deployments whose connected toolkits differ.
- A write boundary that is usable daily, not one that prompts on every ticket.
- An identity change that actually reaches a running agent, not just the repository.

**Non-Goals:**

- Enforcing the write boundary in code. This change states policy in loaded text; the model can disregard it. Enforcement means a plugin hook, which has no install path here.
- Deciding the agent's provider mapping. The connected account is not inspected and no provider is named.
- Re-deriving the templates from the pinned release's starter templates. `scripts/upstream-templates.sha256` records what the current files were derived from and stays as-is.

## Decisions

### Capability-shaped guidance, not a toolkit list

`AGENTS.md` describes capability classes — scheduling, task tracking, issue tracking, mail, documents — and names no provider.

*Alternative considered:* enumerate the connected toolkits (Google Calendar, Jira, Linear, Gmail). Rejected because the list is an account fact baked into an image that outlives any account's connections, and the README already contemplates pointing a local run at a second Composio server with a narrower set. A hardcoded list rots into a lie, and a lie about tool availability produces confident failures.

*Cost:* the agent must establish availability rather than assume it. Mitigated by the spec's requirement that a discovered provider/capability mapping is recorded as a dated `USER.md` directive, so the probe happens once per deployment rather than once per task.

### Authorization tiers by consequence, not by who asked

`AGENTS.md` currently splits on **requested vs unrequested** ("Ask first: public or outbound actions the user did not request"). For a business agent that line falls in the wrong place: "book 30 minutes with Anna and Tom" is requested yet mails two colleagues, while a requested bulk transition of a sprint is far more dangerous and sits on the same side of the line.

The replacement splits on **ambiguity, blast radius and reversibility**:

```
  ACT                       RESOLVE FIRST               CONFIRM BEFORE
  ---                       -------------               --------------
  any read                  ambiguous recipient         bulk writes
  create/update one         ambiguous target            deletions, cancellations
    event, task, ticket       board, project, repo      external-party sends
  ordinary invitee          unclear time zone           permission/access changes
    notification            unclear scope
```

*Alternative considered:* confirm every external write. Rejected — an agent that asks before each Jira comment gets switched off within a week, and `config/security-rules.md` rule 4 already shows where that instinct leads.

### Policy goes in `AGENTS.md`, not in a skill or plugin

Role, routing and the write boundary are always-on. A skill loads on trigger, so a safety rule inside one is absent exactly when it has not triggered.

*Alternatives considered:* the ClawHub `@composio/composio` plugin and `@composio/composio-cli` skill. Both are CLI-backed — they need the `composio` binary present at build time (the Dockerfile's own header states runtime installs are lost), an interactive `composio login`, and credentials on a path that is not volume-backed:

```
  volumes:  /home/node/.openclaw            persisted
            /home/node/.openclaw/workspace  persisted
  HOME:     /home/node                      everything else is ephemeral
```

With `restart: unless-stopped`, a browser sign-in that does not survive a restart contradicts the zero-interaction guarantee in `agent-workspace-provisioning`. The skill's own routing rule also defers to an already-authenticated MCP server, which this deployment has. Their *content* — routing discipline, resolve-before-write, bounded destructive actions — is a model for the prose written here.

A custom skill is the right home for named recurring procedures (a standup digest, a weekly review). None exist yet; writing them before observing the work would be guessing.

### Remove guidance for absent surfaces

Group-chat etiquette and reaction conventions (`telegram.groupPolicy: "disabled"`), Discord and WhatsApp formatting (Telegram is the only channel), ElevenLabs voice storytelling (`skills-manifest.txt` is empty), camera and device nicknames (no home automation anywhere) are deleted rather than reworded. Dead guidance costs context every session and invites the agent to act on a surface it does not have.

*Trade-off:* if group chat is enabled later, that guidance must be reinstated by the change that enables it.

### `USER.md` keeps generic directives

`agent-workspace-provisioning` forbids shipping a placeholder directive as active, so the template cannot ship a business profile for a person it does not know. Its two existing generic directives stay; the capability-shaped routing in `AGENTS.md` instructs the agent to write timezone, working hours and provider mapping into `USER.md` as it learns them. `USER.md` loads under a separate 4,000-character budget, which the generic file is far below.

### `README.md` is updated in the same change

The *Agent Identity and Workspace* section and its file table describe the agent's framing and are gated by nothing. Left alone they go stale the moment the templates change.

## Risks / Trade-offs

- **The four identity strings are edited partially** → `bash scripts/validate-config.sh` is run before commit; it fails closed and names the disagreeing field. The pre-commit hook runs it anyway.
- **The VPS workspace keeps the old files after deploy** → the most likely failure of this change, and invisible: channels show `⚫` while the agent reads `🦉`. No repository gate detects it. Handled by the migration plan below and by the new documentation requirement.
- **Prose policy is advisory** → accepted for now. If the agent is observed crossing the write boundary, the escalation path is a plugin hook, tracked as separate work.
- **Capability-shaped guidance makes the agent hesitant** → the `USER.md` recording directive converts repeated discovery into a one-time cost. If hesitancy persists in use, the fix is a sharper discovery rule, not a hardcoded toolkit list.
- **Context budget** → `AGENTS.md` grows. Measured during implementation: 124 lines / 6,450 characters before, 145 / 8,689 after — +17% lines, +34% characters, roughly 550 extra tokens per session. The earlier estimate that the removals would offset the additions was wrong: ~29 lines came out (group chats, Discord/WhatsApp, storytelling, device notes) and ~50 went in (role, routing, availability, recording, the three tiers). Accepted deliberately. One tightening pass recovered ~440 characters and every remaining line carries a rule a spec requirement needs, so the cost cannot be removed without dropping specified behaviour. Revisit by extracting procedures into skills if the file keeps growing.

## Migration Plan

1. Edit the four identity points together and the three remaining template files; update `README.md`.
2. `bash scripts/validate-config.sh` and `bash scripts/check-env-vars.sh` — both must pass.
3. Verify locally: `./local.sh reset` seeds a fresh workspace, so the new files land and the identity shows `⚫`.
4. Commit, push, tag, release, publish the image (the templates are in the image).
5. From the infra repo, `make deploy`.
6. **Replace the stale workspace copies on the VPS.** Seeding will not overwrite them. Remove or move aside the existing `IDENTITY.md`, `SOUL.md`, `AGENTS.md` and `USER.md` in the agent's workspace and restart so the new copies seed — preserving any content the agent itself has written into `USER.md`.
7. Confirm the running agent reports the new identity and the channel shows `⚫`.

**Rollback:** revert the commit, rebuild, redeploy, and repeat step 6 with the previous files. Locally, `./local.sh reset` restores the repository's versions.

## Open Questions

- The exact mechanism for step 6 lives in the infra repository (`openclaw-terraform-hetzner`), which is not part of this workspace. Whether it is an existing target, a new one, or a documented manual SSH step is settled when the step is written; it does not change the specs or the approach here.
