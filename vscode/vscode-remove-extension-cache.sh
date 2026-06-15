#!/bin/bash

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

if [ -z "$1" ]; then
  log_warn "Usage: $(basename "$0") <extension-name>"
  log_blank
  exit 1
fi

log_info "Removing extension cache: $1"
rm -rf ~/.config/Code/User/globalStorage/"$1"*
rm -rf ~/.config/Code/CachedExtensions/"$1"*
rm -rf ~/.vscode/extensions/"$1"*
log_blank