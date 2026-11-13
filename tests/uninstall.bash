#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 只加载函数，不执行脚本末尾的 main。
source <(sed '$d' "$ROOT/install.sh")
need_root() { :; }
confirm() { return 0; }
account_present=1
group_present=1
stop_fails=0
systemctl() {
    case "$1" in
        stop) (( stop_fails == 0 )) ;;
        is-active) return 1 ;;
        is-enabled) return 0 ;;
        disable|daemon-reload) return 0 ;;
        *) return 1 ;;
    esac
}
getent() {
    case "$1" in
        passwd) (( account_present == 1 )) ;;
        group) (( group_present == 1 )) ;;
        *) return 1 ;;
    esac
}
userdel() { account_present=0; }
groupdel() { group_present=0; }

TEST_DIR="$(mktemp -d)"
ORPHAN_DIR="$(mktemp -d /tmp/vless-reality-update.XXXXXX)"
SNI_ORPHAN_DIR="$(mktemp -d /tmp/vless-reality-sni.XXXXXX)"
trap 'rm -rf -- "$TEST_DIR" "$ORPHAN_DIR" "$SNI_ORPHAN_DIR"' EXIT
printf 'vless-reality-setup\n' > "$ORPHAN_DIR/.vless-reality-owned"
touch "$ORPHAN_DIR/xray.zip"
printf 'vless-reality-setup\n' > "$SNI_ORPHAN_DIR/.vless-reality-owned"
printf '42' > "$SNI_ORPHAN_DIR/result.0"
printf '40' > "$SNI_ORPHAN_DIR/result2.0"
CONFIG_DIR="$TEST_DIR/etc/xray"
CONFIG="$CONFIG_DIR/config.json"
MARKER="$CONFIG_DIR/.vless-reality-owned"
SERVICE="$TEST_DIR/xray.service"
XRAY_BIN="$TEST_DIR/xray"
LINK_FILE="$TEST_DIR/link.txt"
MANAGER="$TEST_DIR/manager.sh"
SHORTCUT="$TEST_DIR/shortcut"
CHECKER_BIN="$TEST_DIR/reality-checker"
CHECKER_MARKER="$TEST_DIR/.vless-reality-checker-owned"
TFO_SYSCTL="$TEST_DIR/tfo.conf"
KERNEL_STATE="$TEST_DIR/kernel"
sysctl() {
    if [[ "$1" == -n ]]; then
        cat "$KERNEL_STATE"
    elif [[ "$1" == -q && "$2" == -w && "$3" == net.ipv4.tcp_fastopen=* ]]; then
        printf '%s' "${3#*=}" > "$KERNEL_STATE"
    else
        return 1
    fi
}

make_fixture() {
    mkdir -p "$CONFIG_DIR/.change-backup.abcdef"
    touch "$CONFIG" "$MARKER" "$XRAY_BIN" "$LINK_FILE" "$MANAGER"
    touch "${LINK_FILE}.abcdef" "$TEST_DIR/.xray-update.abcdef"
    touch "$CONFIG_DIR/.change-backup.abcdef/config.json"
    touch "$CONFIG_DIR/.change-backup.abcdef/.vless-reality-owned"
    touch "$CONFIG_DIR/foreign-file"
    printf '%s\n' 'ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json' > "$SERVICE"
    printf '%s\n' "$SHORTCUT_TAG" > "$SHORTCUT"
    printf '2' > "$KERNEL_STATE"
    printf '%s\n# original=0\n# applied=2\nnet.ipv4.tcp_fastopen = 2\n' "$TFO_TAG" > "$TFO_SYSCTL"
}
make_checker_fixture() {
    printf 'checker program\n' > "$CHECKER_BIN"
    printf '%s\nversion=v2.2.3\nsha256=%s\n' "$CHECKER_TAG" \
        "$(sha256sum "$CHECKER_BIN" | awk '{print $1}')" > "$CHECKER_MARKER"
}

make_fixture
make_checker_fixture
stop_fails=1
if (uninstall_node >/dev/null 2>&1); then
    printf '卸载应在停止服务失败时中止\n' >&2
    exit 1
fi
[[ -f "$SERVICE" && -f "$CONFIG" && -f "$MARKER" ]]
[[ -f "$CHECKER_BIN" && -f "$CHECKER_MARKER" ]]
[[ -f "$TFO_SYSCTL" && "$(kernel_tfo_value)" == 2 ]]

