#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
CONFIG_DIR="$TEST_DIR/xray-config"
SERVICE="$TEST_DIR/xray.service"
XRAY_BIN="$TEST_DIR/xray"
LINK_FILE="$TEST_DIR/link.txt"
mkdir -p "$CONFIG_DIR"
touch "$SERVICE" "$XRAY_BIN" "$LINK_FILE" "$CONFIG_DIR/config.json"

active=1
stop_fails=1
systemctl() {
    case "$1" in
        is-active) (( active == 1 )) ;;
        stop) if (( stop_fails )); then return 1; else active=0; fi ;;
        is-enabled) return 1 ;;
        daemon-reload) return 0 ;;
        *) return 1 ;;
    esac
}
getent() { return 2; }

if purge_node_files; then
    printf '无法停止服务时不应报告回滚成功\n' >&2
    exit 1
fi
[[ -f "$SERVICE" && -f "$XRAY_BIN" && -f "$CONFIG_DIR/config.json" ]]

stop_fails=0
purge_node_files
[[ ! -e "$SERVICE" && ! -e "$XRAY_BIN" && ! -e "$CONFIG_DIR" ]]
printf '安装失败回滚验证通过\n'
