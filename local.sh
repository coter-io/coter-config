#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Local development stack.
#
#   ./local.sh            bring the stack up and follow its logs
#   ./local.sh up         same
#   ./local.sh down       stop and remove the containers (state is kept)
#   ./local.sh logs       follow the logs of a running stack
#   ./local.sh shell      a shell inside the running gateway
#   ./local.sh reset      discard all local state (config dir and workspace)
#   ./local.sh validate   run the full config validation (slow; not run by up)
#
# This runs the shipped artifacts as shipped: config/openclaw.json,
# docker/Dockerfile and docker/docker-compose.yml are used unmodified, with
# docker/docker-compose.local.yml layered on top for the deltas a developer
# machine needs. Nothing here can affect a deployment.
#
# Prerequisite: a SECOND Telegram bot. Telegram allows one getUpdates consumer
# per bot token, so sharing the deployed bot's token makes both gateways
# contend for the long poll and the deployed one drop messages.
###############################################################################

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

ENV_FILE="$REPO_ROOT/.env"
ENV_EXAMPLE="$REPO_ROOT/docker/.env.example"
STATE_DIR="${OPENCLAW_LOCAL_STATE_DIR:-$REPO_ROOT/.local}"
CONFIG_STATE="$STATE_DIR/openclaw"
WORKSPACE_STATE="$STATE_DIR/workspace"
PROJECT_NAME="coter-local"
SERVICE="openclaw-gateway"

# Both compose files, in order. The deployment file carries the real service
# definition; the local file carries only deltas.
COMPOSE_FILES=(-f "$REPO_ROOT/docker/docker-compose.yml" -f "$REPO_ROOT/docker/docker-compose.local.yml")

# --project-directory is not cosmetic: compose resolves relative paths in both
# compose files against it, including the local file's build context and both
# files' bind-mount sources. --env-file covers a different mechanism (${VAR}
# interpolation) and must name the same file.
#
# Neither compose file carries `env_file:` any more — the gateway receives only
# what its `environment:` block names, so the root .env reaches the container
# through no route at all. It is still read here, for interpolation only.
compose() {
  docker compose \
    --project-name "$PROJECT_NAME" \
    --project-directory "$REPO_ROOT" \
    --env-file "$ENV_FILE" \
    "${COMPOSE_FILES[@]}" \
    "$@"
}

die() {
  echo "ERROR: $1" >&2
  shift
  for line in "$@"; do
    echo "       $line" >&2
  done
  exit 1
}

###############################################################################
# Preflight. Fails closed, cheapest check first, nothing built or started until
# every precondition holds.
###############################################################################
preflight() {
  if ! command -v docker >/dev/null 2>&1; then
    die "docker is not installed" \
      "Install Docker Desktop, then retry."
  fi

  if ! docker info >/dev/null 2>&1; then
    die "the Docker daemon is not reachable" \
      "Start Docker Desktop and wait for it to report running, then retry."
  fi

  # Seed rather than start: an absent .env means no credentials, and starting
  # with empty ones produces a gateway that fails at runtime instead of here.
  if [[ ! -f "$ENV_FILE" ]]; then
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    die "no .env found, so one was created from docker/.env.example" \
      "Fill it in, then retry. It is gitignored." \
      "" \
      "Set TELEGRAM_BOT_TOKEN to a SECOND bot's token, not the deployed bot's." \
      "Generate OPENCLAW_GATEWAY_TOKEN with: openssl rand -hex 32"
  fi

  # Checks that the file actually satisfies docker/.env.example, which is what
  # catches a required variable left blank and a value set under a name nothing
  # reads. Its own output names each defect.
  # Its own output names each defect and what to do, so adding a second error
  # line here would only repeat it.
  if ! "$REPO_ROOT/scripts/check-env-file.sh" "$ENV_FILE"; then
    exit 1
  fi
}

###############################################################################
# Deliver the configuration the way a deployment delivers it.
#
# The gateway image does not contain config/openclaw.json; on the VPS the infra
# repo's `make push-config` SCPs config/* into ~/.openclaw, which compose
# bind-mounts. This is the local equivalent, with the same overwrite semantics:
# the repository's copy wins on every start. Only config/* is replaced, so the
# gateway's own session and credential state under the config dir survives.
###############################################################################
push_config() {
  mkdir -p "$CONFIG_STATE" "$WORKSPACE_STATE"
  cp -f "$REPO_ROOT"/config/* "$CONFIG_STATE"/
  echo "[local] config/* -> ${CONFIG_STATE#"$REPO_ROOT"/}/"
}

###############################################################################
# What the local stack is about to do, before it does it. The bot token prefix
# is the one guard against polling with the deployed bot's credential: this
# script cannot detect that on its own, because the deployed secrets do not
# exist on this machine.
###############################################################################
banner() {
  local token prefix
  token="$(grep -E '^[[:space:]]*TELEGRAM_BOT_TOKEN=' "$ENV_FILE" | tail -1 | cut -d= -f2- || true)"
  prefix="${token%%:*}"
  echo "[local] compose project : $PROJECT_NAME"
  echo "[local] state directory : ${STATE_DIR#"$REPO_ROOT"/}"
  echo "[local] image           : coter-openclaw-gateway:local (native arch, not deployable)"
  echo "[local] telegram bot id : ${prefix:-<unset>} — confirm this is your DEV bot, not the deployed one"
  echo ""
}

cmd_up() {
  preflight
  banner
  push_config
  compose up --build -d
  echo ""
  echo "[local] gateway up. Control UI: http://localhost:18789"
  echo "[local] following logs; Ctrl-C detaches without stopping the stack."
  echo ""
  compose logs -f "$SERVICE"
}

cmd_down() {
  compose down
}

cmd_logs() {
  compose logs -f "$SERVICE"
}

cmd_shell() {
  compose exec "$SERVICE" bash
}

cmd_reset() {
  if [[ ! -d "$STATE_DIR" ]]; then
    echo "[local] no state to reset at ${STATE_DIR#"$REPO_ROOT"/}"
    return 0
  fi
  echo "This permanently deletes $STATE_DIR"
  echo "including the gateway's workspace, its installed skills and its session state."
  read -r -p "Type 'reset' to confirm: " reply
  if [[ "$reply" != "reset" ]]; then
    echo "[local] aborted; nothing was deleted."
    return 1
  fi
  compose down 2>/dev/null || true
  rm -rf "$STATE_DIR"
  echo "[local] state discarded. The next 'up' recreates it."
}

# Deliberately separate from up: this costs two container starts and two
# `npx -y openclaw@<pinned>` installs, and the pre-commit hook and the pull
# request gate already run it. Keeping it off the bring-up path is the point.
cmd_validate() {
  "$REPO_ROOT/scripts/validate-config.sh"
  echo ""
  "$REPO_ROOT/scripts/check-env-vars.sh"
}

case "${1:-up}" in
  up)       cmd_up ;;
  down)     cmd_down ;;
  logs)     cmd_logs ;;
  shell)    cmd_shell ;;
  reset)    cmd_reset ;;
  validate) cmd_validate ;;
  -h | --help | help)
    sed -n '5,22p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    die "unknown command: $1" "Run './local.sh help' for the available commands."
    ;;
esac
