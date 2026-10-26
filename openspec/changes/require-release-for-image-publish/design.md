# Design

## Context

`publish-image.yml` is `workflow_dispatch`-only. Its first step rejects non-tag refs; the job has `contents: read`. GitHub's "Use workflow from" picker lists branches and tags only, so a release cannot be chosen directly. A release is always attached to a tag, so the selected tag identifies the release.

## Goals / Non-Goals

**Goals:**
- Make it impossible to publish an image from a tag with no published release.
- Fail fast with an actionable message.

**Non-Goals:**
- Selecting a release in the dispatch UI (not supported by GitHub).
- Triggering on the `release` event, or changing `tag.yml`.
- Requiring stable (non-pre-release) releases.

## Decisions

- **Check with the `gh` CLI**: run `gh release view "$GITHUB_REF_NAME"` in a step right after "Require a tag ref", with `GH_TOKEN: ${{ github.token }}` and `GH_REPO`. `gh` is preinstalled on `ubuntu-latest`, and reading releases needs only `contents: read`, which the job already has. Alternative: `curl` against `/releases/tags/{tag}`; rejected as more boilerplate for the same result.
- **Place it before checkout and validation**: it needs no repo files, so the run fails cheaply and before any scripts run.
- **Drafts do not count**: `releases/tags/{tag}` does not return drafts, so `gh release view` fails for them. This matches "published release" in the spec and needs no extra code.
- **Pre-releases pass**: the goal is "a release exists", and `:latest` is already a separate opt-in input.
- **Distinguish failure causes**: when `gh` fails, print the "create a release" message. Not-found is the expected cause, but API errors also fail the step; the message includes the `gh` error output so they are not mistaken for a missing release.

## Risks / Trade-offs

- [Existing unreleased tags become unpublishable] → Create a release for the tag in the GitHub UI, then re-run.
- [Transient API failure fails the run with a "no release" style message] → Include the `gh` error text in the output; re-run.
- [Release can be deleted after a publish] → Out of scope; published images are not retracted.
