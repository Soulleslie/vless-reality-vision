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
TFO_SYSCTL="$TEST_DIR/tfo.conf"
KERNEL_STATE="$TEST_DIR/kernel"
mkdir -p "$CONFIG_DIR"
touch "$SERVICE" "$XRAY_BIN" "$LINK_FILE" "$CONFIG_DIR/config.json"
printf '2' > "$KERNEL_STATE"
printf '%s\n# original=0\n# applied=2\nnet.ipv4.tcp_fastopen = 2\n' "$TFO_TAG" > "$TFO_SYSCTL"
sysctl() {
    if [[ "$1" == -n ]]; then
        cat "$KERNEL_STATE"
    elif [[ "$1" == -q && "$2" == -w && "$3" == net.ipv4.tcp_fastopen=* ]]; then
        printf '%s' "${3#*=}" > "$KERNEL_STATE"
    else
        return 1
    fi
}

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
[[ -f "$TFO_SYSCTL" && "$(kernel_tfo_value)" == 2 ]]

stop_fails=0
purge_node_files
[[ ! -e "$SERVICE" && ! -e "$XRAY_BIN" && ! -e "$CONFIG_DIR" ]]
[[ ! -e "$TFO_SYSCTL" && "$(kernel_tfo_value)" == 0 ]]
printf '安装失败回滚验证通过\n'
