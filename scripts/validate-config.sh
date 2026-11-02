#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKERFILE="$REPO_ROOT/docker/Dockerfile"

# Defaults to the shipped config. The optional argument exists so the negative
# cases (unrecognized keys, legacy shapes, tolerated drift) can be exercised
# against scratch copies; every gate — pre-commit, pull request, release —
# passes no argument and therefore validates the shipped config.
CONFIG="${1:-$REPO_ROOT/config/openclaw.json}"
if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: $CONFIG does not exist"
  exit 1
fi

echo "Validating $CONFIG ..."

# Every check below fails closed. A validation gate that skips when its tooling
# is missing is how schema drift reached a published image once already.
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required to validate $CONFIG"
  echo "Install it (brew install jq / apt-get install jq) and retry."
  exit 1
fi

# 1. Check valid JSON
if ! JSON_ERROR="$(jq empty "$CONFIG" 2>&1)"; then
  echo "ERROR: $CONFIG is not valid JSON"
  echo "$JSON_ERROR"
  exit 1
fi

# 2. Check for raw API key patterns that should never appear in config
PATTERNS='sk-ant-|sk-proj-|bot[0-9]|bsc_|xai-|gsk_'
if grep -qE "$PATTERNS" "$CONFIG"; then
  echo "ERROR: Raw API key pattern detected in $CONFIG"
  echo "Use \${ENV_VAR} references instead of plaintext keys."
  grep -nE "$PATTERNS" "$CONFIG"
  exit 1
fi

