# Deployment Layer

The **Deployment Layer** owns the deployment lifecycle on the application
server. It is invoked by GitHub Actions but contains all of the logic itself —
the workflow is only an orchestrator (see
[`../.github/Production_CICD_Architecture_Guide.md`](../.github/Production_CICD_Architecture_Guide.md)).

```
GitHub Actions (orchestrator)
      │  HTTPS 443
      ▼
Self-hosted Runner (on app server)
      │  runs ./deploy/deploy.sh
      ▼
Deployment Layer  ──►  verify ─► pull ─► compose up ─► health check ─► rollback? ─► cleanup
      │
      ▼
Docker Compose ──► Application containers
```

## Contents

| File                 | Responsibility                                              |
| -------------------- | ----------------------------------------------------------- |
| `deploy.sh`          | Main lifecycle entrypoint called by CD                      |
| `rollback.sh`        | Manual/automatic rollback to the previous image             |
| `lib.sh`             | Shared functions (logging, config, cosign, health, state)   |
| `docker-compose.yml` | Runtime topology (the *what*, driven by env vars)           |
| `.env.example`       | Configuration template — copy to `/opt/deployment/.env`     |

## Lifecycle (`deploy.sh`)

1. **Load config** — defaults, then `/opt/deployment/.env`, then `deploy/.env`; values already exported by the workflow win.
2. **Docker login** to GHCR (skipped if the daemon is already authenticated).
3. **Verify signature** — `cosign verify` against the keyless OIDC identity. A failed verification aborts the deploy.
4. **Roll out** — `docker compose pull` + `docker compose up -d` with the new digest-pinned image.
5. **Health check** — poll `HEALTHCHECK_URL` until 2xx or the retry budget is exhausted.
6. **Rollback on failure** — re-deploy the previously recorded image and health-check it.
7. **Record + cleanup** — persist `current`/`previous` state and prune dangling images.

State lives under `${DEPLOY_DIR}/state/` (`current`, `previous`, `history.log`) so the runner stays stateless.

## Server setup (Phase-1: runner + app on one host)

Target: Ubuntu Server LTS.

```bash
# 1. Docker Engine + Compose v2
curl -fsSL https://get.docker.com | sh
docker compose version

# 2. cosign (image signature verification)
curl -fsSL -o /usr/local/bin/cosign \
  https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
chmod +x /usr/local/bin/cosign

# 3. Persistent deployment directory, owned by the account the runner runs as.
#    deploy.sh creates this dir + state/ and copies docker-compose.yml here from
#    the runner's checkout on every deploy, so you do NOT clone the repo here.
#    You only pre-create it so the runner user has permission to write under /opt.
sudo mkdir -p /opt/deployment
sudo chown -R "$RUNNER_USER":"$RUNNER_USER" /opt/deployment   # e.g. the user running the runner service

# 3b. (Optional) Only needed for application secrets or to override defaults
#     (port, CPU/memory limits, health-check budget, cosign toggle...). The CD
#     workflow already supplies IMAGE, GHCR auth, cosign identity, DEPLOY_DIR and
#     HEALTHCHECK_URL, so the sample app deploys with NO .env at all.
#     Fetch just the template (no clone needed) and fill in real values:
curl -fsSL -o /opt/deployment/.env \
  https://raw.githubusercontent.com/<owner>/<repo>/main/deploy/.env.example
"$EDITOR" /opt/deployment/.env

# 4. Self-hosted runner
#    GitHub → Settings → Actions → Runners → New self-hosted runner.
#    Give it labels that match DEPLOY_RUNS_ON_* below, e.g. self-hosted + staging/production.
#    Install as a service so it survives reboots:
sudo ./svc.sh install
sudo ./svc.sh start
```

> The Deployment Layer files reach the server **through the runner's checkout**,
> not a manual `git clone`. On every deploy the runner checks out the repo,
> runs `./deploy/deploy.sh`, and the script syncs `docker-compose.yml` into
> `/opt/deployment`. The only artifact you place there by hand is the optional
> `.env` (secrets), which is deliberately never overwritten by a checkout.

If the runner VM is destroyed, reinstall and re-register it — the application
keeps running because its containers, volumes, and this directory are
independent of the runner.

## GitHub configuration

- **Environments** `staging` and `production` (Required reviewers on `production` for the approval gate).
- **Repository variables** to select the deploy runners and endpoints:

  | Variable                    | Example                          | Purpose                                  |
  | --------------------------- | -------------------------------- | ---------------------------------------- |
  | `DEPLOY_RUNS_ON_STAGING`    | `["self-hosted","staging"]`      | Runner labels for the staging deploy job |
  | `DEPLOY_RUNS_ON_PRODUCTION` | `["self-hosted","production"]`   | Runner labels for the production job     |
  | `DEPLOY_DIR`                | `/opt/deployment`                | Deployment directory on the server       |
  | `STAGING_HEALTHCHECK_URL`   | `http://localhost:3000/health`   | Health endpoint checked after rollout    |
  | `PRODUCTION_HEALTHCHECK_URL`| `http://localhost:3000/health`   | Health endpoint checked after rollout    |

  If `DEPLOY_RUNS_ON_*` is unset, the deploy jobs default to `self-hosted`.

- **Secrets** — `GITHUB_TOKEN` already grants GHCR pull. Add application
  secrets (DB URLs, API keys) to `/opt/deployment/.env` on the server, not to
  the workflow.

## Manual operations

Normal deploys run through CD. For emergency/manual runs you need a local copy
of the `deploy/` scripts on the server — clone the repo once (anywhere, e.g.
`git clone <repo> ~/deploy-layer`) and run from there. State still lives in
`/opt/deployment`, so the clone location does not matter.

```bash
# Deploy a specific image by hand (from the server)
IMAGE=ghcr.io/<owner>/<repo>@sha256:<digest> DEPLOY_ENV=production ./deploy/deploy.sh

# Roll back to the previously deployed image
DEPLOY_ENV=production ./deploy/rollback.sh

# Roll back to a specific image
./deploy/rollback.sh ghcr.io/<owner>/<repo>@sha256:<older-digest>
```

## Scaling notes

The compose service publishes a fixed host port, which suits a single replica.
For horizontal scale on one host, front the app with a reverse proxy
(Traefik/Nginx) and remove the static `ports` mapping, or graduate to the
multi-host architecture in the guide's *Future Expansion* section.

## Small/medium teams (SSH instead of a self-hosted runner)

This same Deployment Layer works without a self-hosted runner. Keep a
GitHub-hosted runner and have the deploy job `ssh` onto the server, then run
`./deploy/deploy.sh` there. The deployment logic is identical — only the
transport changes — so nothing here needs to be rewritten when you migrate to
a self-hosted runner later.
