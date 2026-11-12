#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
CONFIG_DIR="$TEST_DIR/xray"
MARKER="$CONFIG_DIR/.vless-reality-owned"
mkdir -p "$CONFIG_DIR"
printf 'old-record\n' > "$MARKER"
PORT=443
SNI=www.amazon.com
NODE_NAME=Reality-Test
SERVER_IP=203.0.113.1
PUBLIC_KEY=test-public-key
SHORT_ID=0123456789abcdef

chown() { return 1; }
if write_marker; then
    printf '写入失败时不应返回成功\n' >&2
    exit 1
fi
[[ "$(< "$MARKER")" == old-record ]]
chown() { return 0; }
write_marker
[[ "$(sed -n '1p' "$MARKER")" == 443 ]]
[[ "$(sed -n '2p' "$MARKER")" == www.amazon.com ]]
printf '安装记录原子写入验证通过\n'