# Mirrors the gateway's IDENTITY.md parser so this gate reads the file the same
# way the runtime does: strip the leading "- ", split at the first colon, drop
# * _ ` from the label, and trim * _ ` and surrounding space from the value.
# A label written "- **Name:** Coter" therefore yields exactly "Coter", and a
# value the runtime would ignore is reported as absent here too.
identity_md_field() {
  awk -v want="$1" '
    { line = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      idx = index(line, ":")
      if (idx == 0) next
      label = substr(line, 1, idx - 1)
      value = substr(line, idx + 1)
      gsub(/[*_`]/, "", label)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", label)
      if (tolower(label) != want) next
      gsub(/^[*_`[:space:]]+|[*_`[:space:]]+$/, "", value)
      if (value == "") next
      print value
      exit
    }' "$2"
}

# 3. Check that the gateway is told not to create workspace bootstrap files.
# Without this key the gateway seeds BOOTSTRAP.md into a fresh workspace and the
# agent's first turn becomes a setup ritual: it asks the user what to call it,
# generates avatar options, and offers plugin installs. The whole point of the
# predefined workspace files is that no user ever sees that.
SKIP_BOOTSTRAP="$(jq -r '.agents.defaults.skipBootstrap' "$CONFIG")"
if [[ "$SKIP_BOOTSTRAP" != "true" ]]; then
  echo "ERROR: agents.defaults.skipBootstrap is not true in $CONFIG (read: $SKIP_BOOTSTRAP)"
  echo "The onboarding ritual would return: the gateway would seed BOOTSTRAP.md"
  echo "into a fresh workspace and the agent's first turn would ask the user for a"
  echo "name, generate avatar options, and offer plugin installs."
  echo 'Set "skipBootstrap": true under agents.defaults.'
  exit 1
fi

# 4. Check that every predefined workspace file reaches the image.
# With bootstrap creation disabled the gateway authors nothing, so a file missing
# here is a file the agent simply does not get — no conventions, no personality,
# no identity. docker/Dockerfile copies this directory into the image and
# docker/entrypoint.sh seeds it into the workspace without clobbering.
#
# This array, in scripts/validate-config.sh, is the single required set. A
# predefined workspace file that is not listed here is not checked by any gate,
# so adding a file to workspace-templates/ without adding it to this array is
# precisely the omission that would go unreported. Keep the two in step.
REQUIRED_WORKSPACE_FILES=(
  "workspace-templates/AGENTS.md"
  "workspace-templates/SOUL.md"
  "workspace-templates/IDENTITY.md"
  "workspace-templates/USER.md"
  "workspace-templates/avatars/avatar.png"
)
MISSING_WORKSPACE_FILES=()
for rel in "${REQUIRED_WORKSPACE_FILES[@]}"; do
  if [[ ! -s "$REPO_ROOT/$rel" ]]; then
    MISSING_WORKSPACE_FILES+=("$rel")
  fi
done
if [[ "${#MISSING_WORKSPACE_FILES[@]}" -gt 0 ]]; then
  echo "ERROR: predefined workspace files are missing or empty:"
  for rel in "${MISSING_WORKSPACE_FILES[@]}"; do
    echo "  - $rel"
  done
  echo "The gateway creates no replacement for these, so the agent would start"
  echo "without them. Restore each file listed above."
  exit 1
fi

# 5. Check that the two places identity is authored agree.
# Displayed identity comes from the config; the agent reads IDENTITY.md to know
# who it is. Nothing syncs them once bootstrap creation is disabled, so a
# disagreement is silent: channels show one identity and the agent believes
# another. The vibe line is held in three places and must match in all of them.
IDENTITY_MD="$REPO_ROOT/workspace-templates/IDENTITY.md"
SOUL_MD="$REPO_ROOT/workspace-templates/SOUL.md"
IDENTITY_MISMATCH=0
for field in name emoji theme avatar; do
  CONFIG_VALUE="$(jq -r --arg f "$field" '.agents.entries.main.identity[$f] // ""' "$CONFIG")"
  FILE_VALUE="$(identity_md_field "$field" "$IDENTITY_MD")"
  if [[ "$CONFIG_VALUE" != "$FILE_VALUE" ]]; then
    echo "ERROR: identity field '$field' disagrees between the two authoring points"
    echo "  config/openclaw.json              : ${CONFIG_VALUE:-<unset>}"
    echo "  workspace-templates/IDENTITY.md   : ${FILE_VALUE:-<unset>}"
    IDENTITY_MISMATCH=1
  fi
done

# Theme wins over Creature and Vibe when the runtime reads IDENTITY.md, so a
# Vibe line that drifts from Theme would leave SOUL.md describing a personality
# the runtime does not use.
IDENTITY_VIBE="$(identity_md_field vibe "$IDENTITY_MD")"
IDENTITY_THEME="$(identity_md_field theme "$IDENTITY_MD")"
if [[ "$IDENTITY_VIBE" != "$IDENTITY_THEME" ]]; then
  echo "ERROR: Vibe and Theme differ in workspace-templates/IDENTITY.md"
  echo "  Vibe : ${IDENTITY_VIBE:-<unset>}"
  echo "  Theme: ${IDENTITY_THEME:-<unset>}"
  IDENTITY_MISMATCH=1
fi

SOUL_VIBE="$(awk '/^## Vibe[[:space:]]*$/ { found = 1; next }
                  found && NF { print; exit }' "$SOUL_MD")"
if [[ "$SOUL_VIBE" != "$IDENTITY_THEME" ]]; then
  echo "ERROR: the vibe line in workspace-templates/SOUL.md does not match IDENTITY.md"
  echo "  SOUL.md ## Vibe : ${SOUL_VIBE:-<unset>}"
  echo "  IDENTITY.md     : ${IDENTITY_THEME:-<unset>}"
  IDENTITY_MISMATCH=1
fi

# The avatar is a workspace-relative path, so it must name a file that actually
# ships. A renamed avatar would otherwise pass the required-set check above.
CONFIG_AVATAR="$(jq -r '.agents.entries.main.identity.avatar // ""' "$CONFIG")"
if [[ -n "$CONFIG_AVATAR" ]]; then
  case "$CONFIG_AVATAR" in
    /* | '~'* | *..*)
      echo "ERROR: identity avatar must be a workspace-relative path: $CONFIG_AVATAR"
      IDENTITY_MISMATCH=1
      ;;
    *)
      if [[ ! -s "$REPO_ROOT/workspace-templates/$CONFIG_AVATAR" ]]; then
        echo "ERROR: identity avatar names a file that does not ship:"
        echo "  workspace-templates/$CONFIG_AVATAR"
        IDENTITY_MISMATCH=1
      fi
      ;;
  esac
fi

if [[ "$IDENTITY_MISMATCH" -ne 0 ]]; then
  echo "Identity is authored in config/openclaw.json and"
  echo "workspace-templates/IDENTITY.md, and the vibe line is repeated in"
  echo "workspace-templates/SOUL.md. Change them together."
  exit 1
fi

# 6. Check the config against the schema of the pinned OpenClaw version.
# The version and node base both come from docker/Dockerfile, so this check and
# the gateway image can never disagree about which schema applies.
# OPENCLAW_VERSION_OVERRIDE exists so check-forward-compat.sh can run this exact
# gate against a different release. Unset — which is how every gate invokes it —
# the version comes from the Dockerfile pin and nowhere else.
OPENCLAW_VERSION="${OPENCLAW_VERSION_OVERRIDE:-$(sed -nE 's/^ARG OPENCLAW_VERSION=([^[:space:]]+).*/\1/p' "$DOCKERFILE" | head -1)}"
if [[ -z "$OPENCLAW_VERSION" ]]; then
  echo "ERROR: Could not read ARG OPENCLAW_VERSION from $DOCKERFILE"
  echo "The schema check needs the pinned version; it will not fall back to an unpinned release."
  exit 1
fi

NODE_IMAGE="$(sed -nE 's/^FROM (node:[^[:space:]]+).*/\1/p' "$DOCKERFILE" | head -1)"
if [[ -z "$NODE_IMAGE" ]]; then
  echo "ERROR: Could not read the node base image from $DOCKERFILE"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is required to validate against openclaw@$OPENCLAW_VERSION"
  echo "The pinned version needs Node >=24.22.1, so the schema check runs in a container."
  echo "Install or start Docker and retry."
  exit 1
fi

# Supply values for the config's ${VAR} placeholders through the environment.
# The pinned runtime expands ${VAR} from the process environment natively, so
# the shipped file is validated exactly as written — there is no substituted
# copy, and nothing here rewrites the real config. Only unset variables are
# defaulted, so real values already in the caller's shell are used when present.
# URL-named variables get a well-formed URL because some fields (e.g.
# mcp.servers.*.url) are format-validated and reject an opaque token.
ENV_ARGS=()
# shellcheck disable=SC2016  # tr deletes the literal characters $ { }, so single quotes are intended
PLACEHOLDERS="$(grep -oE '\$\{[A-Za-z0-9_]+\}' "$CONFIG" | tr -d '${}' | sort -u || true)"
while IFS= read -r var; do
  [[ -z "$var" ]] && continue
  if [[ -n "${!var:-}" ]]; then
    ENV_ARGS+=(-e "$var=${!var}")
  elif [[ "$var" == *URL* ]]; then
    ENV_ARGS+=(-e "$var=https://example.invalid/placeholder")
  else
    ENV_ARGS+=(-e "$var=placeholder")
  fi
done <<< "$PLACEHOLDERS"

# doctor's gateway-auth check reads a token that legitimately lives in the
# environment rather than in the config. Supplying a dummy keeps that check
# running honestly instead of suppressing it below.
ENV_ARGS+=(-e "OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN:-0123456789abcdef0123456789abcdef}")

echo "Checking schema against openclaw@$OPENCLAW_VERSION ($NODE_IMAGE) ..."

set +e
SCHEMA_OUTPUT="$(docker run --rm \
  -v "$CONFIG:/cfg/openclaw.json:ro" \
  -e OPENCLAW_CONFIG_PATH=/cfg/openclaw.json \
  "${ENV_ARGS[@]}" \
  "$NODE_IMAGE" \
  npx -y "openclaw@$OPENCLAW_VERSION" config validate 2>&1)"
SCHEMA_STATUS=$?
set -e

echo "$SCHEMA_OUTPUT"

if [[ "$SCHEMA_STATUS" -ne 0 ]]; then
  echo "ERROR: openclaw@$OPENCLAW_VERSION rejected $CONFIG"
  echo "Each line above names the key at fault and where it sits in the file."
  echo "Run 'openclaw config schema' to inspect the supported shape of that key."
  exit 1
fi

# 7. Check for defects the schema accepts but the runtime considers unhealthy.
# `config validate` above reports hard errors and renamed keys, but accepts a
# config that is structurally fine and still wrong — a hardcoded credential in a
# secret-bearing field validates as a string and is reported only here, as
# core/doctor/security at warning severity. That class surfaces only as a health
# finding, so the structured lint runs too — and it runs second, because
# doctor short-circuits after a failed config validation (measured: checksRun=1)
# and would report nothing about the other checks.
#
# The lint's exit code does not track its own verdict: measured against
# 2026.10.7, a config with a severity:error finding exited 0 while a clean
# config exited 1 on an unrelated network check. So the JSON payload decides and
# the exit code is deliberately ignored.
#
# Skipped checks describe the environment validation runs in, not the config:
#   runtime-tool-schemas        — dials the configured MCP endpoint over the network
#   heartbeat-cadence-migration — wants runtime cron state that lives on the VPS
#   node-hosting-preconditions  — flags loopback bind, but --bind lan comes from compose
echo "Checking health findings against openclaw@$OPENCLAW_VERSION ..."

set +e
DOCTOR_OUTPUT="$(docker run --rm \
  -v "$CONFIG:/cfg/openclaw.json:ro" \
  -e OPENCLAW_CONFIG_PATH=/cfg/openclaw.json \
  "${ENV_ARGS[@]}" \
  "$NODE_IMAGE" \
  npx -y "openclaw@$OPENCLAW_VERSION" doctor --lint --json \
    --severity-min warning \
    --skip core/doctor/runtime-tool-schemas \
    --skip core/doctor/heartbeat-cadence-migration \
    --skip core/doctor/node-hosting-preconditions 2>/dev/null)"
set -e

DOCTOR_JSON="$(grep -E '^\{' <<<"$DOCTOR_OUTPUT" | tail -1 || true)"

if [[ -z "$DOCTOR_JSON" ]] || ! jq empty <<<"$DOCTOR_JSON" 2>/dev/null; then
  echo "ERROR: could not read health findings from openclaw@$OPENCLAW_VERSION"
  echo "The lint produced no JSON payload to judge, so validation cannot pass."
  echo "$DOCTOR_OUTPUT"
  exit 1
fi

DOCTOR_OK="$(jq -r '.ok' <<<"$DOCTOR_JSON")"
FINDING_COUNT="$(jq -r '.findings | length' <<<"$DOCTOR_JSON")"

if [[ "$DOCTOR_OK" != "true" ]] || [[ "$FINDING_COUNT" -ne 0 ]]; then
  echo "ERROR: openclaw@$OPENCLAW_VERSION reported health findings for $CONFIG"
  jq -r '.findings[]
    | "  - [\(.severity)] \(.path // "config"): \(.message)"
      + "\n    fix: \(.fixHint // "see openclaw doctor output")"
      + "\n    check: \(.checkId)"' <<<"$DOCTOR_JSON"
  echo "Migrate each key named above to its canonical shape."
  exit 1
fi

echo "✓ Config validation passed"
