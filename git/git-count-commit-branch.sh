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

branch_name="$1"

get_current_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"
}

count_branch_commits() {
  # local branch=$(git rev-parse --abbrev-ref HEAD)
  local branch=$(get_current_branch)
  local branch_point=$(git merge-base $branch $(git for-each-ref --format='%(refname)' refs/remotes/ | grep -v "/$branch$" | head -1 | sed 's|refs/remotes/||'))
  git rev-list --count $branch_point..$branch
}

# if [ -z "$branch_name" ]; then
#   branch_name=$(get_current_branch)
# fi

# log_debug $branch_name

# git rev-list --count $branch_name

commit_count=$(count_branch_commits)
log_info "Number of commits in current branch: $commit_count"

log_blank