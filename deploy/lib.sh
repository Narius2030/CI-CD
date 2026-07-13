#!/usr/bin/env bash
# Deployment Layer — shared library
#
# Sourced by deploy.sh and rollback.sh. Contains no top-level side effects
# other than defining functions and a couple of readonly constants, so it is
# safe to source from any script.
#
# Design rules (see .github/Production_CICD_Architecture_Guide.md):
#   - The Deployment Layer owns the deployment lifecycle, not the workflow YAML.
#   - Runner is stateless; all persistent state lives under DEPLOY_DIR on the
#     application server (default /opt/deployment).
#   - Application data lives in Docker volumes/databases, never in the runner.

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

if [[ -t 1 ]]; then
  _C_RESET=$'\033[0m'; _C_RED=$'\033[31m'; _C_GRN=$'\033[32m'
  _C_YLW=$'\033[33m'; _C_BLU=$'\033[34m'
else
  _C_RESET=''; _C_RED=''; _C_GRN=''; _C_YLW=''; _C_BLU=''
fi

_ts() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }

log()   { printf '%s %s[deploy]%s %s\n'    "$(_ts)" "$_C_BLU" "$_C_RESET" "$*"; }
ok()    { printf '%s %s[ ok  ]%s %s\n'     "$(_ts)" "$_C_GRN" "$_C_RESET" "$*"; }
warn()  { printf '%s %s[warn ]%s %s\n'     "$(_ts)" "$_C_YLW" "$_C_RESET" "$*" >&2; }
err()   { printf '%s %s[error]%s %s\n'     "$(_ts)" "$_C_RED" "$_C_RESET" "$*" >&2; }
die()   { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Absolute path to the directory containing this library (the repo's deploy/).
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# load_config
#   1. Sets defaults for every tunable.
#   2. Sources $DEPLOY_DIR/.env if present (server-side secrets/overrides),
#      then deploy/.env if present (repo-local, git-ignored).
#      Values already exported in the environment (e.g. from the workflow) win.
#   3. Validates required inputs.
load_config() {
  # Where the live deployment lives on the server. Persistent, NOT the runner
  # workspace. Compose file + .env + rollback state live here.
  DEPLOY_DIR="${DEPLOY_DIR:-/opt/deployment}"

  # Compose project + service. COMPOSE_PROJECT_NAME namespaces containers.
  COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-app}"
  APP_SERVICE="${APP_SERVICE:-app}"

  # Health check: HTTP GET expected to return 2xx within the budget below.
  HEALTHCHECK_URL="${HEALTHCHECK_URL:-http://localhost:3000/health}"
  HEALTHCHECK_RETRIES="${HEALTHCHECK_RETRIES:-10}"
  HEALTHCHECK_INTERVAL="${HEALTHCHECK_INTERVAL:-5}"

  # Cosign verification (mandatory per architecture guide). An escape hatch
  # exists for local smoke tests only; never disable in real environments.
  COSIGN_VERIFY="${COSIGN_VERIFY:-true}"
  COSIGN_CERT_IDENTITY_REGEXP="${COSIGN_CERT_IDENTITY_REGEXP:-}"
  COSIGN_CERT_OIDC_ISSUER="${COSIGN_CERT_OIDC_ISSUER:-https://token.actions.githubusercontent.com}"

  # GHCR authentication (optional if the daemon is already logged in).
  REGISTRY="${REGISTRY:-ghcr.io}"
  GHCR_USERNAME="${GHCR_USERNAME:-}"
  GHCR_TOKEN="${GHCR_TOKEN:-}"

  # Cleanup: prune dangling images after a successful deploy.
  PRUNE_AFTER_DEPLOY="${PRUNE_AFTER_DEPLOY:-true}"

  # Source server-side then repo-local env files (do not clobber the caller's
  # already-exported values).
  _source_env_file "${DEPLOY_DIR}/.env"
  _source_env_file "${LIB_DIR}/.env"

  # State directory for rollback bookkeeping.
  STATE_DIR="${DEPLOY_DIR}/state"

  # DEPLOY_ENV is informational (staging/production) and used in log lines.
  DEPLOY_ENV="${DEPLOY_ENV:-unknown}"
}

# _source_env_file <path>
#   Loads KEY=VALUE lines without overriding variables already set in the
#   environment. Ignores comments and blank lines.
_source_env_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  log "Loading config overrides from ${file}"
  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    key="${line%%=*}"
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    [[ -z "$key" ]] && continue
    # Only set if not already present in the environment.
    if [[ -z "${!key:-}" ]]; then
      val="${line#*=}"
      export "${key}=${val}"
    fi
  done <"$file"
}

# require_var <NAME>  — abort if the named variable is empty.
require_var() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "Required configuration '${name}' is not set."
}

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

# Resolve the docker compose invocation once (v2 plugin preferred).
compose() {
  docker compose \
    --project-name "$COMPOSE_PROJECT_NAME" \
    --project-directory "$DEPLOY_DIR" \
    -f "${DEPLOY_DIR}/docker-compose.yml" \
    "$@"
}

check_prereqs() {
  need_cmd docker
  docker compose version >/dev/null 2>&1 || die "Docker Compose v2 plugin is required ('docker compose')."
  if [[ "$COSIGN_VERIFY" == "true" ]]; then
    need_cmd cosign
  fi
}

