# Tasks

## 1. Workflow release check

- [x] 1.1 Add a "Require a published release" step to `.github/workflows/publish-image.yml` after "Require a tag ref" and before checkout, using `gh release view "$GITHUB_REF_NAME"` with `GH_TOKEN` and `GH_REPO`, failing with a clear "create a release for this tag" message; verify with `actionlint` (or YAML parse) that the workflow is valid and the step order is tag guard, release check, checkout.
- [x] 1.2 Confirm the job permissions still need only `contents: read` and `packages: write`; verify no permission changes are in the diff.

## 2. Documentation

- [x] 2.1 Update the "Publishing from CI" section of `README.md`: add "create a GitHub release for the tag" between creating the tag and running **Publish image**, and note that runs fail for tags without a published release; verify the steps read in order.

## 3. Integration checks

- [x] 3.1 After merging to `main`, dispatch **Publish image** from an existing tag with no release and verify it fails at the release check with the expected message and pushes nothing.
- [x] 3.2 Create a release for that tag, re-dispatch, and verify the release check passes and images are pushed.
