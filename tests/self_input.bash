#!/usr/bin/env bash
# 真实终端验证输入流程；DNS/包安装/systemd 用替身，不更改主机服务。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" == --interactive-* ]]; then
    # shellcheck source=/dev/null
    source <(sed '$d' "$ROOT/install.sh")
    SCRIPT_PATH="$ROOT/install.sh"
    need_root() { :; }
    ensure_dependencies() { printf 'base-tools\n' >> "$VLESS_INPUT_TEST_LOG"; }
    ensure_dns_tool() { printf 'dns-tools\n' >> "$VLESS_INPUT_TEST_LOG"; }
    self_dns_check() { printf 'dns:%s\n' "$1" >> "$VLESS_INPUT_TEST_LOG"; [[ "$1" != missing.example.test ]]; }
    install_node() { printf 'deploy:%s\n' "$*" >> "$VLESS_INPUT_TEST_LOG"; }
    systemd-run() { printf 'domain-job:%s\n' "${@: -1}" >> "$VLESS_INPUT_TEST_LOG"; }
    show_node() { :; }
    if [[ "$1" == --interactive-change ]]; then SNI=old.example.test; change_self_domain;
    else install_self; fi
    exit 0
fi
TEST_DIR="$(mktemp -d)"; trap 'rm -rf -- "$TEST_DIR"' EXIT
export VLESS_INPUT_TEST_LOG="$TEST_DIR/calls"
printf -v child_command 'bash %q --interactive-install' "$ROOT/tests/self_input.bash"
output="$(printf '%s\n' 'https://node.example.test' 'node.example.test:443' 'bad name' ' node.example.test' \
    missing.example.test node.example.test typo.example.test NODE.EXAMPLE.TEST node.example.test \
    http admin@example.test '' n n y | script -q -e -c "$child_command" /dev/null)"
[[ "$output" == *'域名格式不正确'* && "$output" == *'域名预检未通过'* && "$output" == *'两次域名不一致'* ]]
[[ "$output" == *'准备使用的完整域名：node.example.test'* && "$output" == *'请再次输入完整域名确认'* ]]
before_method="${output%%证书验证*}"
[[ "$before_method" == *'两次域名不一致'* ]]
[[ "$(< "$VLESS_INPUT_TEST_LOG")" == $'base-tools\ndns-tools\ndns:missing.example.test\ndns:node.example.test\ndns:node.example.test\ndeploy:443 node.example.test Reality-Self off off' ]]

# 取消不检查 DNS、不安装依赖，也不进入证书/Token 页面。
: > "$VLESS_INPUT_TEST_LOG"
output="$(printf '0\n' | script -q -e -c "$child_command" /dev/null)"
[[ ! -s "$VLESS_INPUT_TEST_LOG" && "$output" == *'已取消安装'* && "$output" != *'证书验证'* ]]

# 修改自有域名的交互也须通过 DNS + 二次输入后才启动后台任务。
: > "$VLESS_INPUT_TEST_LOG"
printf -v child_command 'bash %q --interactive-change' "$ROOT/tests/self_input.bash"
output="$(printf '%s\n' missing.example.test new.example.test wrong.example.test NEW.EXAMPLE.TEST new.example.test \
    | script -q -e -c "$child_command" /dev/null)"
[[ "$output" == *'两次域名不一致'* ]]
[[ "$(tail -n 2 "$VLESS_INPUT_TEST_LOG")" == $'dns:new.example.test\ndomain-job:new.example.test' ]]

# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
need_root() { :; }
# 显式命令参数继续支持无人值守，不额外读取 stdin；仍规范化域名大小写。
output="$(
    install_node() { printf 'cli:%s' "$*"; }
    install_self NODE.EXAMPLE.TEST http admin@example.test Test off off </dev/null
)"
[[ "$output" == 'cli:443 node.example.test Test off off' ]]

# 实际 install-self / install_node 入口：DNS 失败必须在凭据读取、依赖部署、管理文件及事务前返回。
CONFIG_DIR="$TEST_DIR/config"; CONFIG="$CONFIG_DIR/config.json"; MARKER="$CONFIG_DIR/.vless-reality-owned"
SELF_DIR="$TEST_DIR/self"; SELF_WEB="$TEST_DIR/web"; SELF_SITE="$TEST_DIR/site.conf"
SELF_RENEW_SERVICE="$TEST_DIR/cert.service"; SELF_RENEW_TIMER="$TEST_DIR/cert.timer"
MANAGER="$TEST_DIR/manager"; SHORTCUT="$TEST_DIR/shortcut"; SELF_POLICY="$TEST_DIR/policy"
ensure_dependencies() { :; }; ensure_dns_tool() { :; }; check_install_eligibility() { :; }; port_free() { :; }
public_ipv4() { printf '203.0.113.1'; }
self_dns_query() { printf ';; status: NXDOMAIN, id: 1\n'; }
save_manager() { touch "$MANAGER"; }
self_prepare() { touch "$TEST_DIR/deploy-started"; }
systemctl() { return 1; }
if (VLESS_CF_CREDENTIALS="$TEST_DIR/nonexistent-token" install_self wrong.example.test cloudflare admin@example.test Test off off </dev/null > "$TEST_DIR/precheck.log" 2>&1); then exit 1; fi
[[ "$(< "$TEST_DIR/precheck.log")" == *'NXDOMAIN'* && "$(< "$TEST_DIR/precheck.log")" == *'未开始部署'* ]]
[[ ! -e "$SELF_DIR" && ! -e "$MANAGER" && ! -e "$CONFIG_DIR" && ! -e "$TEST_DIR/deploy-started" ]]
[[ "$(< "$TEST_DIR/precheck.log")" != *'正在撤销'* && "$(< "$TEST_DIR/precheck.log")" != *'Token'* ]]

# 显式改域名的 DNS 失败也在前台返回，不启动 systemd 任务或更改现有节点。
SNI=old.example.test
systemd-run() { touch "$TEST_DIR/job-started"; }
if (change_self_domain wrong.example.test > "$TEST_DIR/change.log" 2>&1); then exit 1; fi
[[ ! -e "$TEST_DIR/job-started" && "$(< "$TEST_DIR/change.log")" == *'原节点保持不变'* ]]

# 只隐藏不存在 unit 的查询提示；真实禁用失败仍报错并保留资源。
mkdir -p "$SELF_DIR"; : > "$SELF_DIR/files.sha256"; : > "$SELF_RENEW_TIMER"
printf '{"nginx_active":false,"nginx_enabled":false}\n' > "$SELF_DIR/state.json"
self_cleanup_preflight() { return 0; }
systemctl() {
    case "$1" in
        is-active|is-failed) return 1 ;;
        is-enabled) [[ "${@: -1}" == vless-reality-cert.timer ]] ;;
        disable) printf '实际禁用失败\n' >&2; return 1 ;;
        *) return 1 ;;
    esac
}
if (self_cleanup > "$TEST_DIR/cleanup.log" 2>&1); then exit 1; fi
[[ -d "$SELF_DIR" && -f "$SELF_RENEW_TIMER" && "$(< "$TEST_DIR/cleanup.log")" == *'实际禁用失败'* ]]
printf '自有域名格式/DNS 重输、二次确认、非交互兼容、部署前拦截及回滚错误保护通过\n'
