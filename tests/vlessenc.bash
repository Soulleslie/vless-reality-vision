#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
CONFIG_DIR="$TEST_DIR/xray"
CONFIG="$CONFIG_DIR/config.json"
MARKER="$CONFIG_DIR/.vless-reality-owned"
mkdir -p "$CONFIG_DIR"
PORT=443
SNI=example.com
NODE_NAME=Reality-Test
SERVER_IP=203.0.113.1
PUBLIC_KEY=test-public-key
SHORT_ID=0123456789abcdef
CLIENT_ENCRYPTION=none
printf '{"inbounds":[{"protocol":"vless","settings":{"decryption":"none"}}]}\n' > "$CONFIG"
need_root() { :; }
chown() { :; }
systemctl() { return 1; }
config_ok() { :; }
show_node() { :; }
generate_vless_encryption_pair() {
    printf '%s\n%s\n' 'mlkem768x25519plus.native.600s.ABCdef0123_-' \
        'mlkem768x25519plus.native.0rtt.XYZabc4567_-'
}
write_marker
[[ "$(sed -n '7p' "$MARKER")" == none ]]
vlessenc_apply on >/dev/null
[[ "$(jq -r '.inbounds[0].settings.decryption' "$CONFIG")" == mlkem768x25519plus.native.600s.* ]]
[[ "$(sed -n '7p' "$MARKER")" == mlkem768x25519plus.native.0rtt.* ]]
vlessenc_apply off >/dev/null
[[ "$(jq -r '.inbounds[0].settings.decryption' "$CONFIG")" == none ]]
[[ "$(sed -n '7p' "$MARKER")" == none ]]
config_ok() { return 1; }
if (vlessenc_apply on >/dev/null 2>&1); then
    printf '配置失败时切换应回滚\n' >&2
    exit 1
fi
[[ "$(jq -r '.inbounds[0].settings.decryption' "$CONFIG")" == none ]]
[[ "$(sed -n '7p' "$MARKER")" == none ]]
config_ok() { :; }
show_node() { return 1; }
if (vlessenc_apply on >/dev/null 2>&1); then
    printf '链接保存失败时切换应回滚\n' >&2
    exit 1
fi
[[ "$(jq -r '.inbounds[0].settings.decryption' "$CONFIG")" == none ]]
[[ "$(sed -n '7p' "$MARKER")" == none ]]
printf 'VLESS Encryption 切换及回滚通过\n'
