#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$REPO_ROOT/config/openclaw.json"
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
  exit 1
fi

echo "✓ Environment variable contract satisfied"
