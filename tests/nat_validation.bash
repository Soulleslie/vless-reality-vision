#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"; trap 'rm -rf -- "$TEST_DIR"' EXIT
SELF_DIR="$TEST_DIR/self"; mkdir -p "$SELF_DIR"
PUBLIC=93.184.215.14; SNI=node.example.com
ADDR='[{"addr_info":[{"family":"inet","local":"10.0.0.2"}]}]'
ROUTE='[{"gateway":"10.0.0.1","dev":"eth0","prefsrc":"10.0.0.2"}]'
ip() { if [[ "$*" == '-j -4 address show' ]]; then printf '%s\n' "$ADDR"; else printf '%s\n' "$ROUTE"; fi; }
self_public_uses_nat "$PUBLIC"
nat_addr="$ADDR"; nat_route="$ROUTE"
ADDR='[{"addr_info":[{"family":"inet","local":"93.184.215.14"}]}]'
if self_public_uses_nat "$PUBLIC"; then echo '本机已配置的公网 IP 不能当作 NAT'; exit 1; fi
ADDR="$nat_addr"; ROUTE='[{"type":"local","dev":"lo","prefsrc":"10.0.0.2"}]'
if self_public_uses_nat "$PUBLIC"; then exit 1; fi
ROUTE='[{"gateway":"10.0.0.1","dev":"eth0","prefsrc":"10.0.0.99"}]'
if self_public_uses_nat "$PUBLIC"; then echo '路由源地址必须实际配置在本机'; exit 1; fi
ROUTE='invalid-json'
if self_public_uses_nat "$PUBLIC"; then exit 1; fi
ADDR='[{"addr_info":[{"family":"inet","local":"100.64.0.9"}]}]'
ROUTE='[{"gateway":"100.64.0.1","dev":"eth0","prefsrc":"100.64.0.9"}]'
self_public_uses_nat "$PUBLIC"
ADDR="$nat_addr"; ROUTE="$nat_route"

# 只有 TCP 尚未建立的 NAT 失败可返回 3；TLS、证书、H2/HTTP 错误仍须失败。
CURL_CASE=success
curl() {
    case "$CURL_CASE" in
        success) printf '2 200 0.01 0.02'; return 0 ;;
        timeout) printf '0 000 0.000000 0.000000'; return 28 ;;
        refused) printf '0 000 0.000000 0.000000'; return 7 ;;
        after-connect) printf '0 000 0.01 0'; return 28 ;;
        certificate) printf '0 000 0.01 0'; return 60 ;;
        tls) printf '0 000 0.01 0'; return 35 ;;
        http1) printf '1.1 200 0.01 0.02'; return 0 ;;
        redirect) printf '2 301 0.01 0.02'; return 0 ;;
        http-error) printf '2 503 0.01 0.02'; return 22 ;;
    esac
}
self_public_probe "$SNI" "$PUBLIC"
for CURL_CASE in timeout refused; do
    rc=0; self_public_probe "$SNI" "$PUBLIC" || rc=$?; [[ "$rc" == 3 ]]
done
ADDR='[{"addr_info":[{"family":"inet","local":"93.184.215.14"}]}]'
rc=0; self_public_probe "$SNI" "$PUBLIC" || rc=$?; [[ "$rc" == 1 ]]
ADDR="$nat_addr"
for CURL_CASE in after-connect certificate tls http1 redirect http-error; do
    rc=0; self_public_probe "$SNI" "$PUBLIC" || rc=$?; [[ "$rc" == 1 ]]
done

# 完整检查的汇总：待验证不会变成成功；本地/外部真实失败不能被 NAT 状态遮住。
need_root() { :; }; self_operation_lock() { :; }
load_metadata() { NODE_MODE=self; SNI=node.example.com; }
public_ipv4() { printf '%s' "$PUBLIC"; }
service_ok() { :; }; self_listener_check() { :; }; self_dns_check() { :; }
self_config_check() { [[ "$CHECK_CASE" != bad-config ]]; }
self_tls_check() { :; }; self_loaded_cert_matches() { :; }; self_reject_check() { :; }; self_authority_check() { :; }
self_http_check() { [[ "$CHECK_CASE" != bad-local-http || "$3" != 443 ]]; }
self_renew_ready() { [[ "$CHECK_CASE" != bad-renewal ]]; }
self_client_probe() { [[ "$CHECK_CASE" != bad-auth ]]; }
self_public_probe() { [[ "$CHECK_CASE" == bad-public ]] && return 1; return 3; }
stat() { if [[ "$*" == '-c %u '* ]]; then printf '0'; else command stat "$@"; fi; }
CHECK_CASE=pending
rc=0; output="$(check_self)" || rc=$?; [[ "$rc" == 3 ]]
jq -e '.result=="pending" and .public_probe=="unverified" and .external=="unverified"' "$SELF_DIR/network-check.json" >/dev/null
[[ "$(stat -c %a "$SELF_DIR/network-check.json")" == 600 ]]
[[ "$(self_network_status brief)" == *'待外部验证'* ]]
[[ "$output" != *'通过：公网地址 443'* ]]
for CHECK_CASE in bad-config bad-local-http bad-auth bad-renewal bad-public; do
    rc=0; check_self > /dev/null || rc=$?; [[ "$rc" == 1 ]]
    jq -e '.result=="failed"' "$SELF_DIR/network-check.json" >/dev/null
done
CHECK_CASE=pending
VLESS_EXTERNAL_CHECK="$TEST_DIR/external"
printf '#!/bin/sh\nexit 1\n' > "$VLESS_EXTERNAL_CHECK"; chmod 700 "$VLESS_EXTERNAL_CHECK"
rc=0; check_self >/dev/null || rc=$?; [[ "$rc" == 1 ]]
printf '#!/bin/sh\nexit 0\n' > "$VLESS_EXTERNAL_CHECK"
check_self >/dev/null
jq -e '.result=="external_verified" and .public_probe=="unverified" and .external=="passed"' "$SELF_DIR/network-check.json" >/dev/null
printf 'NAT/TCP 超时分类、未验证退出码、TLS/认证失败保护与外部验证分支通过\n'
