#!/usr/bin/env bash
#
# Deployment Layer — manual rollback.
#
# Restores the previously deployed image recorded in the state directory and
# swaps the current/previous pointers so a subsequent rollback returns here.
#
# Usage:
#   DEPLOY_ENV=production ./deploy/rollback.sh            # roll back to previous
#   ./deploy/rollback.sh <image-ref>                      # roll back to a specific image
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=deploy/lib.sh
source "./lib.sh"

main() {
  local target="${1:-}"

  load_config
  check_prereqs
  ensure_deploy_dir

  local current
  current="$(get_current)"

  if [[ -z "$target" ]]; then
    target="$(get_previous)"
    [[ -n "$target" ]] || die "No previous image recorded in ${STATE_DIR}; nothing to roll back to."
    log "Rolling back to previous image: ${target}"
  else
    log "Rolling back to requested image: ${target}"
  fi

  if [[ "$target" == "$current" ]]; then
    warn "Target image is already the current image (${target}); nothing to do."
    return 0
  fi

  docker_login
  verify_image "$target"
  roll_out "$target"

  if health_check; then
    # Swap pointers: target becomes current, the image we left becomes previous.
    record_success "$target" "$current"
    cleanup
    ok "Rollback complete. Now running: ${target}"
    return 0
  fi

  die "Rollback to ${target} failed health check. Manual intervention required."
}

main "$@"
