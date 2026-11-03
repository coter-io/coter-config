# Tasks

## 1. Predefined workspace files

- [x] 1.1 Extract the four starter templates for the pinned OpenClaw version from the image (`docs/reference/templates/{AGENTS,SOUL,IDENTITY,USER}.md`) into `workspace-templates/`, stripping the YAML front matter block as the gateway itself does when it loads a template; verify each of the four files exists, is non-empty, and begins with its `#` heading rather than `---`
- [x] 1.2 Replace every placeholder value in `workspace-templates/IDENTITY.md` with the canonical identity — name, creature, vibe line, emoji, and the avatar path — and verify no field holds a value from the gateway's recognised placeholder set (for example "not set yet", "pick something you like", or the avatar field's own hint text)
- [x] 1.3 Write real active directives into `workspace-templates/USER.md`, each with an observation date and `status: active`, and verify no example or placeholder directive is left marked active
- [x] 1.4 Set the canonical personality line in `workspace-templates/SOUL.md` and verify it reads identically to the vibe line in `IDENTITY.md`
- [x] 1.5 Delete `workspace-templates/.gitkeep` and verify `git ls-files workspace-templates/` lists the real files and no longer lists the placeholder

## 2. Predefined avatar

- [x] 2.1 Commit the avatar as `workspace-templates/avatars/avatar.png`, promoting the existing image rather than generating a new one, and verify with `file` that it is a valid PNG and with `wc -c` that it is under the 2 MiB limit the avatar path enforces
- [x] 2.2 Reference it from the `- Avatar:` line of `workspace-templates/IDENTITY.md` as the workspace-relative path `avatars/avatar.png`, and verify the path contains no leading `/`, `~`, or `..` segment

## 3. Shipped configuration

- [x] 3.1 Add `agents.defaults.skipBootstrap: true` to `config/openclaw.json` and verify `./scripts/validate-config.sh` passes against the pinned version's schema
- [x] 3.2 Declare `name`, `emoji`, `theme`, and `avatar` under `agents.entries.main.identity`, correcting the emoji to the canonical one, and verify `./scripts/validate-config.sh` passes and that each value is byte-identical to the corresponding field in `workspace-templates/IDENTITY.md`

## 4. Fail-closed validation gate

- [x] 4.1 Extend `scripts/validate-config.sh` to fail when `agents.defaults.skipBootstrap` is absent or not `true`, with a message naming the consequence that the onboarding ritual would return; verify by running the script against a scratch copy with the key removed and confirming it exits non-zero with that message
- [x] 4.2 Add a check that every required predefined workspace file and the avatar are present, reading the required set from a single list in the script; verify by temporarily moving one file aside and confirming the script fails and names that file
- [x] 4.3 Add a check that the identity declared in `config/openclaw.json` matches the values in `workspace-templates/IDENTITY.md`; verify by probing a scratch copy with a mismatched emoji and confirming it fails and reports the disagreement
- [x] 4.4 Confirm the new checks reach every gate with no workflow edit by running `.githooks/pre-commit` locally and by re-reading `.github/workflows/validate-config.yml` to verify it still only invokes the repository scripts
- [x] 4.5 Document the required-set list in a comment in the script explaining that adding a predefined file without listing it is the omission the gate reports; verify the comment names the file that holds the list

## 5. Forward-compatibility drift check

- [x] 5.1 Extend `scripts/check-forward-compat.sh` to compare each predefined workspace file against the corresponding starter template of the OpenClaw version under test and report any that have drifted; verify it reports no drift for the files as derived against the currently pinned version
- [x] 5.2 Make the same check report a starter workspace file the repository does not predefine; verify by running the check against a version whose template set differs from the pin, or by pointing it at a template directory with an extra file
- [x] 5.3 Document in `CONTRIBUTING.md` that raising `ARG OPENCLAW_VERSION` requires reviewing reported drift because `AGENTS.md` no longer tracks upstream automatically, and verify the documented command runs as written

## 6. Operator documentation

- [x] 6.1 Document in `README.md` that the agent's workspace files and identity are predefined, that a first start asks nothing and generates no avatar, and that `config/openclaw.json` plus `workspace-templates/IDENTITY.md` are the only places identity is authored; verify the referenced paths exist
- [x] 6.2 Document that a runtime request to change the agent's displayed identity is transient because the repository's configuration is restored on the next bring-up, and verify the note names the repository as the authoring point

## 7. End-to-end verification

- [x] 7.1 Bring the stack up from a genuinely clean state with `./local.sh reset && ./local.sh up`, and verify the workspace contains the four predefined files and `avatars/avatar.png` with the repository's content and no `BOOTSTRAP.md`
- [x] 7.2 Send a first message over the channel and verify the reply is ordinary work: no question about the agent's name, personality, or avatar, no avatar choice sheet, and no plugin-installation offer
- [x] 7.3 Verify the identity shown on the channel matches `workspace-templates/IDENTITY.md`, then restart the stack and verify no `openclaw.json.clobbered.*` file is produced and no identity value is lost
- [x] 7.4 Edit one delivered workspace file inside the running workspace, restart without resetting, and verify the edit survives — confirming delivery does not overwrite what the workspace already holds
- [x] 7.5 Verify the gateway starts cleanly on a second bring-up with no reset, with no workspace-vanished error and no repeated skill installation
