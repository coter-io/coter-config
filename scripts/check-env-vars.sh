#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$REPO_ROOT/config/openclaw.json"
# The deployment compose file, and deliberately only that one. The contract
# describes what an operator must supply to get a working *deployment*, so a
# compose file no deployment consumes — docker/docker-compose.local.yml, which
# only local.sh ever passes — is outside it, and the local-only variables it
# interpolates are not required to appear in docker/.env.example. Keep those
# confined to local paths nothing deployed reads; anything a deployment needs
# belongs in the file named here, where this check sees it.
COMPOSE="$REPO_ROOT/docker/docker-compose.yml"
ENV_EXAMPLE="$REPO_ROOT/docker/.env.example"

echo "Checking environment variable contract ..."

# Fail closed. The contract is a three-way comparison; a missing input would
# otherwise make the check pass by having nothing to compare.
for file in "$CONFIG" "$COMPOSE" "$ENV_EXAMPLE"; do
  if [[ ! -r "$file" ]]; then
    echo "ERROR: $file is missing or unreadable"
    echo "All three of config/openclaw.json, docker/docker-compose.yml and"
    echo "docker/.env.example are required; this check will not pass on a partial comparison."
    exit 1
  fi
done

# Comments are stripped from compose and from .env.example before anything is
# extracted, and they are stripped on both sides for the same reason. The
# commented-out multi-agent block in docker-compose.yml references
# GIT_WORKSPACE_REPO_SECOND, and .env.example documents it as a commented
# example. Reading comments on one side only would report drift that does not
# exist; ignoring them on both keeps the documented multi-agent recipe intact.
# config/openclaw.json needs no stripping — JSON has no comments.
# shellcheck disable=SC2016  # tr deletes the literal characters $ { }, so single quotes are intended
CONFIG_REFS="$(grep -oE '\$\{[A-Za-z0-9_]+\}' "$CONFIG" | tr -d '${}' | sort -u || true)"
COMPOSE_REFS="$(sed 's/#.*//' "$COMPOSE" \
  | grep -oE '\$\{[A-Za-z0-9_]+' | sed 's/^\${//' | sort -u || true)"
DECLARED="$(sed 's/#.*//' "$ENV_EXAMPLE" \
  | grep -oE '^[A-Za-z0-9_]+=' | tr -d '=' | sort -u || true)"

# Keys of the gateway service's `environment:` block, and deliberately only that
# block. Since docker-compose.yml carries no `env_file:` for that service, this
# block is the *only* route a variable has into the container: a name appearing
# elsewhere in the file — as a bind-mount source, say, the way
# OPENCLAW_CONFIG_DIR does — must not count as passed through, so this cannot be
# a grep over the whole file.
#
# Parsed as text rather than with `docker compose config` on purpose. This check
# runs in the pre-commit hook and as the gate's first offline step, before the
# compose file is validated, and `config` needs Docker plus a value for every
# variable marked :? . The parse tracks indentation: a 2-space key opens a
# service, a 4-space key under the gateway opens or closes its environment
# block, and 6-space keys inside it are the names passed to the container.
GATEWAY_ENV_KEYS="$(sed 's/#.*//' "$COMPOSE" | awk '
  /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
    service = $1; sub(/:$/, "", service); in_env = 0; next
  }
  service != "openclaw-gateway" { next }
  /^    environment:[[:space:]]*$/ { in_env = 1; next }
  /^    [A-Za-z0-9_-]+:/ { in_env = 0 }
  in_env && /^      [A-Za-z0-9_]+:/ {
    key = $1; sub(/:$/, "", key); print key
  }
' | sort -u || true)"

# Fail closed. An empty result means the parse found no gateway environment
# block — a renamed service, a reindented file — not that the block is empty.
# Reporting every referenced variable as unpassed would be a true failure for
# the wrong reason, so name the real one.
if [[ -z "$GATEWAY_ENV_KEYS" ]]; then
  echo "ERROR: could not read the openclaw-gateway service's environment: block in"
  echo "docker/docker-compose.yml. This check compares that block against the"
  echo "\${VAR} references in config/openclaw.json and will not pass without it."
  echo "If the service was renamed or reindented, update the parse in $0."
  exit 1
fi

