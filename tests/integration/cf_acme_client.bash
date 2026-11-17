#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
[[ $EUID == 0 && -f /.dockerenv ]] || exit 1
TEST_DIR="$(mktemp -d)"; provider_pid=''; server_pid=''; origin_pid=''
trap 'for pid in "$provider_pid" "$server_pid" "$origin_pid"; do [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true; done; nginx -s quit 2>/dev/null || true; rm -rf -- "$TEST_DIR"' EXIT
OLD_TOKEN=old_cloudflare_api_fixture_1234567890
NEW_TOKEN=new_cloudflare_api_fixture_0987654321
DENIED_TOKEN=readonly_cloudflare_api_fixture_12345
printf '{"tokens":{"%s":["zone","edit"],"%s":["zone","edit"],"%s":["zone"]}}\n' "$OLD_TOKEN" "$NEW_TOKEN" "$DENIED_TOKEN" > "$TEST_DIR/provider.json"
python3 "$ROOT/tests/integration/cf_provider.py" "$TEST_DIR/provider.json" > "$TEST_DIR/provider.log" 2>&1 & provider_pid=$!
for attempt in {1..30}; do
    if curl --noproxy '*' -fsS http://127.0.0.1:8055/metrics -o /dev/null 2>/dev/null; then break; fi
    sleep 0.1
done
install -m 755 "$ROOT/tests/integration/cf_certbot.py" /usr/local/bin/certbot
SELF_METHOD=cloudflare; SELF_EMAIL=admin@example.test; SNI=node.example.test
self_cloudflare_zone() { return 0; } # 合成域名没有公网 NS；真实 TXT/DNS-01 仍由测试 CA 验证。
mkdir -p "$SELF_DIR/"{acme,work,logs} "$CONFIG_DIR"
printf 'vless-reality-self-v1\n' > "$SELF_DIR/.owned"; : > "$SELF_DIR/files.sha256"
: > "$SELF_DIR/cli.ini"; self_track "$SELF_DIR/cli.ini"
printf 'dns_cloudflare_api_token = %s\n' "$OLD_TOKEN" > "$SELF_DIR/cloudflare.ini"; chmod 600 "$SELF_DIR/cloudflare.ini"
jq -n --arg domain "$SNI" --arg email "$SELF_EMAIL" '{domain:$domain,email:$email,method:"cloudflare",nginx_active:false,nginx_enabled:false}' > "$SELF_DIR/state.json"
self_track "$SELF_DIR/cloudflare.ini"; self_track "$SELF_DIR/state.json"
rm /etc/nginx/sites-enabled/default
self_site_write
if ! self_issue_cert "$SNI"; then cat "$SELF_DIR/logs/issue.log"; exit 1; fi
curl --noproxy '*' --cacert /pebble-ca.pem -fsS https://pebble:15000/roots/0 > /usr/local/share/ca-certificates/pebble-issued-root.crt
update-ca-certificates >/dev/null 2>&1
self_nginx_write "$SNI"; nginx -t; nginx
self_reload_hook_write
cat > /usr/local/bin/systemctl <<'SYSTEMCTL'
#!/bin/sh
for unit do :; done
case "$1" in
    is-enabled|is-active)
        if [ "$unit" = vless-reality-cert.timer ]; then test ! -e /tmp/cf-timer-stopped
        elif [ "$1" = is-active ] && [ "$unit" = nginx ]; then test -s /run/nginx.pid && kill -0 "$(cat /run/nginx.pid)"
        else exit 1; fi ;;
    reload) [ "$unit" = nginx ] || exit 1; printf 'reload\n' >> /tmp/cf-nginx-actions; exec nginx -s reload ;;
    stop) if [ "$unit" = nginx ]; then nginx -s quit; else touch /tmp/cf-timer-stopped; fi ;;
    disable|daemon-reload|reset-failed) exit 0 ;;
    *) exit 1 ;;
