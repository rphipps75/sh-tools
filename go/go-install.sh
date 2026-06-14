#!/bin/bash
#
# Download and install/upgrade the Go runtime environment after checking its release age.
#
# Usage:
#   go-install.sh
#

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
# METADATA FETCHING FUNCTIONS
# ==============================================================================

fetch_latest_go_version() {
  local html_data
  html_data=$(curl -sfL https://go.dev/dl/) || return 1
  
  # Extracts the first matching Go version tag from the download table safely without -oP
  GO_LATEST_VERSION=$(echo "$html_data" | grep -E 'go[0-9]+\.[0-9]+(\.[0-9]+)?\.darwin' | head -n 1 | sed -E 's/.*go([0-9]+\.[0-9]+(\.[0-9]+)?)\.darwin.*/\1/')
}

fetch_github_release_epoch() {
  local version="$1"
  local is_gnu="$2"
  
  local tag_json tag_sha commit_json created
  
  tag_json=$(curl -sf "https://api.github.com/repos/golang/go/git/ref/tags/go${version}") || return 1
  tag_sha=$(echo "$tag_json" | awk -F'"sha": *"' '{print $2}' | cut -d'"' -f1 | head -n 1)
  
  [ -z "$tag_sha" ] && return 1
  
  commit_json=$(curl -sf "https://api.github.com/repos/golang/go/git/commits/${tag_sha}") || return 1
  created=$(echo "$commit_json" | awk -F'"date": *"' '{print $2}' | cut -d'"' -f1 | tail -n 1)
  
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

detect_macos_architecture() {
  local arch
  arch=$(uname -m)
  if [ "$arch" = "arm64" ]; then
    GO_OS_ARCH="darwin-arm64"
  else
    GO_OS_ARCH="darwin-amd64"
  fi
}

# ==============================================================================
# MAIN EXECUTION FLOW
# ==============================================================================

for arg in "$@"; do
  case "$arg" in
    -h|--help) show_usage_and_exit ;;
    --*)      log_fail "Unknown option: $arg"; exit 1 ;;
  esac
done

# Hard Dependency Sanity Checklist Verification
for cmd in awk curl sed head tail uname sudo; do
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

# Detect architecture flavor dynamically for Mac Targets (Intel vs Apple Silicon)
GO_OS_ARCH=""
detect_macos_architecture

GO_CURRENT_VERSION=""
if [ -d "/usr/local/go" ] && command -v go &>/dev/null; then
  GO_CURRENT_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
  log_info "Go $GO_CURRENT_VERSION currently installed."
fi

log_info "Fetching latest Go version metadata..."
GO_LATEST_VERSION=""
fetch_latest_go_version

if [ -z "$GO_LATEST_VERSION" ]; then
  log_fail "Could not discover latest Go version from tracking endpoint."
  exit 1
fi

GO_LATEST_FILENAME="go${GO_LATEST_VERSION}.${GO_OS_ARCH}.tar.gz"

if [ "$GO_CURRENT_VERSION" = "$GO_LATEST_VERSION" ]; then
  log_info "Go $GO_CURRENT_VERSION is already the latest version. No update needed."
  log_blank
  exit 0
fi

# Check release validation age constraints via GitHub API
log_info "Checking release validation lifespan for go${GO_LATEST_VERSION}..."
PARSED_EPOCH=""
fetch_github_release_epoch "$GO_LATEST_VERSION" "$IS_GNU_DATE"

WARN_DAYS_RED="${WARN_DAYS_RED:-7}"

if [ -n "$PARSED_EPOCH" ] && [ "$PARSED_EPOCH" != "0" ]; then
  NOW_EPOCH=$(date +%s)
  AGE_DAYS=$(( (NOW_EPOCH - PARSED_EPOCH) / 86400 ))
  
  log_info "Latest upstream release: go${GO_LATEST_VERSION} (${AGE_DAYS} days old)"
  log_info "Release documentation reference: https://go.dev/doc/devel/release"
  
  if [ "$AGE_DAYS" -lt "$WARN_DAYS_RED" ]; then
    log_fail "❌ Release is only ${AGE_DAYS} days old. Skipping update to allow time for community validation."
    log_blank
    exit 1
  fi
else
  log_warn "Could not securely track upstream release timeline age metrics via GitHub API."
fi

# Remove the Existing Local Version safely
if [ -n "$GO_CURRENT_VERSION" ]; then
  log_warn "Removing legacy deployment target layout: go$GO_CURRENT_VERSION"
  sudo rm -rf /usr/local/go || { log_fail "Administrative elevation via sudo failed to clear target installation layout."; exit 1; }
fi

# Set up staging operational sandbox
TEMP_DIR=$(mktemp -d -t golang-XXXXXX)
cd "$TEMP_DIR" || { log_fail "Unable to descend into ephemeral workspace."; exit 1; }

# Download the specific release targeted payload asset
log_info "Downloading ${GO_LATEST_FILENAME}..."
if ! curl -sfLO "https://go.dev/dl/${GO_LATEST_FILENAME}"; then
  log_fail "Download execution tracking target failed on remote payload request asset."
  rm -rf "$TEMP_DIR"
  exit 1
fi

# Extract and Install deployment tree
log_info "Extracting binaries into localized directory footprint layout..."
if ! sudo tar -C /usr/local -xzf "$GO_LATEST_FILENAME"; then
  log_fail "Administrative context extraction payload execution error detected via tar system pipeline."
  rm -rf "$TEMP_DIR"
  exit 1
fi

# Workspace teardown cleanup sequence
cd - &>/dev/null || true
rm -rf "$TEMP_DIR"

# Verify structural deployment status outputs
if [ -d "/usr/local/go" ]; then
  GO_NEW_VERSION=$(/usr/local/go/bin/go version | awk '{print $3}')
  if [ -n "$GO_CURRENT_VERSION" ]; then
    log_info "✅ Go has been successfully upgraded from go$GO_CURRENT_VERSION to $GO_NEW_VERSION"
  else
    log_info "✅ Go $GO_NEW_VERSION has been successfully installed into the system ecosystem path layout."
  fi
else
  log_fail "Structural validation paths verification engine failed. Installation binary asset tree missing."
  exit 1
fi

log_blank
