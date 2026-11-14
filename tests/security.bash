#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"; trap 'rm -rf "$TEST_DIR"' EXIT
CONFIG_DIR="$TEST_DIR/xray"; CONFIG="$CONFIG_DIR/config.json"; MARKER="$CONFIG_DIR/.vless-reality-owned"
SELF_DIR="$TEST_DIR/self"; LINK_FILE="$TEST_DIR/link"
mkdir -p "$CONFIG_DIR" "$SELF_DIR/work"
need_root() { :; }; chown() { :; }; systemctl() { return 1; }
SNI=node.example.com; NODE_MODE=self; PORT=443; SHORT_ID=0123456789abcdef; PUBLIC_KEY=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB; SERVER_IP=203.0.113.1; NODE_NAME=Self
# 检查传给 jq 外部进程的实参，避免私钥/认证资料通过 ps 暴露。
jq() {
    local arg previous='' before_previous=''
    for arg in "$@"; do
        case "$arg" in
            *AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA*|*00000000-0000-4000-8000-000000000000*|*11111111-1111-4111-8111-111111111111*|*0123456789abcdef*)
                echo '认证资料不应出现在 jq 进程参数中' >&2; return 1 ;;
        esac
        if [[ "$before_previous" == --rawfile && "$previous" == credentials ]]; then
            [[ "$(stat -c %a "$arg")" == 600 ]] || return 1
        fi
        before_previous="$previous"; previous="$arg"
    done
    command jq "$@"
}
write_config 00000000-0000-4000-8000-000000000000 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
write_marker; self_config_policy "$CONFIG" "$SNI"
edit_config_private '($credentials | split("\n")) as $secret | .inbounds[0].settings.clients[0].id=$secret[0]' 11111111-1111-4111-8111-111111111111
[[ "$(config_uuid)" == 11111111-1111-4111-8111-111111111111 ]]
edit_config_private '($credentials | split("\n")) as $secret | .inbounds[0].settings.clients[0].id=$secret[0]' 00000000-0000-4000-8000-000000000000
[[ -z "$(find "$CONFIG_DIR" -name '.private.*' -print)" ]]
original="$(sha256sum "$CONFIG")"
for rule in \
    '.inbounds[0].streamSettings.realitySettings.target="node.example.com:443"' \
    '.inbounds[0].streamSettings.realitySettings.xver=1' \
    '.inbounds[0].streamSettings.realitySettings.serverNames=[""]' \
    '.inbounds[0].streamSettings.realitySettings.shortIds=[""]' \
    '.inbounds[0].streamSettings.realitySettings.shortIds=["0000000000000000"]' \
    '.inbounds[0].settings.clients[0].id=""' \
    '.inbounds[0].settings.clients[0].id="00000000-0000-0000-0000-000000000000"' \
    '.inbounds[0].streamSettings.realitySettings.masterKeyLog="/tmp/key.log"'; do
    if edit_config "$rule"; then echo "不安全配置应在替换前拒绝：$rule"; exit 1; fi
    [[ "$(sha256sum "$CONFIG")" == "$original" ]]
done
PUBLIC_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA; write_marker
if (show_node >/dev/null 2>&1); then echo '不得把私钥作为公钥写入链接'; exit 1; fi
[[ ! -e "$LINK_FILE" ]]
PUBLIC_KEY=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB; write_marker
self_http_check() { [[ "${FAIL_STAGE:-}" != post-http ]] || ! jq -e '.inbounds[0].streamSettings.realitySettings.limitFallbackUpload' "$CONFIG" >/dev/null; }
self_client_probe() { return 0; }
config_ok() { return 0; }
fallback_capability() { [[ "${FAIL_STAGE:-}" != unsupported ]]; }
fallback_apply on >/dev/null
jq -e '.inbounds[0].streamSettings.realitySettings.limitFallbackUpload.bytesPerSec>0' "$CONFIG" >/dev/null
fallback_apply off >/dev/null
[[ "$(sha256sum "$CONFIG")" == "$original" ]]
for FAIL_STAGE in unsupported post-http; do
    if (fallback_apply on >/dev/null 2>&1); then echo "故障应回滚限速：$FAIL_STAGE"; exit 1; fi
    [[ "$(sha256sum "$CONFIG")" == "$original" ]]
done
unset FAIL_STAGE
CAA_CASE=allowed
self_dns_query() {
    printf ';; status: NOERROR\n'
    case "$CAA_CASE" in
        allowed) printf '%s 60 IN CAA 0 issue "letsencrypt.org"\n' "$2" ;;
        parent) [[ "$2" == example.com ]] && printf '%s 60 IN CAA 0 issue "letsencrypt.org"\n' "$2" || true ;;
        blocked) printf '%s 60 IN CAA 0 issue "other-ca.example"\n' "$2" ;;
        constraints) printf '%s 60 IN CAA 0 issue "letsencrypt.org;validationmethods=dns-01"\n' "$2" ;;
        critical) printf '%s 60 IN CAA 128 unknown "value"\n' "$2" ;;
        missing) : ;;
    esac
}
for CAA_CASE in allowed parent; do security_caa_check node.example.com; done
for CAA_CASE in blocked constraints critical missing; do
    result=0; security_caa_check node.example.com >/dev/null || result=$?
    case "$CAA_CASE" in blocked) [[ "$result" == 1 ]] ;; constraints|missing) [[ "$result" == 2 ]] ;; critical) [[ "$result" == 3 ]] ;; esac
done
# DNS 基线忽略 TTL，但记录授权 NS 和有效 CAA 的变化。
SNAP_CHANGE=0; SNAP_TTL=60
self_dns_check() { :; }
self_dns_query() {
    printf ';; status: NOERROR\n'
    case "$3" in
        A) printf '%s %s IN A 203.0.113.1\n' "$2" "$SNAP_TTL" ;;
        NS) [[ "$2" != example.com ]] || printf '%s %s IN NS ns%s.example.com.\n' "$2" "$SNAP_TTL" "$SNAP_CHANGE" ;;
        CAA) [[ "$2" != example.com ]] || printf '%s %s IN CAA 0 issue "letsencrypt.org"\n' "$2" "$SNAP_TTL" ;;
    esac
    return 0
}
security_dns_baseline "$SNI"
security_dns_changed "$SNI"
SNAP_TTL=300; security_dns_changed "$SNI"
SNAP_CHANGE=1
result=0; security_dns_changed "$SNI" >/dev/null || result=$?
[[ "$result" == 2 ]]
printf 'REALITY 安全约束、私钥保护、限速故障回滚和 CAA 检测通过\n'