# True when every _-delimited token of $1 also appears in $2. Used to tell a
# misspelling apart from a genuinely new variable: BRAVE_API_KEY against
# BRAVE_SEARCH_API_KEY is a subset and worth flagging, while TELEGRAM_USER_ID
# against TELEGRAM_BOT_TOKEN merely shares a prefix and is not.
tokens_subset() {
  local haystack token
  haystack="$(tr '_' ' ' <<<"$2")"
  for token in $(tr '_' ' ' <<<"$1"); do
    grep -qw -- "$token" <<<"$haystack" || return 1
  done
  return 0
}

# The comparison is one-directional: every referenced name must be declared. A
# declared-but-unreferenced name is not a failure, because .env.example
# legitimately documents values consumed by neither file — ANTHROPIC_API_KEY
# reaches the container for fallback model access, and GHCR_USERNAME is consumed
# by compose's image reference rather than by a container.
MISSING=0

while IFS= read -r var; do
  [[ -z "$var" ]] && continue
  if grep -Fxq "$var" <<<"$DECLARED"; then
    continue
  fi

  WHERE=""
  if grep -Fxq "$var" <<<"$CONFIG_REFS"; then
    WHERE="config/openclaw.json"
  fi
  if grep -Fxq "$var" <<<"$COMPOSE_REFS"; then
    if [[ -n "$WHERE" ]]; then
      WHERE="$WHERE and docker/docker-compose.yml"
    else
      WHERE="docker/docker-compose.yml"
    fi
  fi

  echo "  - $var"
  echo "      referenced by: $WHERE"
  echo "      must be declared in: docker/.env.example"

  # A name that differs between files shows up here as undeclared while its
  # other spelling sits in .env.example unreferenced. Surface that pairing so
  # the fix is a rename rather than a second variable.
  NEAR=""
  while IFS= read -r candidate; do
    [[ -z "$candidate" ]] && continue
    if tokens_subset "$var" "$candidate" || tokens_subset "$candidate" "$var"; then
      NEAR="${NEAR:+$NEAR }$candidate"
    fi
  done <<< "$DECLARED"
  if [[ -n "$NEAR" ]]; then
    echo "      possible misspelling of: $NEAR — reconcile to one name, do not add a second"
  fi

  MISSING=1
done <<< "$(printf '%s\n%s\n' "$CONFIG_REFS" "$COMPOSE_REFS" | sort -u)"

if [[ "$MISSING" -eq 1 ]]; then
  echo ""
  echo "ERROR: environment variables are referenced but not documented"
  echo "Declare each name listed above in docker/.env.example, together with the source"
  echo "an operator uses to obtain its value. CONTRIBUTING.md requires this, and an"
  echo "undocumented variable reaches the container empty."
fi

# Second comparison: every variable the gateway's own config references must be
# passed into the gateway. Being documented in .env.example is not enough and
# being interpolated somewhere in the compose file is not enough either — with
# no `env_file:` on that service, a referenced variable the environment: block
# does not name arrives in the container as an empty string, and the gateway
# fails at runtime on a config value that looks correct in every file.
#
# Reported alongside the check above rather than after an early exit, so one run
# surfaces both kinds of drift.
UNPASSED=0

while IFS= read -r var; do
  [[ -z "$var" ]] && continue
  grep -Fxq "$var" <<<"$GATEWAY_ENV_KEYS" && continue

  echo "  - $var"
  echo "      referenced by: config/openclaw.json"
  echo "      must be named in: the openclaw-gateway service's environment: block"
  echo "                        in docker/docker-compose.yml"
  if grep -Fxq "$var" <<<"$COMPOSE_REFS"; then
    echo "      note: the name appears elsewhere in docker/docker-compose.yml, but only"
    echo "            the environment: block passes a value into the container"
  fi
  UNPASSED=1
done <<< "$CONFIG_REFS"

if [[ "$UNPASSED" -eq 1 ]]; then
  echo ""
  echo "ERROR: config/openclaw.json references variables the gateway is not given"
  echo "Add each name listed above to the openclaw-gateway service's environment: block"
  echo "in docker/docker-compose.yml. That service carries no env_file:, so the block is"
  echo "the only route a variable has into the container; an unlisted one reaches the"
  echo "gateway empty. CONTRIBUTING.md requires this."
fi

if [[ "$MISSING" -eq 1 || "$UNPASSED" -eq 1 ]]; then
  exit 1
fi

echo "✓ Environment variable contract satisfied"
