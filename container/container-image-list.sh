#!/bin/bash
#
# List Apple container images sorted by repository and tag.
#
# Usage:
#   container-images-list.sh [-h|--help]

case "${1}" in
  -h|--help) sed -n '/^# /,/^[^#]/{ /^# /s/^# \?//p }' "$0"; echo; exit 0 ;;
esac

APPLE_IMAGES_OUTPUT=$(container image list --format table)
echo "$APPLE_IMAGES_OUTPUT" | { head -n 1; echo "$APPLE_IMAGES_OUTPUT" | tail -n +2 | sort -k 1,1 -k 2,2; }
