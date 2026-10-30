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
cp docker/.env.example docker/.env
vim docker/.env  # Add your configuration

# Test build
cd docker
docker compose build

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
