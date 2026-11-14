#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
if [[ $EUID != 0 ]] || ! command -v systemd-analyze >/dev/null; then printf '未验证：当前用户或工具不支持系统 unit 验证；请在测试容器中执行\n'; exit 0; fi
TEST_DIR="$(mktemp -d)"; trap 'rm -rf "$TEST_DIR"' EXIT
SELF_DIR="$TEST_DIR"; SELF_RENEW_SERVICE="$TEST_DIR/vless-reality-cert.service"; SELF_RENEW_TIMER="$TEST_DIR/vless-reality-cert.timer"
MANAGER="$TEST_DIR/manager.sh"; printf '#!/bin/sh\nexit 0\n' > "$MANAGER"; chmod 700 "$MANAGER"
mkdir -p "$SELF_DIR/work"
systemctl() { :; }
self_timer_write
systemd-analyze verify "$SELF_RENEW_SERVICE" "$SELF_RENEW_TIMER" "${SELF_RENEW_SERVICE%.service}-alert.service"
printf 'systemd 续期 timer/service/告警 unit 语法通过（未启动系统调度器）\n'
