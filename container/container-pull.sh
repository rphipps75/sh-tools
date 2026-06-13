#!/bin/bash
#
# Pull a container image after checking its age.
#
# Usage:
#   container-pull.sh <IMAGE_REF>
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
  local is_gnu="$2"
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
    parse_date_to_epoch "$created" "$is_gnu"
  fi
}

fetch_docker_hub_epoch() {
  local ref="$1"
  local is_gnu="$2"
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
    parse_date_to_epoch "$created" "$is_gnu"
  fi
}

# ==============================================================================
# UTILITY AND CORE LOGIC FUNCTIONS
# ==============================================================================

parse_date_to_epoch() {
  local date_str="$1"
  local is_gnu="$2"
  if [ "$is_gnu" = true ]; then
    PARSED_EPOCH=$(date -d "$date_str" +%s 2>/dev/null)
  else
    local date_clean
    date_clean=$(echo "$date_str" | sed -E 's/\.[0-9]+Z$/Z/')
    PARSED_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$date_clean" +%s 2>/dev/null)
  fi
}

get_created_epoch() {
  local ref="$1"
  local is_gnu="$2"

  CREATED_EPOCH=""
  if [[ "$ref" == gcr.io/* ]]; then
    fetch_gcr_epoch "$ref"
  elif [[ "$ref" == ghcr.io/* ]]; then
    fetch_ghcr_epoch "$ref" "$is_gnu"
  else
    fetch_docker_hub_epoch "$ref" "$is_gnu"
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
    log_fail "❌ ${LOGGING_COLOUR_RED}${msg}${LOGGING_COLOUR_RESET} - too recent, skipping pull"
    log_blank
    exit 1
  elif [ $days -lt $warn_orange ]; then
    log_warn "🟠 ${LOGGING_COLOUR_ORANGE}${msg}${LOGGING_COLOUR_RESET} - under 30 days old"
    read -p "Pull anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_blank
      exit 1
    fi
  elif [ $days -gt $warn_yellow ]; then
    log_warn "🟡 ${LOGGING_COLOUR_YELLOW}${msg}${LOGGING_COLOUR_RESET} - over 365 days old"
    read -p "Pull anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_blank
      exit 1
    fi
  else
    log_info "✅ ${LOGGING_COLOUR_BLUE}${msg}${LOGGING_COLOUR_RESET}"
  fi
}

check_local_cache() {
  local ref="$1"
  local remote_epoch="$2"
  local is_gnu="$3"

  if container image inspect "$ref" &>/dev/null; then
    local local_created
    local_created=$(container image inspect "$ref" | jq -r '.[].configuration.creationDate')

    PARSED_EPOCH=0
    parse_date_to_epoch "$local_created" "$is_gnu"
    local local_epoch="$PARSED_EPOCH"

    if [ "$remote_epoch" -gt "$local_epoch" ]; then
      log_warn "Remote is newer than local copy"
      read -p "Update? [y/N] " -n 1 -r
      echo
    elif [ "$remote_epoch" -eq "$local_epoch" ]; then
      log_warn "Local copy is same version as remote"
      read -p "Overwrite? [y/N] " -n 1 -r
      echo
    else
      log_warn "Local copy is newer than remote"
      read -p "Overwrite with older? [y/N] " -n 1 -r
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
    -h|--help) sed -n '/^# /,/^[^#]/{ /^# /s/^# \?//p; }' "$0"; echo; exit 0 ;;
    --*)      log_fail "Unknown option: $arg"; exit 1 ;;
    *)        IMAGE="$arg" ;;
  esac
done

if [ -z "$IMAGE" ]; then
  log_fail "Missing required argument: IMAGE_REF"
  sed -n '/^# /,/^[^#]/{ /^# /s/^# \?//p; }' "$0"
  echo
  exit 1
fi

# Hard Dependency Sanity Checklist Verification
for cmd in jq curl container; do
  if ! command -v "$cmd" &>/dev/null; then
    log_fail "Required foundational tool system dependency is missing: $cmd"
    exit 1
  fi
done

if date --version >/dev/null 2>&1; then
  IS_GNU_DATE=true
else
  IS_GNU_DATE=false
fi

# Resolve formal registry reference naming paths safely without subshell leaks
REGISTRY_REF=""
resolve_registry_reference "$IMAGE"

log_info "Checking age of image ${REGISTRY_REF}..."

WARN_DAYS_RED="${WARN_DAYS_RED:-7}"
WARN_DAYS_ORANGE="${WARN_DAYS_ORANGE:-30}"
WARN_DAYS_YELLOW="${WARN_DAYS_YELLOW:-365}"

# 1. Fetch remote image creation time epoch using orchestration handler
CREATED_EPOCH=""
PARSED_EPOCH=""
get_created_epoch "$REGISTRY_REF" "$IS_GNU_DATE"

# Consolidate standard return assignments dynamically
[ -n "$PARSED_EPOCH" ] && [ "$PARSED_EPOCH" != "0" ] && CREATED_EPOCH="$PARSED_EPOCH"

if [ -z "$CREATED_EPOCH" ]; then
  log_fail "Image or tag not found on remote registry or endpoint timed out: ${IMAGE}"
  log_blank
  exit 1
fi

# 2. Run verification validation thresholds checks
check_image_age_limits "$CREATED_EPOCH" "$WARN_DAYS_RED" "$WARN_DAYS_ORANGE" "$WARN_DAYS_YELLOW"

# 3. Check for locally cached copies prior to running pull executions
check_local_cache "$REGISTRY_REF" "$CREATED_EPOCH" "$IS_GNU_DATE"

log_info "Pulling ${IMAGE}..."
container image pull "$IMAGE"

log_blank