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
# verify 遇到未知指令或非法值只告警且仍返回 0，因此要求输出为空。
verify_clean() {
    local output
    output="$(systemd-analyze verify "$@" 2>&1)" || { printf '%s\n' "$output" >&2; return 1; }
    [[ -z "$output" ]] || { printf '%s\n' "$output" >&2; return 1; }
}
self_timer_write
verify_clean "$SELF_RENEW_SERVICE" "$SELF_RENEW_TIMER" "${SELF_RENEW_SERVICE%.service}-alert.service"
# Xray 服务：生产路径必须与卸载的归属检查一致；语法验证使用测试目录中的可执行替身。
write_xray_service "$TEST_DIR/xray-prod.service"
grep -qFx 'ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json' "$TEST_DIR/xray-prod.service"
cp "$MANAGER" "$TEST_DIR/xray"
sed "s#^ExecStart=/usr/local/bin/xray #ExecStart=$TEST_DIR/xray #" "$TEST_DIR/xray-prod.service" > "$TEST_DIR/xray.service"
for directive in NoNewPrivileges=true ProtectSystem=full PrivateDevices=true ProtectKernelTunables=true RestrictNamespaces=true \
    'RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK' 'CapabilityBoundingSet=CAP_NET_BIND_SERVICE'; do
    grep -qFx "$directive" "$TEST_DIR/xray.service"
done
verify_clean "$TEST_DIR/xray.service"
printf 'systemd 续期 timer/service/告警及 Xray 服务 unit 语法通过（未启动系统调度器）\n'
