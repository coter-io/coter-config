# Tasks

## 1. Rework the config validation script

- [x] 1.1 Replace the `sed` placeholder substitution in `scripts/validate-config.sh` with exported environment defaults for each `${VAR}` the config references, defaulting only unset variables and giving `URL`-named variables a well-formed URL; verify `bash scripts/validate-config.sh` passes, `git status` shows `config/openclaw.json` unmodified, and no temporary copy is left behind
- [x] 1.2 Replace the `doctor` prose grep with `doctor --lint --json` parsed by `jq`, failing when `ok` is false or `findings` is non-empty, with `--severity-min warning`, an exported dummy `OPENCLAW_GATEWAY_TOKEN`, and explicit `--skip` entries for `core/doctor/runtime-tool-schemas`, `core/doctor/heartbeat-cadence-migration` and `core/doctor/node-hosting-preconditions`, each commented with why it is skipped; verify a clean run reports `ok: true` with zero findings and that the script never reads the lint's exit code
- [x] 1.3 Keep `config validate` ordered before the lint and stop on its failure; verify against a scratch copy carrying `gateway.prot` and a string `agents.defaults.maxConcurrent` that the script fails naming both keys with their line numbers, and that the lint step does not run
- [x] 1.4 Verify renamed-legacy detection against a scratch copy using `agents.list` instead of `agents.entries`: the script fails and the output names `agents.entries` as the canonical replacement
- [x] 1.5 Verify detection of a defect the schema accepts against a scratch copy carrying a hardcoded credential in `channels.telegram.botToken`: `config validate` accepts it, the lint reports `core/doctor/security` at warning severity, and the script fails naming the path and remedy; record the observed `checkId` in the script comment. (Measured correction: the originally assumed case — dropping `agents.defaults.modelPolicy.allow` while keeping `agents.defaults.models` — is not in this class on the pinned version and produces zero findings; design.md updated.)
- [x] 1.6 Make each prerequisite fail closed with a named message — missing `jq`, missing container runtime, and an unparseable `ARG OPENCLAW_VERSION` — and verify each exits non-zero rather than skipping the check
- [x] 1.7 Update the validation section of `README.md` to describe environment-supplied placeholders and the structured health lint, and verify the documented command runs as written

## 2. Add the environment-variable contract check

- [x] 2.1 Create `scripts/check-env-vars.sh` that extracts `${VAR}` references from `config/openclaw.json` and `${VAR}` / `${VAR-}` / `${VAR:-default}` references from `docker/docker-compose.yml`, compares them against names declared in `docker/.env.example`, and reports each undeclared name with the file that references it; verify it currently fails naming `BRAVE_API_KEY`, `OPENAI_API_KEY`, `TELEGRAM_USER_ID`, `COMPOSIO_API_KEY` and `COMPOSIO_MCP_URL`
- [x] 2.2 Exclude comments on both sides of the comparison; verify `GIT_WORKSPACE_REPO_SECOND` and `GIT_WORKSPACE_REMOTE_SECOND`, which appear only in commented blocks in both files, are not reported
- [x] 2.3 Verify the check is one-directional: declared-but-unreferenced names `ANTHROPIC_API_KEY` and `GHCR_USERNAME` do not cause a failure
- [x] 2.4 Make the check fail closed with a named message when any of the three input files is missing or unreadable, and verify it exits non-zero
- [x] 2.5 Document `scripts/check-env-vars.sh` in the `README.md` validation section and in the Configuration Guidelines of `CONTRIBUTING.md`, and verify the documented command runs as written

## 3. Clear the environment-variable drift

