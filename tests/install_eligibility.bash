#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
CONFIG_DIR="$TEST_DIR/xray"
CONFIG="$CONFIG_DIR/config.json"
MARKER="$CONFIG_DIR/.vless-reality-owned"
SERVICE="$TEST_DIR/xray.service"
XRAY_BIN="$TEST_DIR/xray"
LINK_FILE="$TEST_DIR/link.txt"

systemctl() { return 1; }
getent() { return 2; }
check_install_eligibility

getent() { [[ "$1" == group && "$2" == xray ]]; }
if (check_install_eligibility >/dev/null 2>&1); then
    printf '已有 xray 用户组时应拒绝安装\n' >&2
    exit 1
fi
printf '安装前检查验证通过\n'
