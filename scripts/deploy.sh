#!/usr/bin/env bash
# Deploy one pinned image tag to the compose stack on this host.
#
# .github/workflows/deploy.yml copies this file next to the compose files and
# runs it over SSH. It is meant to be run by hand just as easily:
#
#   IMAGE_TAG=sha-0123456 bash deploy.sh          # one release, with rollback
#   IMAGE_TAG=1.0.1 bash deploy.sh               # same thing by version tag
#
# Images are pulled, never rebuilt, so what runs in production is byte for byte
# what CI published. If the new tag never becomes ready, the previously
# recorded tag is started again and the script exits non-zero.
set -euo pipefail

image_tag="${IMAGE_TAG:-${1:-}}"
if [ -z "$image_tag" ]; then
  echo "IMAGE_TAG is required (a sha-<commit> tag from release.yml, or a version)" >&2
  exit 2
fi

cd "$(dirname "$0")"
export IMAGE_TAG="$image_tag"

compose=(docker compose -f docker-compose.yml -f docker-compose.deploy.yml)
# The readiness probes are what an order-taking terminal cares about, and the
# probe binary ships inside both images, so this host needs no curl.
probe_api=(/app/probe "http://127.0.0.1:3000/readyz")
probe_file=(/app/probe "http://127.0.0.1:8080/readyz")

# The first deploy on a host has no previous release to fall back to.
previous="$(sed -n 's/^IMAGE_TAG=//p' .release.env 2> /dev/null | head -n 1 || true)"

wait_for_ready() {
  for attempt in $(seq 1 30); do
    if "${compose[@]}" exec -T api "${probe_api[@]}" >/dev/null 2>&1 &&
      "${compose[@]}" exec -T file "${probe_file[@]}" >/dev/null 2>&1; then
      echo "stack ready after $attempt probe(s)"
      return 0
    fi
    sleep 3
  done
  "${compose[@]}" ps
  "${compose[@]}" logs --tail=50 api file
  return 1
}

start() {
  echo "--- pulling and starting $IMAGE_TAG"
  "${compose[@]}" pull api file
  # --no-build keeps a stray ./api directory from shadowing the published image.
  "${compose[@]}" up -d --no-build --remove-orphans
  wait_for_ready
}

echo "deploying $image_tag (currently: ${previous:-nothing})"

# api and file now run as uid 65534 (see the Dockerfiles). A file-uploads
# volume created by the older root-owned images would reject the service's
# first write, which the readiness probe would catch and turn into a
# rollback loop - so hand ownership over before starting. Idempotent and
# cheap at a small shop's file counts; runs outside start() because the
# rollback path must not repeat it while racing the readiness clock.
# mongo:7 rather than a fresh pull of alpine on purpose: the guard below
# only passes on a host that has already run this stack, so that image is
# already local and the deploy path gains no new registry dependency to
# fail on under set -e.
if docker volume inspect pos_file-uploads > /dev/null 2>&1; then
  docker run --rm -v pos_file-uploads:/d mongo:7 \
    chown -R 65534:65534 /d
fi

if ! start; then
  if [ -n "$previous" ] && [ "$previous" != "$image_tag" ]; then
    echo "deploy failed, rolling back to $previous" >&2
    export IMAGE_TAG="$previous"
    if ! start; then
      echo "rollback failed too: the stack needs a person now" >&2
      exit 1
    fi
    echo "rolled back to $previous" >&2
  fi
  exit 1
fi

printf 'IMAGE_TAG=%s\n' "$image_tag" > .release.env
# Dangling layers from the tag that was just replaced are dead weight on a
# small host; images still referenced by .release.env are kept.
docker image prune -f >/dev/null
"${compose[@]}" ps
echo "deployed $image_tag"
