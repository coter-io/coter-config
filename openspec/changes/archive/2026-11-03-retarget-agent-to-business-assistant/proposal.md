# Proposal

## Why

The shipped agent is a general-purpose personal assistant: its workspace files describe an owl that tells bedtime stories, records camera names, and manages Discord group-chat etiquette. The deployment is none of those things — Telegram only, groups disabled, zero skills installed — and its entire external tool surface is a Composio MCP server that no workspace file mentions. The agent therefore starts without knowing its role, without knowing where its tools come from, and with behavioural guidance aimed at a life it does not lead.

## What Changes

- Retarget the predefined workspace files to a professional business assistant: scheduling, task and issue management, and other business workflows carried out through Composio.
- Give the agent a stated tool-routing contract: native tools for workspace, shell, files, browser and web search; everything touching an external business system over MCP from Composio. Written capability-shaped (scheduling, task tracking, issue tracking, mail, documents) rather than naming toolkits, because connected toolkits vary per deployment and a baked image cannot track them.
- Replace the "who asked" authorization line with tiers based on ambiguity, blast radius and reversibility: reads and ordinary single writes proceed; ambiguous recipients, targets, time zones and scope are resolved before any write; bulk, destructive, permission-changing and external-party actions are confirmed first.
- Remove workspace guidance for surfaces this deployment does not have: group-chat etiquette and reaction conventions, Discord and WhatsApp formatting, ElevenLabs voice storytelling, camera and device nicknames.
- Change the agent's identity to `⚫` with a business-like personality line, across all four enforced authoring points.
- Document how an identity or template change reaches a workspace that already exists, which no-clobber delivery does not currently do.

## Capabilities

### New Capabilities

- `agent-operating-policy`: What the agent is for, how it routes work between native tools and external business systems, how it behaves when a capability is not connected, and what it may do without asking.

### Modified Capabilities

- `agent-workspace-provisioning`: the requirement *Displayed identity and the agent's own identity agree* currently guarantees agreement only between the two authoring points in the repository. On a deployment whose workspace already holds an identity file, `docker/entrypoint.sh` seeds with `cp -rn`, so the new file is skipped while `config/openclaw.json` is replaced on bring-up — channels show the new identity and the agent reads the old one. The requirement is amended so the guarantee covers a workspace that already holds an older copy.

## Impact

Changed:

- `workspace-templates/IDENTITY.md`, `SOUL.md`, `AGENTS.md`, `USER.md`
- `config/openclaw.json` — `agents.entries.main.identity`
- `README.md` — the *Agent Identity and Workspace* section and its file table

Constraints this must respect:

- `scripts/validate-config.sh` check 5 fails closed on identity drift. The personality line is one string in four places: `identity.theme` in the config, and `Theme`, `Vibe` and `SOUL.md`'s `## Vibe` in the templates. `identity.name`, `emoji` and `avatar` must match `IDENTITY.md` exactly.
- `workspace-templates/` is `COPY`'d in `docker/Dockerfile`, so this is the image workflow — rebuild and `make deploy`, not `make push-config`.

Unchanged:

- `workspace-templates/avatars/avatar.png` — the owl stays; only the emoji becomes `⚫`
- `scripts/validate-config.sh`, `docker/Dockerfile`, `config/skills-manifest.txt`
- `scripts/upstream-templates.sha256` — it records upstream starter templates, not these customized copies

Out of scope:

- Installing `@composio/composio` (plugin) or `@composio/composio-cli` (skill). Both are CLI-backed: they need the `composio` binary in the image, an interactive `composio login`, and credentials on a path no volume persists. That contradicts the zero-interaction guarantee this repo is built on, and the skill's own rule is to defer to an already-authenticated MCP server.
- Authoring custom skills. The policy in this change is always-on and belongs in `AGENTS.md`; skills load on trigger and are the right home for named recurring procedures, which do not exist yet.
- Wiring `config/security-rules.md`, which claims to be injected into the system prompt and is in fact referenced by nothing. A separate change.
