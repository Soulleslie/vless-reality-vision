#!/usr/bin/env bash
# 仅在一次性测试容器内运行；真实 Nginx/OpenSSL/Xray，本地测试 CA，不接触 ACME 生产环境。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
XRAY_BIN="${1:?请指定官方 Xray 二进制}"
TEST_DIR="$(mktemp -d)"; server_pid=''; http_pid=''
trap '[[ -z "$server_pid" ]] || kill "$server_pid" 2>/dev/null || true; [[ -z "$http_pid" ]] || kill "$http_pid" 2>/dev/null || true; nginx -s quit 2>/dev/null || true; rm -rf "$TEST_DIR"' EXIT
[[ $EUID == 0 && -f /.dockerenv ]] || { echo '仅限一次性容器'; exit 1; }
rm -f /etc/nginx/sites-enabled/default
SELF_DIR=/etc/vless-reality-self; SELF_WEB=/var/www/vless-reality-self
mkdir -p "$SELF_DIR/acme/live/node.example.test" "$SELF_DIR/work"; : > "$SELF_DIR/files.sha256"
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj /CN=Test-CA -keyout "$TEST_DIR/ca.key" -out "$TEST_DIR/ca.crt" >/dev/null 2>&1
cp "$TEST_DIR/ca.crt" /usr/local/share/ca-certificates/vless-test-ca.crt
update-ca-certificates >/dev/null 2>&1
openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj /CN=node.example.test \
    -keyout "$SELF_DIR/acme/live/node.example.test/privkey.pem" -out "$TEST_DIR/leaf.csr" >/dev/null 2>&1
printf 'subjectAltName=DNS:node.example.test\nextendedKeyUsage=serverAuth\n' > "$TEST_DIR/ext"
openssl x509 -req -in "$TEST_DIR/leaf.csr" -CA "$TEST_DIR/ca.crt" -CAkey "$TEST_DIR/ca.key" -CAcreateserial -days 30 \
    -extfile "$TEST_DIR/ext" -out "$SELF_DIR/acme/live/node.example.test/cert.pem" >/dev/null 2>&1
