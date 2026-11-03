# Design

## Context

See proposal.md — Why. The mechanism was traced in the running gateway against the pinned `openclaw@2026.10.7`, not inferred from documentation.

Onboarding is not a wizard the gateway runs. It is a file: OpenClaw seeds `BOOTSTRAP.md` into a workspace, and the agent reads it on its first turn. That file is what asks for a name, proposes a vibe, drives the four-option avatar sheet, and offers plugin installs. Remove the file and the ritual has no existence.

Two independent gates decide whether it is written:

```
runWorkspacePreparation(workspaceDir)
         |
  [GATE 1] agents.defaults.skipBootstrap == true ?
         |
      yes +--> creates NOTHING. bootstrapPending: false.
         |     (the workspace must already hold every file it needs)
         |
       no
         v
  publish AGENTS.md / SOUL.md / IDENTITY.md / USER.md
    -> writes only when the file is absent; never overwrites
         |
         v
  [GATE 2] does the workspace already "look configured"?
      * SOUL.md | IDENTITY.md | USER.md differs from its starter template
      * OR memory/ exists   * OR MEMORY.md exists
      * OR skills/<x>/SKILL.md exists   * OR .git exists
         |
      yes +--> setup is marked complete; BOOTSTRAP.md is never written
         |
       no +--> BOOTSTRAP.md is written; the ritual runs
```

Three properties of the current repository shape the approach:

- The delivery channel already exists and is correct. `docker/Dockerfile` copies `workspace-templates/` into the image at `/opt/workspace-templates/`, and `docker/entrypoint.sh` seeds it into the workspace with a no-clobber recursive copy *before* `exec`-ing the gateway. It holds only `.gitkeep`, which is the entire reason the ritual ran.
- Workspace files cannot travel the configuration path. `local.sh` and the infra repo's `make push-config` deliver `config/*` into the gateway's configuration directory; the workspace is a different mount. Baking into the image is the only channel that reaches both a local run and the VPS.
- Identity currently lives in two places that disagree: `config/openclaw.json` says one emoji, the onboarding-written `IDENTITY.md` says another, and the gateway preserved an `openclaw.json.clobbered.*` copy when the repository's configuration replaced the identity the ritual had written.

## Goals / Non-Goals

**Goals:**

- Make the absence of onboarding a property of the committed repository, not of accumulated runtime state.
- Make first-start behavior deterministic: no heuristic about whether the workspace "looks configured" should be load-bearing.
- Give identity exactly one authoring point, so a bring-up can never discard it.
- Make a regression loud. Emptying `workspace-templates/` must fail a gate rather than quietly restore the ritual.

**Non-Goals:**

- No fork, patch, or wrapper around OpenClaw. Everything here uses configuration and files the published package already honours.
- No change to `docker/Dockerfile`, `docker/entrypoint.sh`, or either compose file. The seeding path is already right.
- Not seeding `MEMORY.md` or `memory/`. Those are the agent's to create; predefining them would fabricate history.
- Not suppressing the plugin-recommendation beat as separate work. It reads state an interactive host onboarding stores; in the container it is already empty, and removing `BOOTSTRAP.md` removes the only thing that would read it.

## Decisions

### Use both gates, and seed all four files

Gate 1 (`agents.defaults.skipBootstrap: true`) and Gate 2 (a workspace that looks configured) each suppress the ritual alone. Both are used.

Gate 1 alone is insufficient: when bootstrap creation is disabled the gateway creates *nothing*, so an unseeded workspace leaves the agent with no conventions, no personality, and no identity.

Gate 2 alone works and is explicitly documented for this purpose, but makes a content heuristic load-bearing on things that have nothing to do with identity. An installed skill counts as evidence, for instance: a `skills/<name>/SKILL.md` would suppress the ritual on its own, so whether a user is interviewed could turn on whether a ClawHub install happened to succeed. The skills manifest now ships empty, so that particular accident cannot occur either way — which is the point: the guarantee should not rest on what else happens to be in the workspace.

Used together, neither depends on the other: the flag makes the outcome deterministic, and the seeded files make the flag safe.

| | Gate 2 only | Gate 1 + seed all four (chosen) |
|---|---|---|
| Configuration change | none | one key |
| `AGENTS.md` | gateway publishes its own | repository owns it |
| Determinism | depends on a heuristic | nothing is ever created |
| Version bumps | upstream improvements arrive free | must be re-diffed |
| Failure mode | upstream changes the heuristic | upstream adds a fifth file |

The accepted cost is ownership of `AGENTS.md`, roughly 6 KB derived from the upstream starter template. The forward-compatibility check is the mitigation.

### Seeding alongside the flag also prevents a hard failure

With bootstrap creation disabled, the preparation path treats a workspace that holds no content as evidence the workspace has vanished and raises an error rather than starting. The seeded files are what supply that evidence, and the entrypoint restores them on every start, so the condition self-heals. This makes "flag plus seeded files" not merely belt-and-braces but the only safe combination.

### A static avatar committed to the repository

The avatar is resolved from the configured identity or, failing that, from the identity file, as a workspace-relative path, an `https:` URL, or a data URI. A committed PNG under `workspace-templates/avatars/` resolves as a local file, and image generation is never reached.

Alternatives: an `https:` URL avoids a binary in the repository but makes identity display depend on an external host; emoji-only avoids both but gives up the avatar. A committed file keeps the repository self-contained and the image reproducible. The 241 KB avatar the earlier onboarding run already produced can be promoted rather than a new one invented.

