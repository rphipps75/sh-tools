#!/bin/bash
#
# Run a sh shell inside an Apple container with the current directory mounted.
#
# Usage:
#   container-here-sh.sh <IMAGE:TAG>
#
# Arguments:
#   IMAGE:TAG   Container image reference (e.g. alpine:3.18)

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

case "${1}" in
  -h|--help) sed -n '/^# /,/^[^#]/{ /^# /s/^# \?//p }' "$0"; echo; exit 0 ;;
esac

if [ -z "$1" ]; then
  log_fail "Missing IMAGE (name:tag)"
  exit 1
fi

IMAGE_NAME="${1%%:*}"
IMAGE_TAG="${1#*:}"

if [ "$IMAGE_NAME" == "$IMAGE_TAG" ] || [ -z "$IMAGE_TAG" ]; then
  log_fail "Missing TAG in '$1' (expected name:tag)"
  exit 1
fi

container run --rm -it --mount type=bind,source="$PWD",target="$PWD" --workdir "$PWD" --entrypoint sh "$1"
