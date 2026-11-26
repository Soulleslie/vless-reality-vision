#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"; trap 'rm -rf -- "$TEST_DIR"' EXIT
MARKER="$TEST_DIR/marker"; MANAGER="$TEST_DIR/manager"
need_root() { :; }

case "${1:-}" in
    --child-install)
        install_self() { say 'TEST: install-self'; }
        interactive_menu; exit 0 ;;
    --child-uninstall)
        touch "$MANAGER"
        uninstall_node() { rm -- "$MANAGER"; say 'TEST: uninstall'; }
        interactive_menu; exit 0 ;;
    --child-website)
        website_random() { say 'TEST: website-random'; }
        interactive_menu; exit 0 ;;
    --child-token)
        cert_command() { [[ "$1" == token ]] && say 'TEST: cert-token'; }
        interactive_menu; exit 0 ;;
    --child-transport)
        transport_command() { say 'TEST: transport'; }
        interactive_menu; exit 0 ;;
esac

# 保持旧 1..29 的操作，新增 30；显示不能重复或乱序。
numbers="$(show_menu | awk '/^[[:space:]]+[0-9]+\./ {number=$1; sub(/\.$/, "", number); print number}')"
[[ "$numbers" == "$(printf '%s\n' {1..30} 00)" ]]

# 安装与卸载不允许因为重排而反向分派；命令行旧数字仍保持旧语义。
install_self() { say install-self; }; uninstall_node() { say uninstall; }
show_node() { say show; }; website_status() { say website; }; security_apply() { say security-apply; }
address_node() { say addr; }; refresh_ip() { say refresh-ip; }
website_random() { say website-random; }
cert_command() { say "cert-$1"; }
transport_command() { say "transport-${1:-menu}"; }
[[ "$(menu_action 2)" == install-self && "$(menu_action 26)" == uninstall ]]
[[ "$(menu_action 18)" == website ]]
[[ "$(menu_action 12)" == addr && "$(main addr ip)" == addr ]]
[[ "$(main 12 2>/dev/null)" == refresh-ip ]]
[[ "$(main 2 2>/dev/null)" == uninstall && "$(main 20 2>/dev/null)" == install-self ]]
[[ "$(main 27 2>/dev/null)" == security-apply ]]
[[ "$(menu_action 24)" == security-apply && "$(menu_action 27)" == website-random ]]
[[ "$(main website-random)" == website-random ]]
[[ "$(menu_action 28)" == cert-token && "$(main cert token)" == cert-token ]]
[[ "$(menu_action 29)" == transport-menu && "$(main transport xhttp)" == transport-xhttp ]]
rc=0; (main 28 >/dev/null 2>&1) || rc=$?; [[ "$rc" == 2 ]]
rc=0; (main 29 >/dev/null 2>&1) || rc=$?; [[ "$rc" == 2 ]]
[[ "$(main install-self)" == install-self && "$(main show)" == show ]]
rc=0; (main 18 >/dev/null 2>&1) || rc=$?; [[ "$rc" == 2 ]]
manager_update() { say self-update; }; update_menu() { say update-menu; }
[[ "$(menu_action 30)" == self-update && "$(main self-update)" == self-update && "$(menu_action 13)" == update-menu ]]
rc=0; menu_action 31 || rc=$?; [[ "$rc" == 2 ]]

# 真实终端输入：新 2 返回菜单，新 26 在成功删除管理入口后直接退出。
printf -v child_command 'bash %q --child-install' "$ROOT/tests/menu.bash"
output="$(printf '31\n2\n\n00\n' | TERM=xterm-256color script -q -e -c "$child_command" /dev/null)"
[[ "$output" == *'请输入菜单中的数字。'* && "$output" == *'TEST: install-self'* ]]
[[ "$output" == *'1. 安装普通 REALITY'*'1. 安装普通 REALITY'* ]]
[[ "$output" == *'请输入数字 [1-30，00 退出]'* ]]
[[ "$output" != *$'\033[3J'* ]] # 保留滚动历史，不能清除刚才的安装错误。
printf -v child_command 'bash %q --child-uninstall' "$ROOT/tests/menu.bash"
output="$(printf '26\n' | script -q -e -c "$child_command" /dev/null)"
[[ "$output" == *'TEST: uninstall'* && "$output" != *'按回车返回主菜单'* ]]
printf -v child_command 'bash %q --child-website' "$ROOT/tests/menu.bash"
output="$(printf '27\n\n00\n' | script -q -e -c "$child_command" /dev/null)"
[[ "$output" == *'TEST: website-random'* && "$output" == *'按回车返回主菜单'* ]]
printf -v child_command 'bash %q --child-token' "$ROOT/tests/menu.bash"
output="$(printf '28\n\n00\n' | script -q -e -c "$child_command" /dev/null)"
[[ "$output" == *'TEST: cert-token'* && "$output" == *'按回车返回主菜单'* ]]
printf -v child_command 'bash %q --child-transport' "$ROOT/tests/menu.bash"
output="$(printf '29\n\n00\n' | script -q -e -c "$child_command" /dev/null)"
[[ "$output" == *'TEST: transport'* && "$output" == *'按回车返回主菜单'* ]]
printf '连续菜单、安装/卸载分派、终端输入与历史数字命令兼容通过\n'
