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

log_info "Rollback to previous commit..."
git reset --soft HEAD~1
log_info "...done"

log_blank