#!/usr/bin/env bash
#
# Deployment Layer — main entrypoint.
#
# Owns the full deployment lifecycle on the application server:
#   verify signature -> pull -> compose up -> health check -> (rollback) -> cleanup
#
# GitHub Actions calls this script and nothing else for a deploy. All
# deployment logic lives here, never in workflow YAML (architecture rule #2).
#
# Usage:
#   IMAGE=ghcr.io/owner/repo@sha256:...  DEPLOY_ENV=production  ./deploy/deploy.sh
#   ./deploy/deploy.sh <image-ref>
#
# Configuration is read from the environment and optional .env files. See
# deploy/.env.example for the full list of tunables.
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=deploy/lib.sh
source "./lib.sh"

main() {
  local image="${1:-${IMAGE:-}}"

  load_config
  IMAGE="$image"
  require_var IMAGE
  check_prereqs
  ensure_deploy_dir

  log "Deploying to '${DEPLOY_ENV}' — image: ${IMAGE}"

  # Capture what is running now so we can roll back to it if this deploy fails.
  local previous
  previous="$(get_current)"
  if [[ -n "$previous" ]]; then
    log "Current running image: ${previous}"
  else
    log "No previously recorded image (first deploy)."
  fi

  docker_login
  verify_image "$IMAGE"

  # Roll out the new image.
  roll_out "$IMAGE"

  # Verify health; on failure, attempt to restore the previous image.
  if health_check; then
    record_success "$IMAGE" "$previous"
    cleanup
    ok "Deployment to '${DEPLOY_ENV}' succeeded: ${IMAGE}"
    return 0
  fi

  err "Deployment unhealthy — initiating rollback."
  if [[ -n "$previous" ]]; then
    if verify_image "$previous" && roll_out "$previous" && health_check; then
      warn "Rolled back to previous healthy image: ${previous}"
      die "Deployment failed for ${IMAGE}; previous version restored."
    fi
    die "Rollback to ${previous} FAILED. Manual intervention required."
  fi
  die "Deployment failed for ${IMAGE} and there is no previous image to roll back to."
}

main "$@"
