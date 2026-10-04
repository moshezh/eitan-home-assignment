#!/usr/bin/env bash
# Import the pinned upstream podinfo image into the dev repo, scan it, record the digest.
# I don't build podinfo, so this is the "build" step. Everything after it uses the digest.
set -euo pipefail
cd "$(dirname "$0")/.."

REGISTRY="${REGISTRY:-localhost:5001}"
source upstream/podinfo.env

if [[ -n "$UPSTREAM_DIGEST" ]]; then
  SRC="$UPSTREAM_IMAGE@$UPSTREAM_DIGEST"
else
  # first run only - on main Jenkins sets REQUIRE_PINNED_DIGEST=true and this fails
  [[ "${REQUIRE_PINNED_DIGEST:-false}" == "true" ]] && { echo "UPSTREAM_DIGEST is empty, refusing to import by tag" >&2; exit 1; }
  SRC="$UPSTREAM_IMAGE:$UPSTREAM_VERSION"
fi

docker pull "$SRC" #download the image to the local docker registry

if [[ -z "$UPSTREAM_DIGEST" ]]; then
  echo "WARNING: not pinned. Put this in upstream/podinfo.env and commit:"
  echo "UPSTREAM_DIGEST=$(docker inspect "$SRC" | jq -r '.[0].RepoDigests[0]' | cut -d@ -f2)"
fi

# fail on fixable HIGH/CRITICAL. The Jenkins agent has trivy, my laptop may not.
if command -v trivy >/dev/null; then  
  trivy image --exit-code 1 --ignore-unfixed --severity HIGH,CRITICAL --no-progress \
      --scanners vuln --ignorefile upstream/.trivyignore "$SRC"
else
  echo "trivy not installed, skipping scan"
fi

DST="$REGISTRY/dev/podinfo:$UPSTREAM_VERSION"
docker tag "$SRC" "$DST"
docker push "$DST"

# digest of what we pushed to OUR registry - this is what gets deployed and promoted
DIGEST=$(docker inspect "$DST" | jq -r --arg prefix "$REGISTRY/dev/podinfo@" ' first(.. | .RepoDigests? | select(. != null) | .[] | select(startswith($prefix)) | ltrimstr($prefix))')
[[ "$DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]] || { echo "could not read pushed digest" >&2; exit 1; }

mkdir -p .build
printf 'APP_VERSION=%s\nIMAGE_DIGEST=%s\n' "$UPSTREAM_VERSION" "$DIGEST" > .build/image.env
echo "pushed $REGISTRY/dev/podinfo@$DIGEST"
