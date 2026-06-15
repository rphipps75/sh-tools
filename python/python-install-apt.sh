#!/bin/bash
#
# Register the deadsnakes PPA, install contemporary Python versions, 
# and manage multiple upstream python3 variants via Debian update-alternatives.
#
# Usage:
#   python-install-apt.sh [OPTIONS]
#
# Options:
#   -s, --silent    Execute non-interactively without pausing between operations.
#   -h, --help      Display usage information.
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
# UTILITY AND INTERACTIVE FUNCTIONS
# ==============================================================================

execution_pause() {
  if [ "$SILENT_MODE" = false ]; then
    read -n 1 -s -r -p "Press any key to continue staging pipeline execution..."
    echo
  fi
}

# ==============================================================================
# MAIN EXECUTION FLOW
# ==============================================================================

SILENT_MODE=false

for arg in "$@"; do
  case "$arg" in
    -s|--silent) SILENT_MODE=true ;;
    -h|--help)   show_usage_and_exit ;;
    --*)         log_fail "Unknown configuration option: $arg"; exit 1 ;;
  esac
done

# Environment Guardrail Verification Checklist
for cmd in apt add-apt-repository update-alternatives sudo; do
  if ! command -v "$cmd" &>/dev/null; then
    log_fail "Environment Error: Required Debian-specific system command is missing: $cmd"
    log_fail "This installer script targets APT-based environments (e.g. Ubuntu) and cannot be executed on this host system."
    log_blank
    exit 1
  fi
done

log_info "Adding deadsnakes third-party team PPA repository for newer Python version matrices..."
if [ "$SILENT_MODE" = true ]; then
  sudo add-apt-repository -y ppa:deadsnakes/ppa
else
  sudo add-apt-repository ppa:deadsnakes/ppa
fi
log_blank
execution_pause

log_info "Installing core system package utility foundation (software-properties-common)..."
if [ "$SILENT_MODE" = true ]; then
  sudo apt install -y software-properties-common
else
  sudo apt install software-properties-common
fi
log_blank
execution_pause

log_info "Synchronising repository data indices and deploying Python environments [3.11, 3.12, 3.13, 3.14] with associated venv wrappers..."
if [ "$SILENT_MODE" = true ]; then
  sudo apt update
  sudo apt install -y \
    python3.11 python3.11-venv \
    python3.12 python3.12-venv \
    python3.13 python3.13-venv \
    python3.14 python3.14-venv
else
  sudo apt update
  sudo apt install \
    python3.11 python3.11-venv \
    python3.12 python3.12-venv \
    python3.13 python3.13-venv \
    python3.14 python3.14-venv
fi
log_blank
execution_pause

log_info "Purging ALL historical system-registered python3 alternatives mappings safely..."
sudo update-alternatives --remove-all python3
log_blank
execution_pause

log_info "Registering fresh alternatives configurations (Priorities: 3.11=11, 3.12=12, 3.13=13, 3.14=14)..."
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 11
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 12
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 13
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.14 14
log_blank

log_info "✅ Selection configuration environment matrix generated. Current default system link target is:"
if command -v python3 &>/dev/null; then
  log_info "$(python3 --version) located at $(which python3)"
else
  log_warn "python3 link assignment verification could not read functional tracking paths."
fi

log_blank
log_info "Done."
log_blank
