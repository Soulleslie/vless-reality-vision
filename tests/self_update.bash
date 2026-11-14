#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"; trap 'rm -rf "$TEST_DIR"' EXIT
CONFIG_DIR="$TEST_DIR/config"; CONFIG="$CONFIG_DIR/config.json"; MARKER="$CONFIG_DIR/.vless-reality-owned"; XRAY_BIN="$TEST_DIR/xray"
SELF_DIR="$TEST_DIR/no-self-state"; mkdir -p "$CONFIG_DIR"
PORT=443; SNI=node.example.com; NODE_NAME=Self; SERVER_IP=203.0.113.1; PUBLIC_KEY=pub; SHORT_ID=0123456789abcdef; NODE_MODE=self
chown() { :; }; need_root() { :; }; ensure_dependencies() { :; }; systemctl() { return 1; }
write_marker
printf '{"inbounds":[{"streamSettings":{"realitySettings":{"target":"127.0.0.1:8443"}}}]}\n' > "$CONFIG"
printf 'old binary\n' > "$XRAY_BIN"
installed_version() { printf 26.11.1; }
fetch_release_metadata() { RELEASE_VERSION=26.11.9; }
download_verified_release() { : > "$1"; }
unzip() {
    cat > "${@: -1}/xray" <<'EOF'
#!/bin/sh
[ "$1" = run ] && [ "$2" = -test ] || exit 1
jq -e '.inbounds[0].streamSettings.realitySettings.target=="127.0.0.1:8443"' "$4" >/dev/null
EOF
}
old="$(sha256sum "$CONFIG" "$MARKER")"
(update_xray) >/dev/null
[[ "$(sha256sum "$CONFIG" "$MARKER")" == "$old" ]]
load_metadata
[[ "$NODE_MODE" == self ]]
# 旧版本六行安装记录在升级时也不应被重写。
sed -i '7,$d' "$MARKER"
old="$(sha256sum "$CONFIG" "$MARKER")"
(update_xray) >/dev/null
[[ "$(sha256sum "$CONFIG" "$MARKER")" == "$old" ]]
load_metadata
[[ "$NODE_MODE" == external ]]
printf 'Xray 更新保留自有域名配置及旧版安装记录测试通过\n'
