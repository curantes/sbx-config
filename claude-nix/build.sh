#!/usr/bin/env bash
# Build the template with docker or podman and load it into sbx's image
# store (sbx does not share the local daemon's images).
set -euo pipefail
cd "$(dirname "$0")"

IMAGE=${IMAGE:-localhost/claude-nix:latest}

# Prefer a docker CLI only when a daemon actually answers; a bare CLI
# (e.g. from nix) with no daemon would otherwise shadow a working podman.
# Override with ENGINE=docker|podman.
engine=${ENGINE:-}
if [[ -z $engine ]]; then
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    engine=docker
  elif command -v podman >/dev/null 2>&1; then
    engine=podman
  else
    echo "need a running docker daemon or podman to build" >&2
    exit 1
  fi
fi
case $engine in
  docker) save_args=() ;;
  podman) save_args=(--format docker-archive) ;;
  *) echo "unsupported ENGINE: $engine" >&2; exit 1 ;;
esac

"$engine" build --pull -t "$IMAGE" "$@" .

tar=$(mktemp --suffix .tar)
trap 'rm -f "$tar"' EXIT
"$engine" image save "${save_args[@]}" -o "$tar" "$IMAGE"
sbx template load "$tar"

echo
echo "Loaded $IMAGE. Run with:"
echo "  sbx run --pull never --template $IMAGE claude <project-dir>"