cat "$SELF_DIR/acme/live/node.example.test/cert.pem" "$TEST_DIR/ca.crt" > "$SELF_DIR/acme/live/node.example.test/fullchain.pem"
SELF_METHOD=cloudflare
security_dns_baseline() { return 0; } # DNS 由独立单元测试覆盖；本容器域名非公网 DNS。
self_site_write; self_nginx_write node.example.test
nginx -t; nginx
self_listener_check
self_tls_check node.example.test 127.0.0.1:8443
self_http_check node.example.test 127.0.0.1 8443
self_loaded_cert_matches node.example.test
self_reject_check node.example.test
self_authority_check node.example.test
printf 'vless-reality-self-v1\n' > "$SELF_DIR/.owned"
printf '# external site references %s/acme\n' "$SELF_DIR" > /etc/nginx/conf.d/other-test.conf
if self_cleanup_preflight >/dev/null 2>&1; then echo '共享证书引用未受保护'; exit 1; fi
rm /etc/nginx/conf.d/other-test.conf
# 使用实际的非 root Xray 服务和客户端；代理请求进入独立的本地 HTTP 测试源。
groupadd --system xray; useradd --system --gid xray --shell /usr/sbin/nologin xray
CONFIG_DIR=/usr/local/etc/xray; CONFIG="$CONFIG_DIR/config.json"; MARKER="$CONFIG_DIR/.vless-reality-owned"
install -d -o root -g xray -m 750 "$CONFIG_DIR"
NODE_MODE=self; PORT=443; SNI=node.example.test; TFO_ENABLED=0; SHORT_ID=0123456789abcdef
uuid="$("$XRAY_BIN" uuid)"; mapfile -t keys < <(generate_reality_keys)
PUBLIC_KEY="${keys[1]}"
container_ip="$(hostname -I | awk '{print $1}')"
SERVER_IP="$container_ip"; NODE_NAME=Self-Test
# 测试域名仅在一次性容器内解析；公网 DNS 校验由独立故障用例覆盖。
printf '%s node.example.test connect.example.test\n' "$container_ip" >> /etc/hosts
jq -n --arg domain "$SNI" '{domain:$domain,method:"cloudflare",nginx_active:false,nginx_enabled:false}' > "$SELF_DIR/state.json"
self_track "$SELF_DIR/state.json"
if command curl --noproxy '*' --connect-timeout 2 --max-time 3 --resolve "$SNI:8443:$container_ip" -fsS "https://$SNI:8443/" -o /dev/null 2>/dev/null; then echo '非回环接口不应能访问 8443'; exit 1; fi
start_server() {
    setpriv --reuid=xray --regid=xray --init-groups "$XRAY_BIN" run -config "$CONFIG" 7>&- 8>&- 9>&- > "$TEST_DIR/server.log" 2>&1 & server_pid=$!
    sleep 0.3
}
stop_server() { kill "$server_pid"; wait "$server_pid" || true; server_pid=''; }
systemctl() {
    local attempt
    case "$1" in
        is-active) if [[ "${@: -1}" == nginx ]]; then [[ -s /run/nginx.pid ]] && kill -0 "$(< /run/nginx.pid)" 2>/dev/null;
            elif [[ "${@: -1}" == xray ]]; then [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; else return 1; fi ;;
        restart) stop_server; start_server ;;
        reload) nginx -s reload ;;
        stop) if [[ "${@: -1}" == nginx ]]; then
                nginx -s quit || return 1
                for attempt in {1..30}; do [[ -s /run/nginx.pid ]] || return 0; sleep 0.1; done
                return 1
            else [[ -z "$server_pid" ]] || stop_server; fi ;;
        daemon-reload|disable) return 0 ;;
        show) if [[ "$*" == *MainPID* ]]; then printf '%s\n' "$server_pid"; else printf 'xray\n'; fi ;;
        *) return 1 ;;
    esac
}
# 用较低的测试阈值实测限速，生产命令使用独立随机的温和阈值。
fallback_limits_json() { printf '%s\n' '{"upload":{"afterBytes":4096,"bytesPerSec":65536,"burstBytesPerSec":65536},"download":{"afterBytes":4096,"bytesPerSec":65536,"burstBytesPerSec":65536}}'; }
mkdir -p "$TEST_DIR/origin"; chmod 755 "$TEST_DIR" "$TEST_DIR/origin"
printf 'proxy transport reached\n' > "$TEST_DIR/origin/index.html"
python3 -m http.server 18080 --bind 0.0.0.0 --directory "$TEST_DIR/origin" > "$TEST_DIR/origin.log" 2>&1 & http_pid=$!
# 替换测试 URL，保留真实 SOCKS/Xray 流量，避免测试依赖公网网站。
curl() {
    local args=() arg
    for arg in "$@"; do
        if [[ "${NAT_TEST:-0}" == 1 && "$arg" == "$SNI:443:93.184.215.14" ]]; then
            printf '0 000 0.000000 0.000000'; return 28
        fi
        [[ "$arg" != https://www.debian.org/ ]] || arg="http://$container_ip:18080/"
        args+=("$arg")
    done
    command curl "${args[@]}"
}
switch_address() (
    public_ipv4() { printf '%s' "$container_ip"; }
    self_dns_check() { return 0; }
    address_node "$@" > "$TEST_DIR/address.log"
)
for mode in off native xorpub random; do
    CLIENT_ENCRYPTION=none; VLESS_DECRYPTION=none
    if [[ "$mode" != off ]]; then mapfile -t pair < <(generate_vless_encryption_pair "$mode"); VLESS_DECRYPTION="${pair[0]}"; CLIENT_ENCRYPTION="${pair[1]}"; fi
    write_config "$uuid" "${keys[0]}"
    # 测试源为私网地址；仅在隔离容器的配置中显式放行该地址和端口。
    jq --arg ip "$container_ip/32" '(.outbounds[] | select(.protocol=="freedom") | .settings.finalRules)=[{action:"allow",network:"tcp",ip:[$ip],port:"18080"}]' "$CONFIG" > "$TEST_DIR/scoped.json"
    cat "$TEST_DIR/scoped.json" > "$CONFIG"
    config_ok
    write_marker
    start_server
    self_http_check "$SNI" "$container_ip" 443
    self_reject_check "$SNI" "$container_ip:443"
    self_authority_check "$SNI" 443 "$container_ip"
    for protocol in --http1.1 --http2; do
        for host in "NODE.EXAMPLE.TEST" "$SNI:443"; do
            result="$(command curl --noproxy '*' -sS "$protocol" --resolve "$SNI:443:$container_ip" -H "Host: $host" -o /dev/null -w '%{http_code}' "https://$SNI/")"
            [[ "$result" == 200 ]]
        done
    done
    result="$(command curl --noproxy '*' -sS --http1.0 --resolve "$SNI:443:$container_ip" -H 'Host:' -o /dev/null -w '%{http_code}' "https://$SNI/")"
    [[ "$result" == 421 ]]
    result="$(command curl --noproxy '*' -sS --http1.1 --resolve "$SNI:443:$container_ip" --request-target 'http://invalid.example/' -o /dev/null -w '%{http_code}' "https://$SNI/")"
    [[ "$result" == 421 ]]
    self_client_probe "$SNI" "$container_ip"
    show_node >/dev/null
    security_permissions; security_link_check; self_key_pair_check; security_service_user
    # IP/域名两种 Address 均进行真实 REALITY/Vision 请求；地址操作不能触碰配置、网站、证书或运行进程。
    address_before="$(sha256sum "$CONFIG" "$SELF_SITE" "$SELF_DIR/state.json" "$SELF_DIR/acme/live/$SNI/"*.pem)"
    address_pid="$server_pid"
    switch_address ip; load_metadata
    [[ "$(< "$LINK_FILE")" == *"@$container_ip:443?"* && "$(< "$LINK_FILE")" == *"&sni=$SNI&"* ]]
    security_link_check; self_client_probe "$SNI" "$(client_address)"
    switch_address domain; load_metadata
    [[ "$(< "$LINK_FILE")" == *"@$SNI:443?"* ]]
    security_link_check; self_client_probe "$SNI" "$(client_address)"
    if [[ "$mode" == off ]]; then
        # 普通模式复用同一真实 TLS 目标作隔离替身；连接域名和第三方 SNI 独立保存。
        NODE_MODE=external; ADDR_MODE=auto; ADDR_DOMAIN=''; write_marker
        switch_address domain connect.example.test; load_metadata
        [[ "$(< "$LINK_FILE")" == *'@connect.example.test:443?'* && "$SNI" == node.example.test ]]
        self_client_probe "$SNI" "$(client_address)"
        switch_address ip; load_metadata
        [[ "$(client_address)" == "$container_ip" ]]
        self_client_probe "$SNI" "$(client_address)"
        NODE_MODE=self; ADDR_MODE=domain; ADDR_DOMAIN=''; write_marker; show_node >/dev/null
    fi
    [[ "$(sha256sum "$CONFIG" "$SELF_SITE" "$SELF_DIR/state.json" "$SELF_DIR/acme/live/$SNI/"*.pem)" == "$address_before" ]]
    [[ "$server_pid" == "$address_pid" ]]; kill -0 "$address_pid"
    printf '真实 IP/域名 Address 切换、SNI/证书/配置保留及免重启 / %s 通过\n' "$mode"
    before="$(wc -l < "$TEST_DIR/origin.log")"
    for bad in bad-uuid bad-reality bad-public-key; do
        result=0; self_client_probe "$SNI" "$container_ip" 443 "$bad" || result=$?
        [[ "$result" == 1 ]] || { echo "错误认证应被拒绝而非测试准备失败：$bad / $result"; exit 1; }
    done
    [[ "$(wc -l < "$TEST_DIR/origin.log")" == "$before" ]] || { echo '错误认证不应访问代理目的站'; exit 1; }
    if [[ "$mode" == off ]]; then
        # 模拟上一 PR 的已归属旧模板，验证升级命令实际加载 Host 严格校验。
        digest="$(sha256sum "$CONFIG")"
        sed -i '/^map /d; /if (\$vless_self_/d; /if (\$host /d; /return 421;/d' "$SELF_SITE"
        self_track "$SELF_SITE"; nginx -t; nginx -s reload; sleep 0.3
        if self_authority_check "$SNI"; then echo '旧模板不应虚假通过 Host 检查'; exit 1; fi
        security_apply > "$TEST_DIR/security-apply.log" 2>&1 || { cat "$TEST_DIR/security-apply.log"; exit 1; }
        [[ "$(sha256sum "$CONFIG")" == "$digest" ]]
    fi
    fallback_apply on > "$TEST_DIR/limit.log" 2>&1 || { cat "$TEST_DIR/limit.log"; exit 1; }
    self_authority_check "$SNI" 443 "$container_ip"
    if [[ "$mode" == off ]]; then
        head -c 262144 /dev/zero > "$SELF_WEB/payload.bin"; chmod 644 "$SELF_WEB/payload.bin"
        elapsed="$(command curl --noproxy '*' -fsS --resolve "$SNI:443:$container_ip" -o /dev/null -w '%{time_total}' "https://$SNI/payload.bin")"
        awk -v t="$elapsed" 'BEGIN {exit !(t>1)}' || { echo '回落限速未产生预期效果'; exit 1; }
        rm "$SELF_WEB/payload.bin"
    fi
    fallback_apply off > "$TEST_DIR/limit.log" 2>&1 || { cat "$TEST_DIR/limit.log"; exit 1; }
    if [[ "$mode" == off ]]; then
        # 仅 DNS/账户与系统调度是替身；权限、进程 UID、TLS、Host、正负向代理请求均真实执行。
        (
            public_ipv4() { printf '%s' "$container_ip"; }
            self_dns_check() { return 0; }
            security_dns_changed() { return 3; }
            security_caa_check() { return 3; }
            self_renew_ready() { return 0; }
            security_check
        ) > "$TEST_DIR/security-check.log" 2>&1 || { cat "$TEST_DIR/security-check.log"; exit 1; }
        jq -e '.failed_checks==0 and .external=="unverified"' "$SELF_DIR/security-last.json" >/dev/null
        [[ "$(stat -c %a "$SELF_DIR/security-last.json")" == 600 ]]
        # 仅注入公网 TCP 超时；NAT 路由判定及本地 TLS、HTTP/2、Vision 客户端均真实执行。
        (
            NAT_TEST=1
            public_ipv4() { printf '93.184.215.14'; }
            self_dns_check() { return 0; }; self_renew_ready() { return 0; }
            rc=0; check_self || rc=$?
            [[ "$rc" == 3 ]]
            self_http_check "$SNI" 127.0.0.1 443
            kill -0 "$server_pid"
        ) > "$TEST_DIR/nat-check.log" 2>&1 || { cat "$TEST_DIR/nat-check.log"; exit 1; }
        jq -e '.result=="pending" and .external=="unverified" and .public_probe=="unverified"' "$SELF_DIR/network-check.json" >/dev/null
        [[ "$(stat -c %a "$SELF_DIR/network-check.json")" == 600 ]]
    fi
    stop_server
    printf '真实 HTTPS/Host/SNI、认证拒绝、权限及回落限速/Vision/%s 通过\n' "$mode"
done
# 实际删除容器内资源与账号，不触碰只读挂载的官方二进制或仓库。
tested_binary="$XRAY_BIN"; XRAY_BIN=/usr/local/bin/xray
install -m 755 "$tested_binary" "$XRAY_BIN"
cp "$ROOT/install.sh" "$MANAGER"; chmod 700 "$MANAGER"
printf '%s\n' "$SHORTCUT_TAG" > "$SHORTCUT"; chmod 755 "$SHORTCUT"
printf 'ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json\n' > "$SERVICE"
mkdir -p "$SELF_DIR/logs"; printf 'private log\n' > "$SELF_DIR/logs/test.log"
printf 'dns_cloudflare_api_token = cleanup-test-only\n' > "$SELF_DIR/cloudflare.ini"
self_track "$SELF_DIR/cloudflare.ini"
confirm() { return 0; }
uninstall_node
for path in "$XRAY_BIN" "$SERVICE" "$CONFIG_DIR" "$SELF_DIR" "$SELF_SITE" "$SELF_WEB" "$MANAGER" "$SHORTCUT" "$LINK_FILE"; do
    [[ ! -e "$path" && ! -L "$path" ]] || { echo "实际卸载仍残留：$path"; exit 1; }
done
if getent passwd xray >/dev/null || getent group xray >/dev/null; then echo '专用账号仍有残留'; exit 1; fi
[[ -z "$(ss -H -ltn '( sport = :443 or sport = :8443 )')" ]]
result=0; (uninstall_node >/dev/null 2>&1) || result=$?
[[ "$result" == 1 ]] # 原命令在已经无残留时明确返回“未发现”，不创建或删除其他资源。
printf '真实 Nginx 停止、节点/证书/Token/日志/账号/管理入口卸载及重复检查通过\n'
