## 1. Dockerfile

- [x] 1.1 Confirm on Docker Hub a `node:24.x-bookworm-slim` tag at or above 24.22.1 and choose the pin form (minor tag or digest)
- [x] 1.2 Change `FROM node:22-bookworm-slim` in `docker/Dockerfile` to the chosen Node 24 image

## 2. Verify

- [x] 2.1 Run `docker buildx build --platform linux/amd64 -f docker/Dockerfile .` and confirm all 9 steps pass, including `npm install -g openclaw@2026.10.7` and `npm install -g clawhub`
- [x] 2.2 Start the built image and confirm `node --version` is 24.22.1 or newer, the `node` user and `/home/node/.openclaw` exist, and `entrypoint.sh` runs through `tini` including the skills manifest loop (Accepted with caveat: Node, user, dirs, tini and entrypoint verified; the skills install loop could not be exercised locally because the Docker host disk was full (ENOSPC), so it is verified on first deploy.)

## 3. Docs

- [x] 3.1 Update the "Upgrade OpenClaw itself" note in `README.md` to say a `OPENCLAW_VERSION` bump may require a matching Node bump in `docker/Dockerfile`

## 4. Release

- [x] 4.1 After merge, create a new tag (for example `v0.1.1`) and dispatch the Publish image workflow from it (Marked complete at archive by request; not performed here, release handled outside OpenSpec.)
- [x] 4.2 Confirm both images are pushed to GHCR with the tag and short SHA (Marked complete at archive by request; not verified here.)
