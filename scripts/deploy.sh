#!/usr/bin/env bash
# helm upgrade one env, then smoke test through the ingress.
# usage: deploy.sh <env> [sha256:...]   (pass a digest to roll back to an older image)
set -euo pipefail
cd "$(dirname "$0")/.."

ENV="$1"
REGISTRY="${REGISTRY:-localhost:5001}"
INGRESS="${INGRESS:-http://127.0.0.1:8080}"

if [[ -n "${2:-}" ]]; then
  IMAGE_DIGEST="$2"
  APP_VERSION=""
else
  source .build/image.env
fi

helm upgrade --install podinfo deploy/helm/podinfo \
  -n "podinfo-$ENV" \
  -f "deploy/environments/$ENV/values.yaml" \
  --set image.repository="$REGISTRY/$ENV/podinfo" \
  --set image.digest="$IMAGE_DIGEST" \
  --wait --timeout 5m --rollback-on-failure \
  --history-max 10

# set to the Ingress host
if [[ "$ENV" == prod ]]; then 
  HOST=podinfo.localtest.me; 
else 
  HOST=$ENV.podinfo.localtest.me; 
fi

curl -fsS --retry 10 --retry-delay 3 --retry-all-errors -H "Host: $HOST" "$INGRESS/readyz" >/dev/null
BODY=$(curl -fsS -H "Host: $HOST" "$INGRESS/")
echo "$BODY"

if [[ -n "$APP_VERSION" ]] && ! grep -Eq "\"version\": ?\"$APP_VERSION\"" <<<"$BODY"; then
  echo "expected version $APP_VERSION, ingress served something else" >&2
  exit 1
fi
echo "$ENV ok"
