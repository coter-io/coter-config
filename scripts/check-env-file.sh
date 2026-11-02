#!/usr/bin/env bash
set -euo pipefail

# Compares a filled-in environment file against the contract docker/.env.example
# declares. check-env-vars.sh checks that every variable the config and the
# deployment compose file reference is *documented*; this checks that the file an
# operator actually supplies *satisfies* that documentation. Nothing checked the
# latter before, which is how docker/.env came to declare BRAVE_SEARCH_API_KEY
# while compose injects BRAVE_API_KEY — a plausible-looking name reaching nothing.
#
# Required vs optional comes from the deployment compose file rather than from a
# list maintained here, so the two cannot disagree: a variable interpolated
# without a default is one the stack cannot start without, and compose already
# marks those with :? .

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${1:-$REPO_ROOT/.env}"
EXAMPLE="$REPO_ROOT/docker/.env.example"
COMPOSE="$REPO_ROOT/docker/docker-compose.yml"

echo "Checking $ENV_FILE against the documented contract ..."

# Fail closed. This is a three-way comparison; a missing input would otherwise
# make the check pass by having nothing to compare.
for file in "$ENV_FILE" "$EXAMPLE" "$COMPOSE"; do
  if [[ ! -r "$file" ]]; then
    echo "ERROR: $file is missing or unreadable"
    echo "The environment file, docker/.env.example and docker/docker-compose.yml are"
    echo "all required; this check will not pass on a partial comparison."
    exit 1
  fi
done

# Whole-line comments only. Stripping from '#' to end of line — which is safe in
# compose and in .env.example, where values are empty — would truncate a real
# value containing '#' here and report it as unset.
strip_comments() {
  grep -vE '^[[:space:]]*#' "$1" || true
}

# Names declared by the documentation. Comments are dropped first so the
# commented-out multi-agent examples in .env.example do not count as declared.
DECLARED="$(strip_comments "$EXAMPLE" \
  | grep -oE '^[A-Za-z0-9_]+=' | tr -d '=' | sort -u || true)"

# Names the environment file mentions at all, and the subset carrying a value.
# An empty assignment is deliberately not a value: a required credential left
# blank reaches the container as an empty string and fails at runtime instead of
# at startup, which is the whole class of defect this check exists to catch.
ENV_BODY="$(strip_comments "$ENV_FILE")"
PRESENT="$(grep -oE '^[[:space:]]*[A-Za-z0-9_]+=' <<<"$ENV_BODY" \
  | sed -E 's/^[[:space:]]*([A-Za-z0-9_]+)=$/\1/' | sort -u || true)"
FILLED="$(grep -E '^[[:space:]]*[A-Za-z0-9_]+=.+' <<<"$ENV_BODY" \
  | sed -E 's/^[[:space:]]*([A-Za-z0-9_]+)=.*/\1/' | sort -u || true)"

# Variables the deployment compose file interpolates without a default. The
# modifier is read from the characters immediately after the variable name, not
# by searching the whole interpolation: one of the :? messages contains
# "openssl rand -hex 32", so matching a bare '-' anywhere would misread a
# required variable as having a default.
REQUIRED_RAW=""
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  body="${ref#\$\{}"
  body="${body%\}}"
  name="${body%%[^A-Za-z0-9_]*}"
  modifier="${body#"$name"}"
  case "$modifier" in
    "" | ":?"* | "?"*) REQUIRED_RAW="${REQUIRED_RAW}${name}"$'\n' ;;
  esac
done <<< "$(strip_comments "$COMPOSE" | grep -oE '\$\{[A-Za-z0-9_]+[^}]*\}' || true)"
REQUIRED="$(grep -v '^$' <<<"$REQUIRED_RAW" | sort -u || true)"

MISSING=0
WARNED=0

while IFS= read -r var; do
  [[ -z "$var" ]] && continue
  grep -Fxq "$var" <<<"$FILLED" && continue

  if grep -Fxq "$var" <<<"$PRESENT"; then
    echo "  - $var is declared but empty"
    echo "      docker/docker-compose.yml interpolates it with no default, so the stack"
    echo "      cannot start without a value. See docker/.env.example for where to get one."
  else
    echo "  - $var is missing"
    echo "      docker/docker-compose.yml interpolates it with no default."
    echo "      Add it to $ENV_FILE; docker/.env.example names where to get its value."
  fi
  MISSING=1
done <<< "$REQUIRED"

# A name set here but documented nowhere reaches no container. Reported rather
# than fatal: .env legitimately carries values consumed outside compose and the
# config, exactly as .env.example documents some (GHCR_USERNAME is read by
# compose's image reference, not by a container).
while IFS= read -r var; do
  [[ -z "$var" ]] && continue
  if ! grep -Fxq "$var" <<<"$DECLARED"; then
    echo "  ! $var is set but not declared in docker/.env.example"
    echo "      Nothing reads this name. Check it against the declared spelling —"
    echo "      a near-miss (BRAVE_SEARCH_API_KEY vs BRAVE_API_KEY) silently reaches nothing."
    WARNED=1
  fi
done <<< "$PRESENT"

if [[ "$MISSING" -eq 1 ]]; then
  echo ""
  echo "ERROR: $ENV_FILE does not satisfy the documented contract"
  echo "Set each variable listed above, then retry."
  exit 1
fi

if [[ "$WARNED" -eq 1 ]]; then
  echo "✓ Every required variable is set (with warnings above)"
else
  echo "✓ Environment file satisfies the documented contract"
fi
