#!/bin/bash
#
# List Docker images sorted by repository and tag.
#
# Usage:
#   docker-images-list.sh [-h|--help]

case "${1}" in
  -h|--help) sed -n '/^# /,/^[^#]/{ /^# /s/^# \?//p }' "$0"; echo; exit 0 ;;
esac

DOCKER_IMAGES_OUTPUT=$(docker images --format "table {{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}" )
echo "$DOCKER_IMAGES_OUTPUT" | { head -n 1; echo "$DOCKER_IMAGES_OUTPUT" | tail -n +2 | sort -k 2,2 -k 3,3; }