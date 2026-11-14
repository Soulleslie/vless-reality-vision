#!/usr/bin/env bash
# 真实 Certbot + Pebble HTTP-01。仅测试 wrapper 将生产 ACME URL 替换为本地测试 CA。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
[[ $EUID == 0 && -f /.dockerenv ]] || exit 1
SELF_METHOD=http; SELF_EMAIL=admin@example.test; SNI=node.example.test
mkdir -p "$SELF_DIR/"{acme,logs,work}
: > "$SELF_DIR/files.sha256"
rm /etc/nginx/sites-enabled/default
self_site_write; self_nginx_write "$SNI" no
nginx -t; nginx
self_http_challenge_check "$SNI" "$(hostname -I | awk '{print $1}')"
trap 'nginx -s quit 2>/dev/null || true' EXIT
self_certbot() {
    local args=() skip=0 arg
    for arg in "$@"; do
        if (( skip )); then skip=0; continue; fi
        if [[ "$arg" == --server ]]; then skip=1; else args+=("$arg"); fi
    done
    REQUESTS_CA_BUNDLE=/pebble-ca.pem certbot "${args[@]}" --server https://pebble:14000/dir --no-random-sleep-on-renew \
        --config-dir "$SELF_DIR/acme" --work-dir "$SELF_DIR/work" --logs-dir "$SELF_DIR/logs"
}
if ! self_issue_cert "$SNI"; then cat "$SELF_DIR/logs/issue.log"; exit 1; fi
# 信任仅用于容器的 Pebble 签发根，HTTPS 测试仍严格校验证书。
curl --noproxy '*' --cacert /pebble-ca.pem -fsS https://pebble:15000/roots/0 > /usr/local/share/ca-certificates/pebble-issued-root.crt
update-ca-certificates >/dev/null 2>&1
self_nginx_write "$SNI"; nginx -t; nginx -s reload
self_reload_hook_write
# 容器没有 systemd；仅将 reload 命令转换成真实 Nginx reload，仍执行生产 deploy hook。
cat > /usr/local/bin/systemctl <<'EOF'
#!/bin/sh
[ "$1" = reload ] && [ "$2" = nginx ] && exec nginx -s reload
exit 1
EOF
chmod 755 /usr/local/bin/systemctl
if ! self_renew_test "$SNI"; then cat "$SELF_DIR/logs/renew-test.log"; exit 1; fi
self_tls_check "$SNI" 127.0.0.1:8443
self_http_check "$SNI" 127.0.0.1 8443
jq -e '.result=="passed"' "$SELF_DIR/renew-test.json" >/dev/null
printf '真实 Certbot HTTP-01 签发、renew --dry-run 和 Nginx deploy hook 均通过（Pebble 测试 CA）\n'
