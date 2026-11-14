#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
CONFIG_DIR="$TEST_DIR/xray"
CONFIG="$CONFIG_DIR/config.json"
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
[[ "$(sed -n '7p' "$MARKER")" == none ]]
[[ "$(sed -n '9p' "$MARKER")" == auto ]]
printf '{}\n' > "$CONFIG_DIR/config.json"
CLIENT_ENCRYPTION=mlkem768x25519plus.native.0rtt.legacykey
write_marker
sed -i '9,$d' "$MARKER"
load_metadata
[[ "$ADDR_MODE" == auto && "$(client_address)" == 203.0.113.1 ]]
sed -i '8,$d' "$MARKER"
load_metadata
[[ "$NODE_MODE" == external && "$CLIENT_ENCRYPTION" == mlkem768x25519plus.native.0rtt.legacykey ]]
sed -i '7,$d' "$MARKER"
CLIENT_ENCRYPTION=stale
load_metadata
[[ "$CLIENT_ENCRYPTION" == none ]]
[[ "$ADDR_MODE" == auto && -z "$ADDR_DOMAIN" ]]
NODE_MODE=self; write_marker; sed -i '9,$d' "$MARKER"
load_metadata
[[ "$ADDR_MODE" == auto && "$(client_address)" == "$SNI" ]]
NODE_MODE=external; ADDR_MODE=domain; ADDR_DOMAIN=node.example.com; write_marker
load_metadata
[[ "$(client_address)" == node.example.com ]]
for mode in invalid domain; do
    ADDR_MODE="$mode"; ADDR_DOMAIN=''; write_marker
    if (load_metadata >/dev/null 2>&1); then echo '无效地址记录不应通过'; exit 1; fi
done
printf '安装记录原子写入验证通过\n'