- [x] 3.1 Rename `BRAVE_SEARCH_API_KEY` to `BRAVE_API_KEY` in `docker/.env.example`, keeping its provisioning comment, and verify the name now matches what `docker/docker-compose.yml` injects
- [x] 3.2 Declare `OPENAI_API_KEY`, `TELEGRAM_USER_ID`, `COMPOSIO_API_KEY` and `COMPOSIO_MCP_URL` in `docker/.env.example`, each with the source an operator uses to obtain its value, and verify no declared variable is a bare name
- [x] 3.3 Verify `bash scripts/check-env-vars.sh` now passes with no findings
- [x] 3.4 Mark every credential the deployment cannot run without as `${VAR:?<how to obtain it>}` in `docker/docker-compose.yml`, leaving feature-only variables on `-` / `:-`, and verify `docker compose config -q` succeeds against a filled `.env`, exits non-zero naming each required variable when it is unset, and still succeeds when an optional one is unset. (Measured correction: plain `${VAR}` with no default only warns and substitutes a blank string, so it does not express "required"; Composio is in the required set because an empty `COMPOSIO_MCP_URL` leaves the literal placeholder in the config and the pinned version rejects it. design.md updated.)

## 4. Add the pull request validation workflow

- [x] 4.1 Create `.github/workflows/validate-config.yml` triggering on `pull_request` against `main` for opened, synchronize and reopened, plus `push` to `main`, with `permissions: contents: read`, a `cancel-in-progress` concurrency group, and no `paths:` filter; verify the workflow file parses with `actionlint` or `gh workflow view`
- [x] 4.2 Add the gate steps in cheap-and-offline-first order — `jq empty` on the config, `scripts/check-secrets.sh`, `scripts/check-env-vars.sh`, `docker compose config -q`, then `scripts/validate-config.sh` — invoking the repository scripts rather than reimplementing their logic, and verify no validation logic is inlined in the workflow
- [x] 4.3 Add a ShellCheck step covering `scripts/*.sh`, `.githooks/pre-commit`, `docker/entrypoint.sh` and `docker/workspace-sync/*.sh`, and verify it passes or that each remaining finding is explicitly suppressed with a reason
- [x] 4.4 Add the advisory forward-compatibility step that resolves the newest published OpenClaw version at run time and validates the config against it without failing the run, and verify a simulated rejection leaves the job conclusion successful
- [x] 4.5 Document the pull request gate in the Pull Requests section of `CONTRIBUTING.md`, including that it runs on every pull request regardless of changed paths, and verify the description matches the workflow triggers

## 5. Bring the other gates to parity

- [x] 5.1 Add a `scripts/check-env-vars.sh` step to the pre-build validation in `.github/workflows/publish-image.yml`, alongside the existing config validation and secret scan, and verify the step ordering places it before any build step
- [x] 5.2 Add `scripts/check-env-vars.sh` to `.githooks/pre-commit` with the same failure messaging style as the existing checks, and verify the hook fails on introduced drift and passes on a clean tree

## 6. End-to-end verification

- [x] 6.1 Open the pull request for this change and verify **Validate config** starts automatically, runs every step, and passes
- [x] 6.2 Push a commit carrying a deliberately broken config, verify the gate fails with output naming the file, the key and its remedy, then revert that commit and verify the gate returns to passing on the new head (verified by the maintainer on the live pull request)
- [x] 6.3 Verify the superseded-run behavior by pushing two commits in quick succession and confirming the earlier run is cancelled and only the newer one reports a conclusion (verified by the maintainer on the live pull request)
- [x] 6.4 Verify the advisory step's output appears in the run log and reports the shipped config as accepted by the newest published release (verified by the maintainer on the live pull request)
- [x] 6.5 Run `openspec validate add-config-pr-validation --strict` and verify it reports no issues

## Workflow follow-up

- Make **Validate config** a required status check on `main` in the repository settings once it has passed on a real pull request.
- Consider replacing `check-secrets.sh`'s `[A-Za-z0-9+/]{40,}={0,2}` pattern with a dedicated scanner, now that a false positive blocks a pull request rather than only a local commit.
- Archive the change after the project's review requirements are satisfied.
- Verify the archived result.
