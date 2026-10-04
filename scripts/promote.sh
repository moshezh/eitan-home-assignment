#!/usr/bin/env bash
# Copy the tested image from one env repo to the next. No rebuild, same digest.
# With Artifactory Pro this is one call to the docker promote API instead of pull/tag/push.
# usage: promote.sh <from> <to>
set -euo pipefail
cd "$(dirname "$0")/.."

FROM="$1"
TO="$2"
REGISTRY="${REGISTRY:-localhost:5001}"
source .build/image.env

if [[ -n "${REGISTRY_USER:-}" ]]; then
  echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin
fi

docker pull "$REGISTRY/$FROM/podinfo@$IMAGE_DIGEST"
docker tag "$REGISTRY/$FROM/podinfo@$IMAGE_DIGEST" "$REGISTRY/$TO/podinfo:$APP_VERSION"
docker push "$REGISTRY/$TO/podinfo:$APP_VERSION" | tee .build/promote.log

# checking the digest didn't change, otherwise we'd ship something we didn't test
if ! grep -q "digest: $IMAGE_DIGEST" .build/promote.log; then
  echo "digest changed during promotion, stopping" >&2
  exit 1
fi