### Configuration is the canonical identity, and the identity file is generated from it

`name`, `emoji`, `theme`, and `avatar` are declared in `config/openclaw.json`, and `workspace-templates/IDENTITY.md` restates the same values. The configuration is canonical because it is the file the repository already overwrites on every bring-up; a value only in the workspace would survive but not be authoritative, and a value only in the configuration would leave the agent reading a template about itself.

The two must not be allowed to drift by hand. Keeping them equal is a gate check rather than a convention.

The current emoji disagreement is resolved in favour of the owl, which matches both the avatar and the personality line; the other value is treated as the placeholder it appears to be.

### Predefined content must avoid the placeholders the gateway recognises

The gateway parses identity fields and treats a known set of starter phrases — among them "not set yet", "pick something you like", and the avatar field's own hint text — as *unset*. Predefined files must therefore carry real values, not filled-in-looking scaffolding.

`USER.md` needs the same care for a different reason: its starter content carries an example directive under an instruction never to leave a placeholder directive active, so shipping it verbatim would hand the agent a live instruction that says nothing. Because a missing `USER.md` is skipped without complaint, the choice is real content or no file; this change ships real content.

### Drift is measured against a recorded baseline, not against the files themselves

Decided during implementation. Comparing the predefined files directly to a
release's starter templates reports drift on every run, because they are
customized on purpose — the signal would always be on and would stop meaning
anything. `scripts/upstream-templates.sha256` instead records the sha256 of each
starter template body as of the pinned release, and the check compares a target
release's templates against that record. What it reports is upstream changing out
from under the predefined copies, and at the pinned release it reports nothing.

Template bodies are hashed with their YAML front matter stripped, the way the
gateway loads them, so a reworded front-matter summary is not mistaken for a
template change.

The baseline lives in `scripts/` rather than `workspace-templates/` because
`docker/entrypoint.sh` seeds that directory with `cp -rn <dir>/.`, which copies
hidden files too: anything placed there, dotfile included, would be delivered
into every agent workspace. The retired `.gitkeep` reached the live workspace
exactly that way.

A second list in the check records the templates deliberately not predefined —
`BOOTSTRAP.md` above all, since shipping it would reinstate the ritual. A
template that is neither predefined nor on that list is reported, which is how a
new upstream workspace file gets noticed.

### Validation extends the existing scripts rather than adding a new gate

`config-pr-validation` already requires the pull request gate to apply any check a validation script gains, and the pre-commit hook and release gate invoke the same scripts. Adding the checks to `scripts/validate-config.sh` and `scripts/check-forward-compat.sh` therefore reaches all three paths with no workflow edit and no new requirement in that capability.

`agents.defaults.skipBootstrap`, `identity.theme`, and `identity.avatar` were confirmed to pass the existing schema gate against the pinned version before this design was written, so the configuration change does not depend on a schema bump.

## Risks / Trade-offs

- **`AGENTS.md` no longer tracks upstream.** Improvements to the starter template stop arriving automatically, and the file can rot across version bumps. → The forward-compatibility check reports drift against the new version's templates when `ARG OPENCLAW_VERSION` is raised, making the review deliberate rather than optional.
- **A future OpenClaw release could expect a workspace file this repository does not predefine.** With creation disabled, that file would simply be absent. → The same check reports a starter file the repository does not provide.
- **The repository gains its first binary.** Diffs are opaque and the file cannot be reviewed as text. → One small PNG, referenced from a path the gate asserts exists; size is bounded by the 2 MiB limit the avatar path already enforces.
- **A user who asks the agent to change its own identity gets a transient result.** The configuration is replaced on the next bring-up. → Specified as intended behavior, and documented so the operator is pointed at the repository as the authoring point.
- **A stale workspace from before this change keeps whatever onboarding produced.** No-clobber delivery will not correct it. → Addressed by the migration plan, not by overwriting agent-written files.
- **Someone adds a fifth predefined file and forgets the gate.** The guarantee silently narrows. → The gate reads the required set from one list, so adding a file without listing it is the omission the check reports.

## Migration Plan

1. Land the configuration key, the four predefined files, the avatar, and the gate checks together. Split across commits the gate would fail on the intermediate state, which is the gate working correctly.
2. Rebuild the image so `workspace-templates/` is present at `/opt/workspace-templates/`. Locally `./local.sh up` already builds; the VPS needs a published image, so the change is only in effect there after a tagged release and deploy.
3. Verify locally from a genuinely clean state with `./local.sh reset && ./local.sh up`, then send a first message over the channel and confirm the reply is ordinary work: no name question, no avatar sheet, no plugin offer, and no `BOOTSTRAP.md` in the workspace.
4. Existing workspaces — the VPS one, and any developer workspace that has already been through onboarding — are not rewritten. Whoever owns one either leaves it as it is, since it is already configured and the ritual will not re-run, or discards it to adopt the predefined content. For the local stack that is `./local.sh reset`.
5. Rollback is removing the configuration key and the predefined files. The gateway resumes publishing its own starter files and the ritual returns on the next genuinely fresh workspace; nothing in an existing workspace is destroyed by reverting.

## Open Questions

- Whether `TOOLS.md`, which the gateway recognises but does not seed, is worth predefining later for environment-specific tool notes. The current predefined `AGENTS.md` carries a `## Tools` section, which is where upstream directs those notes, so this changes no requirement and no task here.
