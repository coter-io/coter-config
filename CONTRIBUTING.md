# Contributing to OpenClaw Docker Config

Thank you for your interest in contributing! This repository provides Docker configuration for deploying OpenClaw.

## How to Contribute

### Reporting Issues

Before creating an issue:
- Check existing issues to avoid duplicates
- Verify the issue is related to the Docker configuration, not OpenClaw itself

When creating an issue, include:
- **Clear title** describing the problem
- **Steps to reproduce** the issue
- **Expected vs actual behavior**
- **Environment** (OS, Docker version, OpenClaw version)
- **Relevant logs** from `docker compose logs`

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues:
- Use a clear, descriptive title
- Explain the proposed functionality
- Describe why it would be useful
- Provide examples of usage

### Pull Requests

Every pull request against `main` is validated automatically by the **Validate config**
workflow. It runs on every pull request regardless of which files you changed, so it
always reports a conclusion and can be relied on as a required check. It needs no
secrets and runs on forks.

The workflow runs the same scripts you can run locally, in this order — cheap offline
checks first, so you get every finding even if a later step cannot start:

| Check | Command |
|---|---|
| JSON syntax | `jq empty config/openclaw.json` |
| Secret scan | `bash scripts/check-secrets.sh` |
| Environment variable contract | `bash scripts/check-env-vars.sh` |
| Compose file | `docker compose -f docker/docker-compose.yml config -q` |
| Shell scripts | `shellcheck scripts/*.sh .githooks/pre-commit docker/entrypoint.sh docker/workspace-sync/*.sh` |
| Config against the pinned OpenClaw version | `bash scripts/validate-config.sh` |
| Newest release (advisory, never fails) | `bash scripts/check-forward-compat.sh` |

Run the two most likely to catch you out before pushing:

```bash
bash scripts/validate-config.sh
bash scripts/check-env-vars.sh
```

Enabling the pre-commit hook (`git config core.hooksPath .githooks`) runs them for you
on every commit.

1. **Fork the repository** and create your branch from `main`
2. **Test your changes**:
   - Build the Docker image locally
   - Test deployment on a VPS or local environment
   - Verify all configurations work as expected
3. **Update documentation**:
   - Update README.md if adding new features
   - Document new environment variables
   - Update configuration examples
4. **Commit with clear messages**:
   - Use present tense ("Add feature" not "Added feature")
   - Reference issues when relevant
   - Keep commits focused on single concerns

### Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/openclaw-docker-config.git
cd openclaw-docker-config

# Set up environment
cp docker/.env.example .env
vim .env  # Add your configuration

# Build and run the stack locally
./local.sh

# Test deployment (requires infra repo)
# See README.md for full deployment instructions
```

## Configuration Guidelines

When adding or modifying configuration:

- Use environment variables for all user-specific values
- Provide sensible defaults with `${VAR:-default}` syntax; interpolate without a
  default only when the deployment genuinely cannot run without the value
- Document all variables in `docker/.env.example`, under the same name they are
  referenced by, and with the source an operator uses to obtain the value. This is
  enforced by `bash scripts/check-env-vars.sh`, which runs in the pull request gate —
  a variable documented under one spelling and injected under another reaches the
  container empty
- Keep skills minimal and generic
- Avoid hardcoding paths, usernames, or domains

## Predefined Agent Workspace

The agent's workspace files are predefined in this repository rather than created
by the gateway on first run. `config/openclaw.json` sets
`agents.defaults.skipBootstrap: true`, so OpenClaw authors nothing: everything the
agent starts with comes from `workspace-templates/`, which `docker/Dockerfile`
copies into the image and `docker/entrypoint.sh` seeds into the workspace without
overwriting what is already there.

That means a first start asks the user nothing and generates no avatar. It also
means a file missing from `workspace-templates/` is a file the agent simply does
not get, so `bash scripts/validate-config.sh` fails when any predefined file is
absent, when `skipBootstrap` is not `true`, or when the identity in
`config/openclaw.json` disagrees with `workspace-templates/IDENTITY.md`.

Anything added to `workspace-templates/` must also be added to the
`REQUIRED_WORKSPACE_FILES` array in `scripts/validate-config.sh`; nothing else
checks it. Note that the entrypoint seeds the directory with `cp -rn <dir>/.`,
which copies hidden files too — anything placed there, including a dotfile, lands
in every agent workspace.

### Raising the pinned OpenClaw version

`AGENTS.md`, `SOUL.md`, `IDENTITY.md`, and `USER.md` were derived from the pinned
release's starter templates and then customized. They no longer track upstream
automatically, so improvements to those templates do not arrive on their own and
have to be folded in by hand.

`scripts/upstream-templates.sha256` records what those templates looked like when
the files were derived. Before raising `ARG OPENCLAW_VERSION` in
`docker/Dockerfile`, run:

```bash
bash scripts/check-forward-compat.sh
```

It reports any starter template that changed upstream since the baseline was
recorded, and any workspace file the new release ships that this repository does
not predefine. To check a specific release rather than the newest published one:

```bash
OPENCLAW_FORWARD_TARGET=2026.10.9 bash scripts/check-forward-compat.sh
```

When it reports drift, fold the upstream change into `workspace-templates/` by
hand and refresh `scripts/upstream-templates.sha256` in the same commit as the
version bump. The check is advisory and does not gate a pull request; it is a
prompt to review, not a verdict.

## Skill Contributions

When adding skills to the manifest:

- Only add well-tested ClawHub skills
- Document the skill's purpose in `config/skills-manifest.txt`
- Avoid personal or niche use-case skills
- Test skill installation in a fresh deployment

## Code Style

- Use consistent formatting (2-space indentation for YAML/JSON)
- Comment complex configurations
- Keep docker-compose.yml organized and readable
- Follow Docker best practices (multi-stage builds, layer caching)

## Questions?

- Check the [README](README.md) first
- Open a discussion for general questions
- Join the OpenClaw community channels
- Reference the [OpenClaw documentation](https://docs.openclaw.ai/)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
