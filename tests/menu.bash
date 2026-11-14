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
esac

# 回归用户截图中的跳号：显示必须严格为 1..26、00，不能重复或乱序。
numbers="$(show_menu | awk '/^[[:space:]]+[0-9]+\./ {number=$1; sub(/\.$/, "", number); print number}')"
[[ "$numbers" == "$(printf '%s\n' {1..26} 00)" ]]

# 安装与卸载不允许因为重排而反向分派；命令行旧数字仍保持旧语义。
install_self() { say install-self; }; uninstall_node() { say uninstall; }
show_node() { say show; }; website_status() { say website; }; security_apply() { say security-apply; }
[[ "$(menu_action 2)" == install-self && "$(menu_action 26)" == uninstall ]]
[[ "$(menu_action 18)" == website ]]
[[ "$(main 2 2>/dev/null)" == uninstall && "$(main 20 2>/dev/null)" == install-self ]]
[[ "$(main 27 2>/dev/null)" == security-apply ]]
[[ "$(main install-self)" == install-self && "$(main show)" == show ]]
rc=0; (main 18 >/dev/null 2>&1) || rc=$?; [[ "$rc" == 2 ]]
rc=0; menu_action 27 || rc=$?; [[ "$rc" == 2 ]]

# 真实终端输入：新 2 返回菜单，新 26 在成功删除管理入口后直接退出。
printf -v child_command 'bash %q --child-install' "$ROOT/tests/menu.bash"
output="$(printf '27\n2\n\n00\n' | script -q -e -c "$child_command" /dev/null)"
[[ "$output" == *'请输入菜单中的数字。'* && "$output" == *'TEST: install-self'* ]]
[[ "$output" == *'1. 安装普通 REALITY'*'1. 安装普通 REALITY'* ]]
[[ "$output" == *'请输入数字 [1-26，00 退出]'* ]]
printf -v child_command 'bash %q --child-uninstall' "$ROOT/tests/menu.bash"
output="$(printf '26\n' | script -q -e -c "$child_command" /dev/null)"
[[ "$output" == *'TEST: uninstall'* && "$output" != *'按回车返回主菜单'* ]]
printf '连续菜单、安装/卸载分派、终端输入与历史数字命令兼容通过\n'