stop_fails=0
uninstall_node >/dev/null
[[ ! -e "$SERVICE" && ! -e "$CONFIG" && ! -e "$MARKER" ]]
[[ ! -e "$XRAY_BIN" && ! -e "$LINK_FILE" && ! -e "$MANAGER" && ! -e "$SHORTCUT" ]]
[[ ! -e "$CHECKER_BIN" && ! -e "$CHECKER_MARKER" ]]
[[ ! -e "${LINK_FILE}.abcdef" && ! -e "$TEST_DIR/.xray-update.abcdef" ]]
[[ ! -e "$ORPHAN_DIR" ]]
[[ ! -e "$SNI_ORPHAN_DIR" ]]
[[ ! -e "$TFO_SYSCTL" && "$(kernel_tfo_value)" == 0 ]]
[[ ! -e "$CONFIG_DIR/.change-backup.abcdef" && -f "$CONFIG_DIR/foreign-file" ]]
(( account_present == 0 && group_present == 0 ))

rm -f -- "$CONFIG_DIR/foreign-file"
account_present=1
group_present=1
make_fixture
make_checker_fixture
printf 'modified\n' >> "$CHECKER_BIN"
if (uninstall_node >/dev/null 2>&1); then
    printf '程序被修改时卸载应在停止节点前中止\n' >&2
    exit 1
fi
[[ -f "$SERVICE" && -f "$CONFIG" && -f "$MARKER" \
    && -f "$CHECKER_BIN" && -f "$CHECKER_MARKER" ]]
sed -i '$d' "$CHECKER_BIN"
uninstall_node >/dev/null
[[ ! -e "$CHECKER_BIN" && ! -e "$CHECKER_MARKER" ]]

rm -f -- "$CONFIG_DIR/foreign-file"
account_present=1
group_present=1
make_fixture
rm -f -- "$CONFIG_DIR/foreign-file"
uninstall_node >/dev/null
[[ ! -e "$CONFIG_DIR" ]]

make_fixture
rm() {
    for arg in "$@"; do [[ "$arg" != "$MANAGER" ]] || return 1; done
    command rm "$@"
}
if (uninstall_node >/dev/null 2>&1); then
    printf '管理脚本删除失败时应报告失败\n' >&2
    exit 1
fi
unset -f rm
[[ -f "$MARKER" && -f "$MANAGER" ]]
uninstall_node >/dev/null
[[ ! -e "$MARKER" && ! -e "$MANAGER" ]]

printf 'VLESS + REALITY + Vision 节点管理脚本\n' > "$MANAGER"
printf '%s\n' "$SHORTCUT_TAG" > "$SHORTCUT"
uninstall_node >/dev/null
[[ ! -e "$SHORTCUT" && ! -e "$MANAGER" ]]

printf 'VLESS + REALITY + Vision 节点管理脚本\n' > "$MANAGER"
uninstall_node >/dev/null
[[ ! -e "$MANAGER" ]]
printf '%s\n' "$SHORTCUT_TAG" > "$SHORTCUT"
uninstall_node >/dev/null
[[ ! -e "$SHORTCUT" ]]

make_checker_fixture
uninstall_node >/dev/null
[[ ! -e "$CHECKER_BIN" && ! -e "$CHECKER_MARKER" ]]

printf 'foreign checker\n' > "$CHECKER_BIN"
printf 'VLESS + REALITY + Vision 节点管理脚本\n' > "$MANAGER"
uninstall_node >/dev/null
[[ -f "$CHECKER_BIN" && ! -e "$CHECKER_MARKER" ]]
rm -f -- "$CHECKER_BIN"

account_present=1
group_present=1
make_fixture
rm -f -- "$CONFIG"
[[ "$(menu_status)" == *'节点文件不完整'* ]]
uninstall_node >/dev/null
[[ ! -e "$MARKER" && ! -e "$MANAGER" && ! -e "$SHORTCUT" ]]
printf '2' > "$KERNEL_STATE"
printf '%s\n# original=0\n# applied=2\nnet.ipv4.tcp_fastopen = 2\n' "$TFO_TAG" > "$TFO_SYSCTL"
uninstall_node >/dev/null
[[ ! -e "$TFO_SYSCTL" && "$(kernel_tfo_value)" == 0 ]]
printf '卸载路径验证通过\n'
