#!/bin/bash
#
# Pull a Docker container image after verifying its upstream release lifespan age.
#
# Usage:
#   docker-pull.sh <IMAGE_REF>
#
# Arguments:
#   IMAGE_REF   Docker image reference e.g.
#               ubuntu:22.04                                  (default Docker Hub registry docker.io)
#               dhi.io/alpine-base:3.23                       (Docker hardened images registry)
#               gcr.io/google-containers/pause:3.9            (Google registry)
#               ghcr.io/home-assistant/home-assistant:stable  (GitHub registry)

LOGGING_SRC=${LOGGING_SRC}
# 1. Fallback to PROFILE_SCRIPTS_SH if LOGGING_SRC is empty/unset
LOGGING_SRC="${LOGGING_SRC:-$PROFILE_SCRIPTS_SH}"
# 2. If it is still empty/unset, default to the current directory
LOGGING_SRC="${LOGGING_SRC:-./}"

# Ensure the logging utility framework path resolution is stable
if [ -f "${LOGGING_SRC}/_logging.sh" ]; then
  source "${LOGGING_SRC}/_logging.sh"
else
  # Minimal fallback logging mechanics if infrastructure is missing
  log_info() { echo -e "[INFO] $*"; }
  log_warn() { echo -e "[WARN] $*"; }
  log_fail() { echo -e "[FAIL] $*" >&2; }
  log_blank() { echo ""; }
fi
log_blank

# ==============================================================================
# LIFECYCLE AND HELP FUNCTIONS
# ==============================================================================

show_usage_and_exit() {
  sed -n '/^# /,/^[^#]/{ /^# /s/^# \?//p; }' "$0"
  echo
  exit 1
}

# ==============================================================================
# REGISTRY METADATA FUNCTIONS
# ==============================================================================

