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
  # --load: with a buildx builder using the docker-container driver the
  # result otherwise stays in the build cache, and the save below would
  # silently export whatever image the tag pointed to before.
  docker) build_args=(--load) save_args=() ;;
  podman) build_args=() save_args=(--format docker-archive) ;;
  *) echo "unsupported ENGINE: $engine" >&2; exit 1 ;;
esac

tmp=$(mktemp -d)
trap 'rm -f "$tmp/iid" "$tmp/image.tar"; rmdir "$tmp"' EXIT

echo "Building $IMAGE with $engine ($(command -v "$engine"))" >&2
"$engine" build --pull "${build_args[@]}" --iidfile "$tmp/iid" -t "$IMAGE" "$@" .

# Refuse to load anything but the image this build produced.
built=$(sed 's/^sha256://' "$tmp/iid")
tagged=$("$engine" image inspect --format '{{.Id}}' "$IMAGE" | sed 's/^sha256://')
if [[ $built != "$tagged" ]]; then
  echo "built image ${built:0:12} but $IMAGE is ${tagged:0:12} in $engine's image store; not loading" >&2
  exit 1
fi

"$engine" image save "${save_args[@]}" -o "$tmp/image.tar" "$IMAGE"
sbx template load "$tmp/image.tar"

echo
echo "Loaded $IMAGE (image ${built:0:12}, built with $engine)."
echo "Existing sandboxes keep their old image: sbx rm <name> and recreate."
echo "Run with:"
echo "  sbx run --pull never --template $IMAGE claude <project-dir>"
