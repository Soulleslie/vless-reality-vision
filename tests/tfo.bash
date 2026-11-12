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
TFO_SYSCTL="$TEST_DIR/tfo.conf"
KERNEL_STATE="$TEST_DIR/kernel"
mkdir -p "$CONFIG_DIR"
printf '%s\n' '{"inbounds":[{"protocol":"vless","streamSettings":{"sockopt":{"tcpFastOpen":false}}}]}' > "$CONFIG"
printf 'vless-reality-setup\n' > "$MARKER"
printf '0' > "$KERNEL_STATE"

need_root() { :; }
need_command() { :; }
load_metadata() { :; }
# shellcheck disable=SC2329 # 由 tfo_node 间接调用。
config_ok() { return 0; }
systemctl() { return 1; }
chown() { :; }
chmod() { :; }
sysctl() {
    if [[ "$1" == -n ]]; then
        cat "$KERNEL_STATE"
    elif [[ "$1" == -q && "$2" == -w && "$3" == net.ipv4.tcp_fastopen=* ]]; then
        printf '%s' "${3#*=}" > "$KERNEL_STATE"
    else
        return 1
    fi
}

tfo_node on >/dev/null
config_tfo_enabled
kernel_tfo_server
tfo_sysctl_is_ours
[[ "$(kernel_tfo_value)" == 2 ]]
[[ "$(tfo_sysctl_field original)" == 0 ]]
tfo_node off >/dev/null
if config_tfo_enabled; then exit 1; fi
[[ "$(kernel_tfo_value)" == 0 && ! -e "$TFO_SYSCTL" ]]

# shellcheck disable=SC2329 # 由 tfo_node 间接调用。
config_ok() { return 1; }
if (tfo_node on >/dev/null 2>&1); then
    printf '配置验证失败时应回滚 TFO\n' >&2
    exit 1
fi
if config_tfo_enabled; then exit 1; fi
[[ "$(kernel_tfo_value)" == 0 && ! -e "$TFO_SYSCTL" ]]
config_ok() { return 0; }

printf '由其他程序创建\n' > "$TFO_SYSCTL"
if (tfo_node on >/dev/null 2>&1); then
    printf '内核 TFO 未开启时不得覆盖其他程序的设置文件\n' >&2
    exit 1
fi
[[ "$(< "$TFO_SYSCTL")" == '由其他程序创建' ]]
if config_tfo_enabled; then exit 1; fi
printf '2' > "$KERNEL_STATE"
tfo_node on >/dev/null 2>&1
config_tfo_enabled
tfo_node off >/dev/null
[[ "$(< "$TFO_SYSCTL")" == '由其他程序创建' && "$(kernel_tfo_value)" == 2 ]]
rm -f -- "$TFO_SYSCTL"
printf '0' > "$KERNEL_STATE"

tfo_node on >/dev/null
sysctl -q -w net.ipv4.tcp_fastopen=3
tfo_node off >/dev/null
[[ "$(kernel_tfo_value)" == 3 && ! -e "$TFO_SYSCTL" ]]
if config_tfo_enabled; then exit 1; fi
SNI=www.amazon.com
PORT=443
SHORT_ID=0123456789abcdef
TFO_ENABLED=0
write_config 00000000-0000-0000-0000-000000000000 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
if config_tfo_enabled; then exit 1; fi
TFO_ENABLED=1
write_config 00000000-0000-0000-0000-000000000000 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
config_tfo_enabled
printf 'TFO 开关与回滚验证通过\n'
