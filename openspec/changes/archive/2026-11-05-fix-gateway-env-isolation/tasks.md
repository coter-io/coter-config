# Tasks

## 1. Stop the blanket injection in the deployment compose file

- [x] 1.1 Remove `env_file: .env` from the `openclaw-gateway` service in `docker/docker-compose.yml`, with a comment naming why it is absent and pointing at the directory pins; verify with `docker compose -f docker/docker-compose.yml config` that the rendered gateway service has no `env_file` key and that the `image:` reference and both bind-mount sources still render their interpolated values
- [x] 1.2 Add `OPENCLAW_CONFIG_DIR: /home/node/.openclaw` and `OPENCLAW_WORKSPACE_DIR: /home/node/.openclaw/workspace` to that service's `environment:` block, with a comment naming them as pins that must stay equal to the mount targets; verify the rendered config shows both equal to the `volumes:` targets declared in the same service
- [x] 1.3 Confirm `workspace-sync` still carries no `env_file` and renders only its four declared variables; verify from the same rendered config

## 2. Document which variables describe the host

- [x] 2.1 In `docker/.env.example`, rewrite the Directories section to state that both values are host filesystem paths compose consumes for bind-mount sources and are not passed to the container; verify `bash scripts/check-env-vars.sh` still passes, since the declared names are unchanged
- [x] 2.2 In `CONTRIBUTING.md`, extend the environment-variable contract section to state that a variable reaching the gateway must be named in the deployment compose file's `environment:` block, and that adding a `${VAR}` to `config/openclaw.json` requires naming it there too; verify the documented commands in that section run as written

## 3. Enforce the invariant the removal depends on

- [x] 3.1 Extend `scripts/check-env-vars.sh` with a check that every `${VAR}` referenced by `config/openclaw.json` appears as a key in the gateway service's `environment:` block in `docker/docker-compose.yml`, reading that block specifically so a name appearing only as a bind-mount source does not satisfy it; verify `bash scripts/check-env-vars.sh` passes against the current tree
- [x] 3.2 Make that check fail closed and name the defect: verify by temporarily adding a `${SOME_UNPASSED_VAR}` reference to `config/openclaw.json` and confirming the script exits non-zero and names both the variable and the compose block that must declare it, then revert the edit
- [x] 3.3 Verify the check does not accept a false positive: temporarily name a config-referenced variable only in the `volumes:` section rather than `environment:`, confirm the script still fails, then revert
- [x] 3.4 Correct the comment and the operator-facing message in the "set but not declared" branch of `scripts/check-env-file.sh`, which justifies its warning severity with the claim that an undeclared name reaches no container — true only once `env_file` is gone; keep it a warning and verify `bash scripts/check-env-file.sh .env` still passes on the project `.env`

## 4. Reconcile the local override with the shipped file

- [x] 4.1 Update the comment block in `docker/docker-compose.local.yml` that explains the inherited `env_file: .env` as sufficient and load-bearing, so it describes the shipped file as it now is; verify by reading it against `docker/docker-compose.yml` that no statement about `env_file` remains that the shipped file contradicts
- [x] 4.2 Decide and record whether the local override keeps its own `OPENCLAW_CONFIG_DIR` and `OPENCLAW_WORKSPACE_DIR` pins now that the shipped file carries them, keeping the local mount targets correct either way; verify `docker compose -f docker/docker-compose.yml -f docker/docker-compose.local.yml --project-directory . config` renders both variables equal to the local mount targets

## 5. Verify the whole path locally

- [x] 5.1 Bring the local stack up with `./local.sh` and verify it reaches a running gateway with no preflight failure
- [x] 5.2 Run `docker compose ... exec openclaw-gateway env` against the local stack and verify `OPENCLAW_CONFIG_DIR`, `OPENCLAW_WORKSPACE_DIR` and `HOME` all name in-container paths, and that no variable declared in the project `.env` for host use appears
- [x] 5.3 Verify every credential `config/openclaw.json` references is present and non-empty in that same environment output, confirming the enumerated block replaced what `env_file` was supplying
- [x] 5.4 Exercise an inbound message end to end against the local stack and verify it is answered rather than dead-lettered, with no `EACCES` in the gateway logs
- [x] 5.5 Run `bash scripts/validate-config.sh`, `bash scripts/check-env-vars.sh`, `bash scripts/check-secrets.sh` and `bash scripts/check-env-file.sh .env` and verify all four pass

## Workflow follow-up

Deployment to the VPS is carried out by the separate infra repository and cannot be completed from this change. These steps follow the design's Migration Plan and belong in the deployment runbook:

- Capture `docker compose exec openclaw-gateway env` on the VPS as the before-state, before replacing the compose file.
- Confirm the host directory behind the mount (`/home/openclaw/.openclaw`) is owned by uid 1000, since writes land there once the paths are corrected.
- Decide whether to clear the Telegram update spool or let it replay; spooled updates will be answered as a burst of belated replies on the first successful start. This is design.md's open question and is the operator's call.
- Replace `docker/docker-compose.yml` on the VPS and recreate the gateway service.
- Capture the environment again and diff against the before-state: the four host-side and undeclared names must be gone, and no credential the config references may have disappeared.
- Confirm the gateway answers on `127.0.0.1:18789`, given that `OPENCLAW_GATEWAY_BIND=0.0.0.0` no longer reaches the container and the shipped `command:` passes `--bind lan`.
- Send a message and confirm a reply, with no `EACCES` in the logs.
- Rotate `OPENCLAW_GATEWAY_TOKEN` if the value observed during diagnosis was the real one rather than a redaction. Unrelated to this change, surfaced by it.
- Archive the change once the deployment is verified.
