# Tasks

## 1. Identity

- [x] 1.1 Change all four enforced identity points together — `agents.entries.main.identity` in `config/openclaw.json` (`emoji` to `⚫`, `theme` to the new personality line) and `workspace-templates/IDENTITY.md` (`Emoji`, `Theme`, `Vibe` identical to `Theme`, `Creature` to `Business assistant`), leaving `name` as `Coter` and `avatar` as `avatars/avatar.png`; verify `bash scripts/validate-config.sh` passes
- [x] 1.2 Update the explanatory notes in `workspace-templates/IDENTITY.md` so they describe a business assistant rather than an owl assistant, and verify the `- Label: value` lines are still parsed as real values by re-running `bash scripts/validate-config.sh`
- [x] 1.3 Update the *Changing the agent's identity* subsection of `README.md` so the described identity matches what ships; verify by reading back that no sentence names the previous emoji or personality line

## 2. Personality

- [x] 2.1 Rewrite `workspace-templates/SOUL.md` for a professional business assistant — reframe the "you're a guest" passage around someone's calendar, inbox and their team's tracker rather than their home, and keep the core truths about being genuinely helpful and having opinions; verify the file reads as one voice rather than edited patches
- [x] 2.2 Set the first non-blank line under `## Vibe` in `workspace-templates/SOUL.md` to the exact personality line from task 1.1; verify `bash scripts/validate-config.sh` passes its three-way vibe check

## 3. Operating guidance

- [x] 3.1 Remove the sections of `workspace-templates/AGENTS.md` covering surfaces this deployment lacks — group-chat participation and reactions, Discord and WhatsApp formatting, ElevenLabs voice storytelling, and camera/SSH/device nicknames; verify no remaining line instructs the agent to act on a channel or device class the shipped configuration does not enable
- [x] 3.2 Add a role statement to `workspace-templates/AGENTS.md` naming the agent's purpose as professional business and productivity work; verify it satisfies the *The agent knows it is a business assistant* requirement without naming a provider
- [x] 3.3 Add the tool-routing contract to `workspace-templates/AGENTS.md` — native tools for workspace, shell, files, browser and web search; the configured MCP tool surface for calendars, task trackers, issue trackers, mail and documents — written in capability classes with no provider named; verify against the *Work is routed by surface* and *capability, not by named provider* requirements
- [x] 3.4 Add the availability rule to `workspace-templates/AGENTS.md`: establish that a capability is present before promising an action, and when nothing covers it say so and stop rather than improvising through the browser or a web form; verify against the *An unavailable capability is reported rather than worked around* requirement
- [x] 3.5 Replace the *External vs Internal* section of `workspace-templates/AGENTS.md` with the three authorization tiers from `design.md` — act, resolve first, confirm before — and verify every scenario under the *Reads and ordinary single writes* and *High-consequence actions are confirmed first* requirements is covered by an explicit line
- [x] 3.6 Add the instruction to record a discovered capability-to-provider mapping, plus timezone and working hours, as dated `USER.md` directives; verify it matches the metadata and supersession rules already stated in `workspace-templates/USER.md`
- [x] 3.7 Retarget the *Automations* section of `workspace-templates/AGENTS.md` to business rhythms — upcoming meetings, ticket and task state, unread mail that needs an answer — dropping the weather and companion-style reach-out triggers; verify the quiet-hours and `NO_REPLY` rules still resolve unambiguously when both conditions apply
- [x] 3.8 Confirm `workspace-templates/AGENTS.md` carries every policy element its requirements call for — role statement, surface routing, capability-class framing naming no provider, availability-before-promise, the three authorization tiers with each spec scenario covered, and the `USER.md` recording directive — and that no surviving line contradicts them; verify by checking each against the spec and by recording the measured size change in `design.md`

## 4. User model

- [x] 4.1 Review `workspace-templates/USER.md` against the business framing, keeping both generic directives active and adding none that describe a person this template cannot know; verify no placeholder directive is left `active`, as `agent-workspace-provisioning` requires
- [x] 4.2 Confirm `workspace-templates/USER.md` stays well under its 4,000-character session budget; verify with a character count

## 5. Delivery documentation

- [x] 5.1 Document in `README.md` that `workspace-templates/` is `COPY`'d in `docker/Dockerfile`, so a template change is the image workflow and not `make push-config`; verify the statement against the `COPY` line and the two workflows already described in the README
- [x] 5.2 Document the step that makes a changed template take effect on a deployment that already has a workspace — that `docker/entrypoint.sh` seeds with `cp -rn` and skips existing files, so the stale copies must be removed or moved aside and the stack restarted, preserving anything the agent wrote into `USER.md`; verify against the *Releasing a change to the predefined files requires a deliberate delivery step* requirement
- [x] 5.3 State in `README.md` that no repository gate detects a stale deployed workspace, because `scripts/validate-config.sh` compares the repository's own authoring points and never inspects a deployment; verify by confirming the script contains no check that reads a workspace
- [x] 5.4 Update the workspace file table in the *Agent Identity and Workspace* section of `README.md` so each row describes what the file now holds; verify every listed path exists

## 6. Integration verification

- [x] 6.1 Run `bash scripts/validate-config.sh` and `bash scripts/check-env-vars.sh`; verify both pass
- [x] 6.2 Deliver the changed templates to the running local stack by moving the four stale workspace copies aside (preserving them and the agent databases rather than running `./local.sh reset`) and restarting; verify all four files then match the repository's content, that seeding into an empty workspace delivers them plus the avatar with no `BOOTSTRAP.md`, and that no setup question is asked
- [x] 6.3 Verify the running local agent reports the new identity and that `⚫` is what the channel displays, confirming the config and the workspace file agree at runtime
- [x] 6.4 Ask the local agent for an action in a capability the tool surface does not expose; verify it says so and stops rather than attempting a browser workaround
- [x] 6.5 Ask the local agent for an action with an ambiguous target; verify it asks which is meant before writing

## Workflow follow-up

- Land the deployment step from task 5.2 in the infra repository (`openclaw-terraform-hetzner`), as either a `make` target or a documented manual path, and reconcile the README wording with whichever it becomes.
- Separate change: decide whether `config/security-rules.md` is wired into the system prompt or removed. It currently claims to be injected and is referenced by nothing.
- Separate change: verify the custom-skill recipe in `README.md` (`skill.json` plus shell handlers) against the pinned OpenClaw 2026.10.7, which appears to use the `SKILL.md` form instead.
