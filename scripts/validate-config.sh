#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$REPO_ROOT/config/openclaw.json"
DOCKERFILE="$REPO_ROOT/docker/Dockerfile"

echo "Validating $CONFIG ..."

# 1. Check valid JSON
if ! jq empty "$CONFIG" 2>/dev/null; then
  echo "ERROR: $CONFIG is not valid JSON"
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
OPENCLAW_VERSION="$(sed -nE 's/^ARG OPENCLAW_VERSION=([^[:space:]]+).*/\1/p' "$DOCKERFILE" | head -1)"
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

echo "Checking schema against openclaw@$OPENCLAW_VERSION ($NODE_IMAGE) ..."

# Substitute ${VAR} placeholders with well-formed dummy values in a throwaway
# copy. Some fields (e.g. mcp.servers.*.url) are format-validated, so a literal
# placeholder fails on its syntax. The schema check is about config shape, not
# about resolving secrets, and the real config is never modified.
SUBSTITUTED_CONFIG="$(mktemp "${TMPDIR:-/tmp}/openclaw-config-validate.XXXXXX")"
trap 'rm -f "$SUBSTITUTED_CONFIG"' EXIT
sed -E \
  -e 's#\$\{[A-Za-z0-9_]*URL[A-Za-z0-9_]*\}#https://example.invalid/placeholder#g' \
  -e 's#\$\{[A-Za-z0-9_]+\}#placeholder#g' \
  "$CONFIG" > "$SUBSTITUTED_CONFIG"

set +e
SCHEMA_OUTPUT="$(docker run --rm \
  -v "$SUBSTITUTED_CONFIG:/cfg/openclaw.json:ro" \
  -e OPENCLAW_CONFIG_PATH=/cfg/openclaw.json \
  "$NODE_IMAGE" \
  npx -y "openclaw@$OPENCLAW_VERSION" config validate 2>&1)"
SCHEMA_STATUS=$?
set -e

echo "$SCHEMA_OUTPUT"

if [[ "$SCHEMA_STATUS" -ne 0 ]]; then
  echo "ERROR: openclaw@$OPENCLAW_VERSION rejected $CONFIG"
  exit 1
fi

# 4. Check for legacy keys — drift that has not turned fatal yet.
# `config validate` only reports hard schema errors: it calls a config with
# legacy-only drift "valid" and exits 0. `doctor` names each legacy key but also
# exits 0, so the output is what decides here. COLUMNS keeps doctor's boxed
# output wide enough that the phrase is not wrapped mid-match.
echo "Checking for legacy keys ..."

set +e
DOCTOR_OUTPUT="$(docker run --rm \
  -v "$SUBSTITUTED_CONFIG:/cfg/openclaw.json:ro" \
  -e OPENCLAW_CONFIG_PATH=/cfg/openclaw.json \
  -e COLUMNS=200 \
  "$NODE_IMAGE" \
  npx -y "openclaw@$OPENCLAW_VERSION" doctor --no-color 2>&1)"
set -e

if grep -q "Legacy config keys detected" <<<"$DOCTOR_OUTPUT"; then
  echo "ERROR: openclaw@$OPENCLAW_VERSION reported legacy config keys in $CONFIG"
  grep -A20 "Legacy config keys detected" <<<"$DOCTOR_OUTPUT"
  echo "Migrate each key named above to its canonical shape."
  exit 1
fi

echo "✓ Config validation passed"
