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

# 3. Check the config against the schema of the pinned OpenClaw version.
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

# 4. Check for defects the schema accepts but the runtime considers unhealthy.
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
