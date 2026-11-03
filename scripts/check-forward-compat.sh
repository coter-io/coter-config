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

# The release to compare against. Defaults to the newest published one;
# OPENCLAW_FORWARD_TARGET names a specific release instead, which is how the
# starter-template check below is exercised against a chosen version.
TARGET="${OPENCLAW_FORWARD_TARGET:-$LATEST}"
if [[ "$TARGET" != "$LATEST" ]]; then
  echo "Target overridden: $TARGET"
fi

###############################################################################
# Starter-template drift.
#
# The predefined workspace files in workspace-templates/ were derived from the
# pinned release's starter templates and then customized, so comparing them to
# upstream directly would report drift on every run — they are meant to differ.
# scripts/upstream-templates.sha256 records what those templates looked like
# when the files were derived, and this check compares the target release's
# templates against that record. What it reports is upstream changing out from
# under the predefined copies, which is the thing a version bump must not miss.
#
# Advisory like the rest of this script: anything that prevents the comparison
# degrades to "no signal".
###############################################################################

# Top-level templates this repository deliberately does not predefine.
# BOOTSTRAP.md is the onboarding ritual itself — shipping it would undo the
# whole point. The others are optional workspace files the agent or operator
# adds if they are ever wanted. A template that is neither predefined nor
# listed here is reported, so a genuinely new upstream file gets noticed.
KNOWN_NOT_PREDEFINED=(
  "BOOTSTRAP.md"
  "BOOT.md"
  "HEARTBEAT.md"
  "TOOLS.md"
)

# Strips a leading YAML front matter block and the blank lines after it, which
# is what the gateway does when it loads a template. Hashing the body keeps a
# reworded front-matter summary from being reported as a template change.
template_body() {
  awk '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---"   { in_fm = 0; next }
    in_fm                  { next }
    !started && $0 ~ /^[[:space:]]*$/ { next }
    { started = 1; print }
  ' "$1"
}

TEMPLATE_DRIFT=0
BASELINE="$REPO_ROOT/scripts/upstream-templates.sha256"

if [[ ! -f "$BASELINE" ]]; then
  echo "ADVISORY: $BASELINE is missing; skipping the starter-template check."
elif ! command -v shasum >/dev/null 2>&1 && ! command -v sha256sum >/dev/null 2>&1; then
  echo "ADVISORY: no sha256 tool available; skipping the starter-template check."
else
  echo ""
  echo "Comparing openclaw@$TARGET starter templates against the recorded baseline ..."

  TEMPLATE_WORK="$(mktemp -d)"
  # shellcheck disable=SC2064  # expand TEMPLATE_WORK now, so cleanup is pinned to this directory
  trap "rm -rf '$TEMPLATE_WORK'" EXIT

  if ! npm pack "openclaw@$TARGET" --pack-destination "$TEMPLATE_WORK" --silent >/dev/null 2>&1; then
    echo "ADVISORY: could not download openclaw@$TARGET; skipping the starter-template check."
  else
    TARBALL="$(find "$TEMPLATE_WORK" -maxdepth 1 -name '*.tgz' -print -quit)"
    EXTRACT_ROOT="$TEMPLATE_WORK/extracted"
    # Split rather than one long literal: scripts/check-secrets.sh flags any run
    # of 40+ characters from [A-Za-z0-9+/] as possible base64, and "/" is in that
    # class, so a long slash-separated path reads as a leaked token.
    TEMPLATE_DIR="$EXTRACT_ROOT/package/docs/reference/templates"
    mkdir -p "$EXTRACT_ROOT"
    # A directory path, not a wildcard: BSD tar and GNU tar disagree about
    # pattern matching but both extract a named directory recursively.
    if [[ -z "$TARBALL" ]] || ! tar -xzf "$TARBALL" -C "$EXTRACT_ROOT" \
        package/docs/reference/templates 2>/dev/null || [[ ! -d "$TEMPLATE_DIR" ]]; then
      echo "ADVISORY: could not read the starter templates from openclaw@$TARGET; skipping the check."
    else
      sha256_of() {
        if command -v sha256sum >/dev/null 2>&1; then
          sha256sum | cut -d' ' -f1
        else
          shasum -a 256 | cut -d' ' -f1
        fi
      }

      # 1. Did a template the predefined files derive from change upstream?
      while read -r expected name; do
        [[ -z "$expected" || "$expected" == \#* ]] && continue
        if [[ ! -f "$TEMPLATE_DIR/$name" ]]; then
          echo "  ! $name is no longer published by openclaw@$TARGET"
          TEMPLATE_DRIFT=1
          continue
        fi
        # Truncated to match the baseline's digest length; see the header of
        # scripts/upstream-templates.sha256 for why it is not the full digest.
        actual="$(template_body "$TEMPLATE_DIR/$name" | sha256_of | cut -c1-32)"
        if [[ "$actual" != "$expected" ]]; then
          echo "  ! $name changed upstream since the baseline was recorded"
          echo "      baseline: $expected"
          echo "      $TARGET: $actual"
          TEMPLATE_DRIFT=1
        fi
      done < "$BASELINE"

      # 2. Does the target expect a workspace file this repository does not ship?
      for template in "$TEMPLATE_DIR"/*.md; do
        [[ -f "$template" ]] || continue
        name="$(basename "$template")"
        case "$name" in
          *.dev.md) continue ;;
        esac
        if grep -qE "[[:space:]]$name\$" "$BASELINE"; then
          continue
        fi
        known=0
        for excluded in "${KNOWN_NOT_PREDEFINED[@]}"; do
          [[ "$name" == "$excluded" ]] && known=1 && break
        done
        if [[ "$known" -eq 0 ]]; then
          echo "  ! $name is a starter template openclaw@$TARGET ships that this repository does not predefine"
          TEMPLATE_DRIFT=1
        fi
      done

      if [[ "$TEMPLATE_DRIFT" -eq 0 ]]; then
        echo "✓ No starter-template drift: the predefined files still match what they were derived from."
      else
        echo ""
        echo "ADVISORY: review each item above before raising ARG OPENCLAW_VERSION."
        echo "Fold the upstream change into workspace-templates/ by hand, then refresh"
        echo "scripts/upstream-templates.sha256 in the same commit."
      fi
    fi
  fi

  rm -rf "$TEMPLATE_WORK"
  trap - EXIT
fi


if [[ "$TARGET" == "$PINNED" ]]; then
  echo ""
  echo "✓ The pin is already the target release; no config comparison to make."
  exit "$TEMPLATE_DRIFT"
fi

echo ""
echo "Validating the shipped config against openclaw@$TARGET (advisory) ..."
echo ""

if OPENCLAW_VERSION_OVERRIDE="$TARGET" bash "$REPO_ROOT/scripts/validate-config.sh"; then
  echo ""
  echo "✓ ADVISORY: the config is also accepted by openclaw@$TARGET."
  if [[ "$TEMPLATE_DRIFT" -eq 0 ]]; then
    echo "  Bumping ARG OPENCLAW_VERSION to $TARGET needs no config change."
    exit 0
  fi
  echo "  The config is fine, but the starter-template drift reported above"
  echo "  still needs review before the bump."
  exit 1
fi

echo ""
echo "ADVISORY: openclaw@$TARGET rejects the shipped config (see the findings above)."
echo "This does NOT affect the current deployment — the gateway runs the pinned $PINNED."
echo "Resolve it as part of bumping ARG OPENCLAW_VERSION in docker/Dockerfile."
exit 1
