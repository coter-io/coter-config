#!/usr/bin/env bash
set -euo pipefail

# Advisory check: does the shipped config still validate against the newest
# published OpenClaw release? The gateway runs the version pinned in
# docker/Dockerfile, so a rejection here is upgrade-readiness information, not a
# verdict on the current config. Callers must treat a non-zero exit as advisory;
# the pull request gate marks this step continue-on-error for that reason.
#
# Anything that prevents the comparison — no npm, no network, an unparseable
# version — degrades to "no signal" and exits 0. A registry hiccup must not
# look like a config defect.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKERFILE="$REPO_ROOT/docker/Dockerfile"

PINNED="$(sed -nE 's/^ARG OPENCLAW_VERSION=([^[:space:]]+).*/\1/p' "$DOCKERFILE" | head -1)"
if [[ -z "$PINNED" ]]; then
  echo "ADVISORY: could not read the pinned version; skipping the forward-compatibility check."
  exit 0
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "ADVISORY: npm is unavailable; skipping the forward-compatibility check."
  exit 0
fi

echo "Resolving the newest published OpenClaw release ..."
LATEST="$(npm view openclaw version 2>/dev/null | tr -d '[:space:]' || true)"

if [[ ! "$LATEST" =~ ^[0-9][0-9A-Za-z.\-]*$ ]]; then
  echo "ADVISORY: could not resolve the newest published version; skipping the check."
  echo "This is not a config failure — the registry was unreachable or returned something unexpected."
  exit 0
fi

echo "Pinned: $PINNED   Newest published: $LATEST"

if [[ "$LATEST" == "$PINNED" ]]; then
  echo "✓ The pin is already the newest published release; nothing to compare."
  exit 0
fi

echo ""
echo "Validating the shipped config against openclaw@$LATEST (advisory) ..."
echo ""

if OPENCLAW_VERSION_OVERRIDE="$LATEST" bash "$REPO_ROOT/scripts/validate-config.sh"; then
  echo ""
  echo "✓ ADVISORY: the config is also accepted by openclaw@$LATEST."
  echo "  Bumping ARG OPENCLAW_VERSION to $LATEST needs no config change."
  exit 0
fi

echo ""
echo "ADVISORY: openclaw@$LATEST rejects the shipped config (see the findings above)."
echo "This does NOT affect the current deployment — the gateway runs the pinned $PINNED."
echo "Resolve it as part of bumping ARG OPENCLAW_VERSION in docker/Dockerfile."
exit 1
