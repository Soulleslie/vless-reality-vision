#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d)"; suffix="vless-acme-$RANDOM-$$"; pebble="$suffix-pebble"; client="$suffix-client"
PEBBLE_IMAGE='ghcr.io/letsencrypt/pebble@sha256:0c81f05db371f436c97fb894bd6d2ab8fc9c8e2ce40f8bef8a8e15941bcd75ef'
cleanup() { docker rm -f "$client" "$pebble" >/dev/null 2>&1 || true; docker network rm "$suffix" >/dev/null 2>&1 || true; rm -rf "$TEST_DIR"; }
trap cleanup EXIT
docker network create "$suffix" >/dev/null
docker create --name "$pebble" --network "$suffix" --network-alias pebble \
    -e PEBBLE_VA_NOSLEEP=1 -e PEBBLE_WFE_NONCEREJECT=0 -e PEBBLE_AUTHZREUSE=0 \
    -v "$ROOT/tests/integration/pebble.json:/test/config.json:ro" "$PEBBLE_IMAGE" -config /test/config.json >/dev/null
docker cp "$pebble:/test/certs/pebble.minica.pem" "$TEST_DIR/ca.pem"
docker start "$pebble" >/dev/null
docker run --rm --name "$client" --network "$suffix" --network-alias node.example.test \
    -e LC_ALL=C.UTF-8 -e NO_PROXY=pebble,node.example.test,localhost,127.0.0.1 -e no_proxy=pebble,node.example.test,localhost,127.0.0.1 -v "$ROOT:/src:ro" -v "$TEST_DIR/ca.pem:/pebble-ca.pem:ro" vless-self-test bash tests/integration/acme_client.bash
