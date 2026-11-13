#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" == --child ]]; then
    # shellcheck source=/dev/null
    source <(sed '$d' "$ROOT/install.sh")
    SCRIPT_PATH="$ROOT/install.sh"
    TEST_DIR="$(mktemp -d)"
    trap 'rm -rf -- "$TEST_DIR"' EXIT
    CONFIG_DIR="$TEST_DIR/xray"
    CONFIG="$CONFIG_DIR/config.json"
    MARKER="$CONFIG_DIR/.vless-reality-owned"
    TFO_SYSCTL="$TEST_DIR/tfo.conf"
    KERNEL_STATE="$TEST_DIR/kernel"
    SHORTCUT="$TEST_DIR/shortcut"
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' '{"inbounds":[{"protocol":"vless","streamSettings":{"sockopt":{"tcpFastOpen":false}}}]}' > "$CONFIG"
    printf 'vless-reality-setup\n' > "$MARKER"
    printf '0' > "$KERNEL_STATE"
    need_root() { :; }
    need_command() { :; }
    ensure_shortcut() { :; }
    load_metadata() { NODE_NAME=test; SERVER_IP=127.0.0.1; PORT=443; SNI=www.amazon.com; }
    show_node() { :; }
    installed_version() { printf 'test'; }
    config_ok() { return 0; }
    wait_service() { return 0; }
    systemctl() {
        case "$1" in
            is-active|restart) return 0 ;;
            *) return 1 ;;
        esac
    }
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
    systemd-run() {
        [[ " $* " == *' --wait '* && " $* " == *' --collect '* ]] || return 1
        (tfo_apply "${@: -1}")
    }
    interactive_menu
    exit 0
fi

command -v script >/dev/null 2>&1 || { printf '缺少 script 命令\n' >&2; exit 1; }
printf -v child_command 'bash %q --child' "$ROOT/tests/tfo_menu.bash"
output="$(printf '17\ny\n\n00\n' | script -q -e -c "$child_command" /dev/null)"
[[ "$output" == *'TCP Fast Open 已开启'* ]]
[[ "$output" == *'如果 SSH 经过此节点，连接可能中断。后台任务会继续执行'* ]]
[[ "$output" == *'17. 开关 TCP Fast Open'*'17. 开关 TCP Fast Open'* ]]
printf 'TFO 菜单交互验证通过\n'