# ---------------------------------------------------------------------------
# Registry auth
# ---------------------------------------------------------------------------

docker_login() {
  if [[ -n "$GHCR_TOKEN" && -n "$GHCR_USERNAME" ]]; then
    log "Logging in to ${REGISTRY} as ${GHCR_USERNAME}"
    printf '%s' "$GHCR_TOKEN" | docker login "$REGISTRY" -u "$GHCR_USERNAME" --password-stdin >/dev/null \
      || die "docker login to ${REGISTRY} failed."
    ok "Authenticated to ${REGISTRY}"
  else
    log "No GHCR credentials provided; assuming the Docker daemon is already authenticated."
  fi
}

# ---------------------------------------------------------------------------
# Supply-chain verification
# ---------------------------------------------------------------------------

# verify_image <image-ref>
#   Verifies the keyless cosign signature. The image MUST be referenced by
#   digest (…@sha256:…) so that verification is bound to immutable content.
verify_image() {
  local image="$1"
  if [[ "$COSIGN_VERIFY" != "true" ]]; then
    warn "COSIGN_VERIFY=${COSIGN_VERIFY}: skipping signature verification (NOT for production)."
    return 0
  fi
  require_var COSIGN_CERT_IDENTITY_REGEXP
  if [[ "$image" != *"@sha256:"* ]]; then
    warn "Image '${image}' is not pinned by digest; verification is strongest against a digest."
  fi
  log "Verifying cosign signature for ${image}"
  cosign verify \
    --certificate-identity-regexp "$COSIGN_CERT_IDENTITY_REGEXP" \
    --certificate-oidc-issuer "$COSIGN_CERT_OIDC_ISSUER" \
    "$image" >/dev/null \
    || die "Signature verification failed for ${image}. Refusing to deploy."
  ok "Signature verified for ${image}"
}

# ---------------------------------------------------------------------------
# Compose lifecycle
# ---------------------------------------------------------------------------

# roll_out <image-ref>
#   Pulls the image and (re)creates the service with it. APP_IMAGE is consumed
#   by docker-compose.yml via variable substitution.
roll_out() {
  local image="$1"
  export APP_IMAGE="$image"
  log "Pulling ${image}"
  compose pull "$APP_SERVICE" || die "docker compose pull failed for ${image}"
  log "Starting service '${APP_SERVICE}' (${DEPLOY_ENV})"
  compose up -d --remove-orphans || die "docker compose up failed for ${image}"
}

# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------

# health_check
#   Polls HEALTHCHECK_URL until it returns HTTP 2xx or the retry budget is
#   exhausted. Returns non-zero on failure so callers can trigger rollback.
health_check() {
  need_cmd curl
  log "Health check: ${HEALTHCHECK_URL} (up to ${HEALTHCHECK_RETRIES} attempts, ${HEALTHCHECK_INTERVAL}s apart)"
  local attempt=1 code
  while (( attempt <= HEALTHCHECK_RETRIES )); do
    code="$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 5 "$HEALTHCHECK_URL" 2>/dev/null || true)"
    if [[ "$code" =~ ^2 ]]; then
      ok "Health check passed (HTTP ${code}) on attempt ${attempt}"
      return 0
    fi
    warn "Attempt ${attempt}/${HEALTHCHECK_RETRIES} — got '${code:-no response}', retrying in ${HEALTHCHECK_INTERVAL}s"
    sleep "$HEALTHCHECK_INTERVAL"
    (( attempt++ ))
  done
  err "Health check failed after ${HEALTHCHECK_RETRIES} attempts."
  compose ps || true
  return 1
}

# ---------------------------------------------------------------------------
# State (for rollback)
# ---------------------------------------------------------------------------

state_init()      { mkdir -p "$STATE_DIR"; }
get_current()     { cat "${STATE_DIR}/current" 2>/dev/null || true; }
get_previous()    { cat "${STATE_DIR}/previous" 2>/dev/null || true; }

# record_success <new-image> <prev-image>
#   Promotes new -> current and demotes the image it replaced -> previous.
record_success() {
  local new="$1" prev="$2"
  state_init
  [[ -n "$prev" ]] && printf '%s\n' "$prev" >"${STATE_DIR}/previous"
  printf '%s\n' "$new" >"${STATE_DIR}/current"
  printf '%s %s %s\n' "$(_ts)" "$DEPLOY_ENV" "$new" >>"${STATE_DIR}/history.log"
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

cleanup() {
  if [[ "$PRUNE_AFTER_DEPLOY" == "true" ]]; then
    log "Pruning dangling images"
    docker image prune -f >/dev/null 2>&1 || warn "Image prune failed (non-fatal)."
  fi
}

# ---------------------------------------------------------------------------
# Compose file sync
# ---------------------------------------------------------------------------

# ensure_deploy_dir
#   Guarantees DEPLOY_DIR exists and holds the current docker-compose.yml from
#   the repository. Never touches .env or state/ (owned by the server).
ensure_deploy_dir() {
  mkdir -p "$DEPLOY_DIR"
  state_init
  if [[ "$(cd "$DEPLOY_DIR" && pwd)" != "$LIB_DIR" ]]; then
    cp -f "${LIB_DIR}/docker-compose.yml" "${DEPLOY_DIR}/docker-compose.yml"
  fi
}
