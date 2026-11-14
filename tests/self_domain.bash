#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
CONFIG_DIR="$TEST_DIR/xray"; CONFIG="$CONFIG_DIR/config.json"; MARKER="$CONFIG_DIR/.vless-reality-owned"
LINK_FILE="$TEST_DIR/link.txt"; SELF_DIR="$TEST_DIR/self"; SELF_WEB="$TEST_DIR/web"; SELF_SITE="$TEST_DIR/site.conf"
SELF_RENEW_SERVICE="$TEST_DIR/cert.service"; SELF_RENEW_TIMER="$TEST_DIR/cert.timer"
mkdir -p "$CONFIG_DIR"
need_root() { :; }
ensure_dns_tool() { :; } # 此测试使用下方的 DNS 回复替身，不访问系统包管理器。
chown() { :; }
public_ipv4() { printf '203.0.113.1'; }
DNS_CASE=valid
self_dns_query() {
    printf ';; ->>HEADER<<- status: NOERROR, id: 1\n'
    if [[ "$3" == A ]]; then
        case "$DNS_CASE" in
            valid) printf '%s 60 IN A 203.0.113.1\n' "$2" ;;
            wrong) printf '%s 60 IN A 203.0.113.2\n' "$2" ;;
            cname) printf '%s 60 IN CNAME cdn.example.com.\n%s 60 IN A 203.0.113.1\n' "$2" "$2" ;;
            missing) : ;;
        esac
    elif [[ "$DNS_CASE" == ipv6 ]]; then printf '%s 60 IN AAAA 2001:db8::1\n' "$2"; fi
}
self_dns_check node.example.com
for DNS_CASE in wrong cname missing ipv6; do
    if self_dns_check node.example.com >/dev/null 2>&1; then echo "DNS 应拒绝 $DNS_CASE"; exit 1; fi
done
DNS_CASE=valid
PORT=443; SNI=node.example.com; SERVER_IP=203.0.113.1; NODE_NAME=Test; PUBLIC_KEY=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB; SHORT_ID=0123456789abcdef
NODE_MODE=self; VLESS_DECRYPTION=none
write_config 00000000-0000-4000-8000-000000000000 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
write_marker
load_metadata
[[ "$NODE_MODE" == self ]]
jq -e '.inbounds[0].streamSettings.realitySettings.target=="127.0.0.1:8443"' "$CONFIG" >/dev/null
show_node >/dev/null
[[ "$(< "$LINK_FILE")" == *'@node.example.com:443?'* && "$(< "$LINK_FILE")" == *'sni=node.example.com&'* ]]
refresh_ip >/dev/null
[[ "$(< "$LINK_FILE")" != *'@203.0.113.1'* ]]
if (change_port 8444 >/dev/null 2>&1); then echo '自有域名不能改到其他端口'; exit 1; fi
if (change_sni auto >/dev/null 2>&1); then echo '自有域名不能切到第三方 SNI'; exit 1; fi
SELF_METHOD=http; SELF_EMAIL=admin@example.com
port_free() { [[ "$1" != "${OCCUPIED:-}" ]]; }
for OCCUPIED in 443 8443 80; do
    if (self_preflight >/dev/null 2>&1); then echo "应拒绝占用端口 $OCCUPIED"; exit 1; fi
done
unset OCCUPIED
self_preflight
NODE_MODE=external; write_config 00000000-0000-4000-8000-000000000000 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
jq -e '.inbounds[0].streamSettings.realitySettings.target=="node.example.com:443"' "$CONFIG" >/dev/null
write_marker
# 兼容旧版六行安装记录。
sed -i '7,$d' "$MARKER"
load_metadata
[[ "$NODE_MODE" == external && "$CLIENT_ENCRYPTION" == none ]]
printf '自有域名 DNS、端口、元数据、链接和普通模式兼容测试通过\n'