resolve_registry_reference() {
  local img="$1"
  if [[ "$img" == dhi.io/* ]] || [[ "$img" == gcr.io/* ]] || [[ "$img" == ghcr.io/* ]]; then
    REGISTRY_REF="$img"
  elif [[ "$img" == docker.io/* ]]; then
    local temp="${img#docker.io/}"
    if [[ "$temp" != */* ]]; then
      REGISTRY_REF="docker.io/library/${temp}"
    else
      REGISTRY_REF="$img"
    fi
  elif [[ "$img" != */* ]]; then
    REGISTRY_REF="docker.io/library/${img}"
  else
    REGISTRY_REF="docker.io/${img}"
  fi
}

fetch_gcr_epoch() {
  local ref="$1"
  local repo_path="${ref#gcr.io/}"
  local repo_name="${repo_path%%:*}"
  local image_tag="${repo_path#*:}"
  [ "$image_tag" = "$repo_path" ] && image_tag="latest"

  local api_url="https://gcr.io/v2/${repo_name}/tags/list"
  local remote_json
  remote_json=$(curl -sfL "$api_url") || return 1

  local gcr_ms
  gcr_ms=$(echo "$remote_json" | jq -r --arg tag "$image_tag" '.manifest[$tag].timeUploadedMs // empty')
  if [ -n "$gcr_ms" ] && [ "$gcr_ms" != "null" ]; then
    CREATED_EPOCH=$(( gcr_ms / 1000 ))
  fi
}

fetch_ghcr_epoch() {
  local ref="$1"
  local repo_path="${ref#ghcr.io/}"
  local repo_name="${repo_path%%:*}"
  local image_tag="${repo_path#*:}"
  [ "$image_tag" = "$repo_path" ] && image_tag="latest"

  local gh_token
  gh_token=$(curl -sf "https://ghcr.io/token?service=ghcr.io&scope=repository:${repo_name}:pull" | jq -r '.token // empty')
  [ -z "$gh_token" ] || [ "$gh_token" = "null" ] && return 1

  local manifest_json
  manifest_json=$(curl -sf -H "Authorization: Bearer $gh_token" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    -H "Accept: application/vnd.oci.image.manifest.v1+json" \
    "https://ghcr.io/v2/${repo_name}/manifests/${image_tag}") || return 1

  local created
  created=$(echo "$manifest_json" | jq -r '.history[0].v1Compatibility // empty' | jq -r '.created // empty')
  [ -z "$created" ] && created=$(echo "$manifest_json" | jq -r '.lifecycle.created // empty')

  if [ -n "$created" ] && [ "$created" != "null" ]; then
    CREATED_EPOCH=$(date -d "$created" +%s 2>/dev/null)
  fi
}

fetch_docker_hub_epoch() {
  local ref="$1"
  local repo_path image_tag repo_name api_url

  if [[ "$ref" == dhi.io/* ]]; then
    repo_path="${ref#dhi.io/}"
    repo_name="${repo_path%%:*}"
    image_tag="${repo_path#*:}"
    [ "$image_tag" = "$repo_path" ] && image_tag="latest"

    api_url="https://hub.docker.com/v2/repositories/hardened/$(echo "$repo_name" | sed 's/-base//')/tags/${image_tag}/"
    if [[ "$repo_name" == *"-"* ]]; then
       api_url="https://hub.docker.com/v2/repositories/hardened/${repo_name}/tags/${image_tag}/"
    fi
  else
    repo_path="${ref#docker.io/}"
    repo_name="${repo_path%%:*}"
    image_tag="${repo_path#*:}"
    [ "$image_tag" = "$repo_path" ] && image_tag="latest"

    api_url="https://hub.docker.com/v2/repositories/${repo_name}/tags/${image_tag}/"
  fi

  local remote_json
  remote_json=$(curl -sfL "$api_url") || return 1

  local created
  created=$(echo "$remote_json" | jq -r '.last_updated // empty')

  if [ -n "$created" ] && [ "$created" != "null" ]; then
    CREATED_EPOCH=$(date -d "$created" +%s 2>/dev/null)
  fi
}

# ==============================================================================
# UTILITY AND CORE LOGIC FUNCTIONS
# ==============================================================================

get_created_epoch() {
  local ref="$1"

  CREATED_EPOCH=""
  if [[ "$ref" == gcr.io/* ]]; then
    fetch_gcr_epoch "$ref"
  elif [[ "$ref" == ghcr.io/* ]]; then
    fetch_ghcr_epoch "$ref"
  else
    fetch_docker_hub_epoch "$ref"
  fi
}

check_image_age_limits() {
  local created_epoch="$1"
  local warn_red="$2"
  local warn_orange="$3"
  local warn_yellow="$4"

  local now
  now=$(date +%s)
  local diff=$(( (now - created_epoch) / 3600 ))
  local days=$(( diff / 24 ))
  local msg=""

  if [ $diff -ge 24 ]; then
    msg="${days} days"
  else
    msg="${diff} hrs"
  fi

  if [ $days -lt $warn_red ]; then
    log_fail "❌ Too recent (${msg}), skipping pull execution pipeline to protect ecosystem stability."
    log_blank
    exit 1
  elif [ $days -lt $warn_orange ]; then
    log_warn "🟠 Image is under-validated (${msg} old)."
    read -p "Proceed with pulling anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_blank
      exit 1
    fi
  elif [ $days -gt $warn_yellow ]; then
    log_warn "🟡 Image is outdated or legacy (${msg} old)."
    read -p "Proceed with pulling anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_blank
      exit 1
    fi
  else
    log_info "✅ Age validation window is optimal (${msg})."
  fi
}

check_local_cache() {
  local ref="$1"
  local remote_epoch="$2"

  if docker image inspect "$ref" &>/dev/null; then
    local local_created
    local_created=$(docker image inspect "$ref" | jq -r '.[0].Created')

    local local_epoch
    local_epoch=$(date -d "$local_created" +%s 2>/dev/null)

    if [ "$remote_epoch" -gt "$local_epoch" ]; then
      log_warn "Remote engine tracking version is newer than localized copy."
      read -p "Update target image? [y/N] " -n 1 -r
      echo
    elif [ "$remote_epoch" -eq "$local_epoch" ]; then
      log_warn "Local copy matches upstream remote metadata signature."
      read -p "Force overwrite layout? [y/N] " -n 1 -r
      echo
    else
      log_warn "Local cache copy is newer than upstream remote server target."
      read -p "Downgrade with older remote version? [y/N] " -n 1 -r
      echo
    fi

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_blank
      exit 0
    fi
  fi
}

# ==============================================================================
# MAIN EXECUTION FLOW
# ==============================================================================

IMAGE=""

for arg in "$@"; do
  case "$arg" in
    -h|--help) show_usage_and_exit ;;
    --*)      log_fail "Unknown runtime option: $arg"; exit 1 ;;
    *)        IMAGE="$arg" ;;
  esac
done

if [ -z "$IMAGE" ]; then
  log_fail "Missing required argument: IMAGE_REF"
  show_usage_and_exit
fi

# Hard Dependency Linux/Unix Tool Checklist Verification
for cmd in jq curl docker sed awk head tail date; do
  if ! command -v "$cmd" &>/dev/null; then
    log_fail "Required foundational system utility dependency is missing: $cmd"
    exit 1
  fi
done

# Resolve formal registry reference naming paths safely without subshell leaks
REGISTRY_REF=""
resolve_registry_reference "$IMAGE"

log_info "Checking lifecycle age profile for ${REGISTRY_REF}..."

WARN_DAYS_RED="${WARN_DAYS_RED:-7}"
WARN_DAYS_ORANGE="${WARN_DAYS_ORANGE:-30}"
WARN_DAYS_YELLOW="${WARN_DAYS_YELLOW:-365}"

# 1. Fetch remote image creation time epoch using orchestration handler
CREATED_EPOCH=""
get_created_epoch "$REGISTRY_REF"

if [ -z "$CREATED_EPOCH" ] || [ "$CREATED_EPOCH" = "0" ]; then
  log_fail "Image or tag signature not found on remote registry metadata endpoint: ${IMAGE}"
  log_blank
  exit 1
fi

# 2. Run verification validation thresholds checks
check_image_age_limits "$CREATED_EPOCH" "$WARN_DAYS_RED" "$WARN_DAYS_ORANGE" "$WARN_DAYS_YELLOW"

# 3. Check for locally cached copies prior to running pull executions
check_local_cache "$REGISTRY_REF" "$CREATED_EPOCH"

log_info "Pulling ${IMAGE}..."
docker image pull "$IMAGE"

log_blank
