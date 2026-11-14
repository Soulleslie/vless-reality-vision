#!/usr/bin/env bash
# 仅在一次性测试容器内运行；真实 Nginx/OpenSSL/Xray，本地测试 CA，不接触 ACME 生产环境。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
XRAY_BIN="${1:?请指定官方 Xray 二进制}"
TEST_DIR="$(mktemp -d)"; pid=''; http_pid=''
trap '[[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true; [[ -z "$http_pid" ]] || kill "$http_pid" 2>/dev/null || true; nginx -s quit 2>/dev/null || true; rm -rf "$TEST_DIR"' EXIT
[[ $EUID == 0 && -f /.dockerenv ]] || { echo '仅限一次性容器'; exit 1; }
rm -f /etc/nginx/sites-enabled/default
SELF_DIR=/etc/vless-reality-self; SELF_WEB=/var/www/vless-reality-self
mkdir -p "$SELF_DIR/acme/live/node.example.test" "$SELF_DIR/work"; : > "$SELF_DIR/files.sha256"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=Test-CA -keyout "$TEST_DIR/ca.key" -out "$TEST_DIR/ca.crt" >/dev/null 2>&1
cp "$TEST_DIR/ca.crt" /usr/local/share/ca-certificates/vless-test-ca.crt
update-ca-certificates >/dev/null 2>&1
openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj /CN=node.example.test \
    -keyout "$SELF_DIR/acme/live/node.example.test/privkey.pem" -out "$TEST_DIR/leaf.csr" >/dev/null 2>&1
printf 'subjectAltName=DNS:node.example.test\nextendedKeyUsage=serverAuth\n' > "$TEST_DIR/ext"
openssl x509 -req -in "$TEST_DIR/leaf.csr" -CA "$TEST_DIR/ca.crt" -CAkey "$TEST_DIR/ca.key" -CAcreateserial -days 1 \
    -extfile "$TEST_DIR/ext" -out "$SELF_DIR/acme/live/node.example.test/cert.pem" >/dev/null 2>&1
cat "$SELF_DIR/acme/live/node.example.test/cert.pem" "$TEST_DIR/ca.crt" > "$SELF_DIR/acme/live/node.example.test/fullchain.pem"
SELF_METHOD=cloudflare
self_site_write; self_nginx_write node.example.test
nginx -t; nginx
self_listener_check
self_tls_check node.example.test 127.0.0.1:8443
self_http_check node.example.test 127.0.0.1 8443
self_loaded_cert_matches node.example.test
self_reject_check node.example.test
printf 'vless-reality-self-v1\n' > "$SELF_DIR/.owned"
printf '# external site references %s/acme\n' "$SELF_DIR" > /etc/nginx/conf.d/other-test.conf
if self_cleanup_preflight >/dev/null 2>&1; then echo '共享证书引用未受保护'; exit 1; fi
rm /etc/nginx/conf.d/other-test.conf
# 使用实际的非 root Xray 服务和客户端；代理请求进入独立的本地 HTTP 测试源。
groupadd --system xray; useradd --system --gid xray --shell /usr/sbin/nologin xray
CONFIG_DIR=/usr/local/etc/xray; CONFIG="$CONFIG_DIR/config.json"
install -d -o root -g xray -m 750 "$CONFIG_DIR"
NODE_MODE=self; PORT=443; SNI=node.example.test; TFO_ENABLED=0; SHORT_ID=0123456789abcdef
uuid="$("$XRAY_BIN" uuid)"; mapfile -t keys < <(generate_reality_keys)
PUBLIC_KEY="${keys[1]}"
container_ip="$(hostname -I | awk '{print $1}')"
mkdir -p "$TEST_DIR/origin"; chmod 755 "$TEST_DIR" "$TEST_DIR/origin"
printf 'proxy transport reached\n' > "$TEST_DIR/origin/index.html"
python3 -m http.server 18080 --bind 0.0.0.0 --directory "$TEST_DIR/origin" >/dev/null 2>&1 & http_pid=$!
# 替换测试 URL，保留真实 SOCKS/Xray 流量，避免测试依赖公网网站。
curl() {
    local args=() arg
    for arg in "$@"; do
        [[ "$arg" != https://www.debian.org/ ]] || arg="http://$container_ip:18080/"
        args+=("$arg")
    done
    command curl "${args[@]}"
}
for mode in off native xorpub random; do
    CLIENT_ENCRYPTION=none; VLESS_DECRYPTION=none
    if [[ "$mode" != off ]]; then mapfile -t pair < <(generate_vless_encryption_pair "$mode"); VLESS_DECRYPTION="${pair[0]}"; CLIENT_ENCRYPTION="${pair[1]}"; fi
    write_config "$uuid" "${keys[0]}"
    # 测试源为私网地址；仅在隔离容器的配置中显式放行该地址和端口。
    jq --arg ip "$container_ip/32" '(.outbounds[] | select(.protocol=="freedom") | .settings.finalRules)=[{action:"allow",network:"tcp",ip:[$ip],port:"18080"}]' "$CONFIG" > "$TEST_DIR/scoped.json"
    cat "$TEST_DIR/scoped.json" > "$CONFIG"
    config_ok
    setpriv --reuid=xray --regid=xray --init-groups "$XRAY_BIN" run -config "$CONFIG" > "$TEST_DIR/server.log" 2>&1 & pid=$!
    sleep 1
    self_http_check "$SNI" "$container_ip" 443
    self_client_probe "$SNI" "$container_ip"
    kill "$pid"; wait "$pid" || true; pid=''
    printf '真实 Nginx HTTPS 回落 + 非 root REALITY/Vision/%s 握手通过\n' "$mode"
done
