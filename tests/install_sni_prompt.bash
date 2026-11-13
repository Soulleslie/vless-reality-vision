#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" == --child || "${1:-}" == --child-on || "${1:-}" == --child-manual ]]; then
    TEST_MODE="${1:-}"
    source <(sed '$d' "$ROOT/install.sh")
    need_root() { :; }
    check_install_eligibility() { :; }
    choose_port() { PORT=443; }
    port_free() { :; }
    ensure_dependencies() { :; }
    select_nearby_sni() {
        SNI=www.samsung.com
        say '实测延迟最低的域名：www.samsung.com（约 31 ms）'
    }
    check_sni_target() { say "手动域名已检查：$1"; }
    confirm() {
        say "$1"
        [[ "$TEST_MODE" == --child-on && "$1" == '是否开启 TCP Fast Open？默认关闭 [y/N]：' ]]
    }
    install_node
    exit 0
fi

command -v script >/dev/null 2>&1 || { printf '缺少 script 命令\n' >&2; exit 1; }
printf -v child_command 'bash %q --child' "$ROOT/tests/install_sni_prompt.bash"
output="$(printf '\n\n' | script -q -e -c "$child_command" /dev/null)"
[[ "$output" == *'实测延迟最低的域名：www.samsung.com（约 31 ms）'* ]]
before_name="${output%%请输入节点名称*}"
[[ "$before_name" == *'实测延迟最低的域名：www.samsung.com（约 31 ms）'* ]]
[[ "$output" == *'SNI： www.samsung.com:443（同网段优选）'* ]]
[[ "$output" == *'是否开启 TCP Fast Open？默认关闭 [y/N]：'* ]]
[[ "$output" == *'TFO： 关闭'* ]]
printf -v child_command 'bash %q --child-on' "$ROOT/tests/install_sni_prompt.bash"
output="$(printf '\n\n' | script -q -e -c "$child_command" /dev/null)"
[[ "$output" == *'TFO： 开启'* ]]
printf -v child_command 'bash %q --child-manual' "$ROOT/tests/install_sni_prompt.bash"
output="$(printf 'www.example.com\n\n' | script -q -e -c "$child_command" /dev/null)"
[[ "$output" == *'手动域名已检查：www.example.com'* ]]
[[ "$output" == *'SNI： www.example.com:443'* ]]
printf '安装时优选域名显示顺序验证通过\n'
