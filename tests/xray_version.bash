#!/usr/bin/env bash
# update_xray 的版本选择：不带参数只升级到最新稳定版且不降级；指定版本可回退，但目标版本必须接受当前配置。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"; trap 'rm -rf -- "$TEST_DIR"' EXIT
CONFIG_DIR="$TEST_DIR/config"; CONFIG="$CONFIG_DIR/config.json"; MARKER="$CONFIG_DIR/.vless-reality-owned"
XRAY_BIN="$TEST_DIR/bin/xray"; SELF_DIR="$TEST_DIR/no-self"; LINK_FILE="$TEST_DIR/link.txt"
mkdir -p "$CONFIG_DIR" "$TEST_DIR/bin"
PORT=443; SNI=www.example.com; NODE_NAME=Version-Test; SERVER_IP=203.0.113.1; PUBLIC_KEY=pub; SHORT_ID=0123456789abcdef
chown() { :; }; need_root() { :; }; ensure_dependencies() { :; }; systemctl() { return 1; }
write_marker
write_config 00000000-0000-4000-8000-000000000000 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
# 替身程序：报告自身版本；ACCEPTS=0 时拒绝当前配置。
fake_xray() {
    printf '#!/bin/sh\n[ "$1" = version ] && { echo "Xray %s (test)"; exit 0; }\n[ "$1" = run ] && [ "$2" = -test ] && exit %s\nexit 1\n' "$1" "$2" > "$3"
    chmod 755 "$3"
}
LATEST=26.2.0; ACCEPTS=1
fetch_release_metadata() {
    printf '%s\n' "$1" >> "$TEST_DIR/selectors"
    if [[ "$1" == latest ]]; then RELEASE_VERSION="$LATEST"; else RELEASE_VERSION="${1#v}"; fi
}
download_verified_release() { : > "$1"; }
unzip() { fake_xray "$RELEASE_VERSION" "$(( ACCEPTS ? 0 : 1 ))" "${@: -1}/xray"; }
set_current() { fake_xray "$1" 0 "$XRAY_BIN"; : > "$TEST_DIR/selectors"; }
config_before="$(sha256sum "$CONFIG" "$MARKER")"

# 指定较低版本：回退。
set_current 26.2.0
(update_xray v26.1.1) >/dev/null
[[ "$(installed_version)" == 26.1.1 && "$(< "$TEST_DIR/selectors")" == v26.1.1 ]]
# 不带参数：升级到最新稳定版。
: > "$TEST_DIR/selectors"
(update_xray) >/dev/null
[[ "$(installed_version)" == 26.2.0 && "$(< "$TEST_DIR/selectors")" == latest ]]
# 不带参数且当前高于最新稳定版：保持原有行为，不降级。
set_current 26.3.0
[[ "$( (update_xray) 2>&1 )" == *'高于官方最新稳定版 26.2.0，未执行降级'* && "$(installed_version)" == 26.3.0 ]]
# 指定当前版本：无需替换。
[[ "$( (update_xray v26.3.0) 2>&1 )" == *'当前已是 Xray 26.3.0'* && "$(installed_version)" == 26.3.0 ]]
# 目标版本不接受当前配置（如旧版不支持 XHTTP/VLESS Encryption）：不替换程序。
ACCEPTS=0
if (update_xray v26.1.1 >/dev/null 2>&1); then echo '目标版本拒绝配置时不能替换'; exit 1; fi
[[ "$(installed_version)" == 26.3.0 ]]
ACCEPTS=1
# 版本号格式错误：在查询发布信息之前拒绝。
: > "$TEST_DIR/selectors"
for bad in 26.1 v26.1.1-rc1 'v26.1.1;id' '../v26.1.1'; do
    if (update_xray "$bad" >/dev/null 2>&1); then echo "应拒绝版本号 $bad"; exit 1; fi
done
[[ ! -s "$TEST_DIR/selectors" ]]
if (update_xray v26.1.1 extra >/dev/null 2>&1); then exit 1; fi
# 版本切换不修改节点配置和安装记录，也不遗留临时程序。
[[ "$(sha256sum "$CONFIG" "$MARKER")" == "$config_before" ]]
[[ -z "$(find "$TEST_DIR/bin" -name '.xray-update.*' -print)" ]]
printf 'Xray 指定版本回退、最新版不降级、配置不兼容保护与版本号校验通过\n'