esac
SYSTEMCTL
chmod 755 /usr/local/bin/systemctl
printf 'timer\n' > "$SELF_RENEW_TIMER"; printf 'service\n' > "$SELF_RENEW_SERVICE"
self_track "$SELF_RENEW_TIMER"; self_track "$SELF_RENEW_SERVICE"
XRAY_BIN=/xray; PORT=443; NODE_NAME=CF-Test; NODE_MODE=self; ADDR_MODE=domain
SERVER_IP="$(hostname -I | awk '{print $1}')"; SHORT_ID="$(openssl rand -hex 8)"
uuid="$("$XRAY_BIN" uuid)"; mapfile -t keys < <(generate_reality_keys); PUBLIC_KEY="${keys[1]}"
groupadd --system xray; useradd --system --gid xray --shell /usr/sbin/nologin xray
install -d -o root -g xray -m 750 "$CONFIG_DIR"
write_config "$uuid" "${keys[0]}"; write_marker; show_node >/dev/null
# 仅测试配置精确放行本容器的独立 HTTP 源，生产私网防护不变。
jq --arg ip "$SERVER_IP/32" '(.outbounds[] | select(.protocol=="freedom") | .settings.finalRules)=[{action:"allow",network:"tcp",ip:[$ip],port:"18080"}]' "$CONFIG" > "$TEST_DIR/scoped.json"
cat "$TEST_DIR/scoped.json" > "$CONFIG"; config_ok
mkdir "$TEST_DIR/origin"; printf 'CF rotation origin\n' > "$TEST_DIR/origin/index.html"
python3 -m http.server 18080 --bind 0.0.0.0 --directory "$TEST_DIR/origin" > "$TEST_DIR/origin.log" 2>&1 & origin_pid=$!
setpriv --reuid=xray --regid=xray --init-groups "$XRAY_BIN" run -config "$CONFIG" 7>&- 8>&- 9>&- > "$TEST_DIR/xray.log" 2>&1 & server_pid=$!
curl() {
    local args=() arg
    for arg in "$@"; do [[ "$arg" != https://www.debian.org/ ]] || arg="http://$SERVER_IP:18080/"; args+=("$arg"); done
    command curl "${args[@]}"
}
sleep 0.3
self_client_probe "$SNI" "$SERVER_IP"
if ! self_renew_test "$SNI"; then cat "$SELF_DIR/logs/renew-test.log"; exit 1; fi
nginx_pid="$(< /run/nginx.pid)"
immutable="$(sha256sum "$CONFIG" "$MARKER" "$LINK_FILE" "$SELF_SITE" "$SELF_WEB/index.html" "$SELF_DIR/state.json" "$SELF_RENEW_TIMER" "$SELF_RENEW_SERVICE" "$SELF_DIR/acme/live/$SNI/"*.pem "$SELF_DIR/acme/renewal/$SNI.conf")"
credential_before="$(sha256sum "$SELF_DIR/cloudflare.ini" "$SELF_DIR/files.sha256" "$SELF_DIR/renew-test.json")"
printf 'dns_cloudflare_api_token = %s\n' "$DENIED_TOKEN" > "$TEST_DIR/denied.ini"; chmod 600 "$TEST_DIR/denied.ini"
if (VLESS_CF_CREDENTIALS="$TEST_DIR/denied.ini" self_cf_token_rotate > "$TEST_DIR/denied.log" 2>&1); then echo '只读 Token 不应通过全新 DNS-01 验证'; exit 1; fi
[[ "$(sha256sum "$SELF_DIR/cloudflare.ini" "$SELF_DIR/files.sha256" "$SELF_DIR/renew-test.json")" == "$credential_before" ]]
printf 'dns_cloudflare_api_token = %s\n' "$NEW_TOKEN" > "$TEST_DIR/new.ini"; chmod 600 "$TEST_DIR/new.ini"
if ! (VLESS_CF_CREDENTIALS="$TEST_DIR/new.ini" self_cf_token_rotate > "$TEST_DIR/change.log" 2>&1); then cat "$TEST_DIR/change.log"; exit 1; fi
[[ "$(sha256sum "$CONFIG" "$MARKER" "$LINK_FILE" "$SELF_SITE" "$SELF_WEB/index.html" "$SELF_DIR/state.json" "$SELF_RENEW_TIMER" "$SELF_RENEW_SERVICE" "$SELF_DIR/acme/live/$SNI/"*.pem "$SELF_DIR/acme/renewal/$SNI.conf")" == "$immutable" ]]
[[ "$(< /run/nginx.pid)" == "$nginx_pid" && "$(< "$SELF_DIR/cloudflare.ini")" == *"$NEW_TOKEN"* ]]
self_file_owned "$SELF_DIR/cloudflare.ini"; self_cf_renewal_binding
kill -0 "$server_pid"; self_client_probe "$SNI" "$SERVER_IP"
jq -e '.result=="passed"' "$SELF_DIR/renew-test.json" >/dev/null
if rg -q -F -e "$OLD_TOKEN" -e "$NEW_TOKEN" -e "$DENIED_TOKEN" "$SELF_DIR/logs" "$TEST_DIR/change.log" "$TEST_DIR/denied.log"; then echo 'Token 日志脱敏失败'; exit 1; fi
[[ -z "$(find "$SELF_DIR/work" -name 'token-backup.*')" && -z "$(find "$SELF_DIR/logs" -name 'token-probe.*')" ]]
# 撤销模拟旧 Token；随后强制测试 CA 进入到期续期路径，仍执行原生产函数。
python3 - "$TEST_DIR/provider.json" <<'PY_REVOKE'
import json, sys
path=sys.argv[1]; data=json.load(open(path))
data["tokens"]={k:v for k,v in data["tokens"].items() if not k.startswith("old_")}
json.dump(data,open(path,"w"))
PY_REVOKE
cert_before="$(sha256sum "$SELF_DIR/acme/live/$SNI/cert.pem")"
self_dns_check() { return 0; }; security_dns_changed() { return 0; } # Synthetic domain, not public DNS.
if ! self_cert_renew; then cat "$SELF_DIR/logs/renew.log"; exit 1; fi
[[ "$(sha256sum "$SELF_DIR/acme/live/$SNI/cert.pem")" != "$cert_before" ]]
jq -e '.result=="passed"' "$SELF_DIR/renew-status.json" >/dev/null
self_wait_tls "$SNI"
kill -0 "$server_pid"; self_client_probe "$SNI" "$SERVER_IP"
curl --noproxy '*' -fsS http://127.0.0.1:8055/metrics > "$TEST_DIR/metrics.json"
python3 - "$TEST_DIR/metrics.json" "$TEST_DIR/new.ini" <<'PY_METRICS'
import hashlib, json, sys
data=json.load(open(sys.argv[1]))["result"]
assert data["denied"]>=1 and data["records"]==[] and data["queries"]>0
token=open(sys.argv[2]).read().split("=",1)[1].strip()
count=data["created"].get(hashlib.sha256(token.encode()).hexdigest(),0)
assert count>=3, f"New Token TXT creations: {count}; expected at least 3 independent DNS-01 cycles"
PY_METRICS
mkdir "$SELF_DIR/work/token-backup.orphan"; cp "$SELF_DIR/cloudflare.ini" "$SELF_DIR/work/token-backup.orphan/old.ini"
kill "$server_pid"; wait "$server_pid" || true; server_pid=''
self_cleanup
[[ ! -e "$SELF_DIR" && ! -e "$SELF_WEB" && ! -e "$SELF_SITE" && ! -e "$SELF_RENEW_TIMER" && -f "$TEST_DIR/new.ini" ]]
printf '真实 CF 插件/DNS-01：权限拒绝、Token 轮换、证书/节点保留、旧 Token 撤销后的正常续期、VLESS/Vision 连接、日志脱敏与私有资料清理通过（隔离提供商/测试 CA）\n'
