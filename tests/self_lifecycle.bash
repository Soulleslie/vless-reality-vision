#!/usr/bin/env bash
# 故障注入：ACME、DNS、systemd 为替身；实际协议测试见 integration/self_tls.bash。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" != --child ]]; then
    for stage in success dns provider credentials cert renewal timer nginx xray target; do
        bash "${BASH_SOURCE[0]}" --child "$stage" cloudflare
    done
    bash "${BASH_SOURCE[0]}" --child success http
    printf '自有域名安装、证书/服务失败回滚、域名切换和卸载保护测试通过\n'
    exit 0
fi
STAGE="$2"; METHOD="$3"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
CONFIG_DIR="$TEST_DIR/xray"; CONFIG="$CONFIG_DIR/config.json"; MARKER="$CONFIG_DIR/.vless-reality-owned"
SERVICE="$TEST_DIR/xray.service"; XRAY_BIN="$TEST_DIR/xray-bin"; LINK_FILE="$TEST_DIR/link"
SELF_POLICY="$TEST_DIR/policy-rc.d"; SELF_DIR="$TEST_DIR/self"; SELF_SITE="$TEST_DIR/site.conf"; SELF_WEB="$TEST_DIR/web"
SELF_RENEW_SERVICE="$TEST_DIR/cert.service"; SELF_RENEW_TIMER="$TEST_DIR/cert.timer"
MANAGER="$TEST_DIR/manager.sh"; SHORTCUT="$TEST_DIR/shortcut"; TFO_SYSCTL="$TEST_DIR/tfo"
mkdir -p "$TEST_DIR/bin" "$TEST_DIR/units"
export PATH="$TEST_DIR/bin:$PATH"
for program in nginx systemctl; do printf '#!/bin/sh\nexit 0\n' > "$TEST_DIR/bin/$program"; chmod 755 "$TEST_DIR/bin/$program"; done
printf 'dns_cloudflare_api_token = abcdefghijklmnopqrstuvwxyz12345\n' > "$TEST_DIR/credentials.ini"
chmod 600 "$TEST_DIR/credentials.ini"
[[ "$STAGE" != credentials ]] || chmod 644 "$TEST_DIR/credentials.ini"
export VLESS_CF_CREDENTIALS="$TEST_DIR/credentials.ini"
need_root() { :; }; need_command() { :; }; ensure_dependencies() { :; }; self_extra_dependencies() { :; }
self_dns_check() { [[ "$STAGE" != dns ]]; }; self_cloudflare_zone() { [[ "$STAGE" != provider ]]; }; self_tls_check() { :; }; self_reject_check() { :; }; self_loaded_cert_matches() { :; }
public_ipv4() { printf '203.0.113.1'; }; chown() { :; }; getent() { return 2; }; groupadd() { :; }; useradd() { :; }
stat() { if [[ "$*" == '-c %u '* ]]; then printf 0; else command stat "$@"; fi; }
install() {
    local args=() skip=0 arg
    for arg in "$@"; do
        if (( skip )); then skip=0; continue; fi
        case "$arg" in -o|-g) skip=1 ;; *) args+=("$arg") ;; esac
    done
    command install "${args[@]}"
}
save_manager() { cp "$ROOT/install.sh" "$MANAGER"; MANAGER_COPIED=1; }
fetch_release_metadata() { RELEASE_VERSION=26.11.9; }
download_verified_release() { : > "$1"; }
unzip() {
    cat > "${@: -1}/xray" <<'EOF'
#!/bin/sh
case "$1" in
 uuid) echo 00000000-0000-4000-8000-000000000000 ;;
 x25519) printf 'PrivateKey: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\nPublicKey: BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB\n' ;;
 run) exit 0 ;;
 version) echo 'Xray 26.11.9' ;;
esac
EOF
}
ss() {
    case "$*" in
        *:443*) [[ ! -f "$TEST_DIR/units/active-xray" ]] || printf 'LISTEN 0 1 0.0.0.0:443\n' ;;
        *:8443*) [[ ! -f "$TEST_DIR/units/active-nginx" ]] || printf 'LISTEN 0 1 127.0.0.1:8443\n' ;;
    esac
    return 0
}
nginx() {
    case "$1" in -v) echo nginx/1.22.1 >&2 ;; -T) echo 'include /etc/nginx/conf.d/*.conf;' ;; *) return 0 ;; esac
}
systemctl() {
    local cmd="$1" unit="${@: -1}"
    case "$cmd" in
        cat) return 1 ;;
        is-active) [[ -f "$TEST_DIR/units/active-$unit" ]] ;;
        is-enabled) [[ -f "$TEST_DIR/units/enabled-$unit" ]] ;;
        daemon-reload|reload) return 0 ;;
        start|restart|enable)
            [[ "$STAGE" != nginx || "$unit" != nginx ]] || return 1
            [[ "$STAGE" != xray || "$unit" != xray ]] || return 1
            [[ "$STAGE" != timer || "$unit" != vless-reality-cert.timer ]] || return 1
            [[ "$cmd" != enable ]] || touch "$TEST_DIR/units/enabled-$unit"
            touch "$TEST_DIR/units/active-$unit" ;;
        stop) rm -f "$TEST_DIR/units/active-$unit" ;;
        disable) rm -f "$TEST_DIR/units/enabled-$unit" ;;
        *) return 1 ;;
    esac
}
curl() {
    if [[ "$1" == --version ]]; then printf 'curl HTTP2\n';
    elif [[ "$*" == *'.well-known/acme-challenge/'* ]]; then cat "$SELF_WEB/.well-known/acme-challenge/${*: -1:1}" 2>/dev/null || printf '%s' "${*: -1}" | awk -F/ '{print $NF}';
    else printf '2 200'; fi
}
self_certbot() {
    if [[ "$1" == certonly ]]; then
        [[ "$STAGE" != cert ]] || return 1
        if [[ "$METHOD" == cloudflare ]]; then
            [[ "$*" == *'--dns-cloudflare --dns-cloudflare-credentials '* && "$*" == *'--dns-cloudflare-propagation-seconds 60'* ]] || return 1
        else [[ "$*" == *'--webroot --webroot-path '* ]] || return 1; fi
        local domain='' previous='' arg
        for arg in "$@"; do [[ "$previous" != -d ]] || domain="$arg"; previous="$arg"; done
        mkdir -p "$SELF_DIR/acme/live/$domain"
        touch "$SELF_DIR/acme/live/$domain/"{cert,fullchain,privkey}.pem
    else
        [[ "$*" == *'--dry-run'* ]] || return 1
        [[ "$STAGE" != renewal && "$STAGE" != domain-renewal ]] || return 1
    fi
}
self_client_probe() { :; }
self_nginx_shared() { return 1; }
# 目标配置错误必须让安装最终检查失败。
if [[ "$STAGE" == target ]]; then self_config_check() { return 1; }; fi
set +e
( set -e; install_self node.example.com "$METHOD" admin@example.com Test off off > "$TEST_DIR/install.log" 2>&1 )
result=$?
set -e
if (( result == 0 )); then
    [[ "$STAGE" == success ]] || { echo "故障 $STAGE 未阻止安装"; exit 1; }
else
    [[ "$STAGE" != success ]] || { cat "$TEST_DIR/install.log"; exit 1; }
    [[ ! -e "$SELF_DIR" && ! -e "$SELF_WEB" && ! -e "$SELF_SITE" && ! -e "$SELF_RENEW_TIMER" && ! -e "$XRAY_BIN" && ! -e "$CONFIG_DIR" ]] || { echo "故障 $STAGE 回滚有残留"; ls -la "$TEST_DIR"; exit 1; }
    exit 0
fi
load_metadata
self_managed_paths_ok
mv "$SELF_DIR/work" "$TEST_DIR/work-kept"
ln -s "$TEST_DIR/work-kept" "$SELF_DIR/work"
if self_managed_paths_ok; then echo '不能沿符号链接操作共享证书目录'; exit 1; fi
rm "$SELF_DIR/work"; mv "$TEST_DIR/work-kept" "$SELF_DIR/work"
# 重复安装受保护。
if (install_self node.example.com "$METHOD" admin@example.com Test >/dev/null 2>&1); then exit 1; fi
[[ "$NODE_MODE" == self && "$(< "$LINK_FILE")" == *'@node.example.com:443?'* ]]
old_config="$(sha256sum "$CONFIG")"; old_site="$(sha256sum "$SELF_SITE")"
STAGE=domain-renewal
if (self_domain_apply other.example.com >/dev/null 2>&1); then echo '域名续期失败应回滚'; exit 1; fi
[[ "$(sha256sum "$CONFIG")" == "$old_config" && "$(sha256sum "$SELF_SITE")" == "$old_site" ]]
[[ "$(self_state domain)" == node.example.com ]]
STAGE=success
self_domain_apply other.example.com > "$TEST_DIR/domain.log" 2>&1 || { cat "$TEST_DIR/domain.log"; exit 1; }
load_metadata
[[ "$SNI" == other.example.com && "$(< "$LINK_FILE")" == *'@other.example.com:443?'* ]]
# hook 缺失不能仅凭旧的 dry-run 记录报续期正常。
mv "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx" "$SELF_DIR/work/hook-backup"
if self_renew_ready >/dev/null 2>&1; then echo '缺失 hook 不应通过检查'; exit 1; fi
mv "$SELF_DIR/work/hook-backup" "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx"
# 中断的包安装保护文件也应随卸载清理。
printf '#!/bin/sh\n# vless-reality-self package guard\nexit 101\n' > "$SELF_POLICY"
self_track "$SELF_POLICY"
# 改动的站点文件、用户新增数据必须被保护。
printf '\n# user change\n' >> "$SELF_SITE"
if self_cleanup_preflight >/dev/null 2>&1; then echo '不能删除已修改站点'; exit 1; fi
sed -i '$d' "$SELF_SITE"; sed -i '$d' "$SELF_SITE"
printf 'foreign\n' > "$SELF_WEB/user.txt"
if self_cleanup_preflight >/dev/null 2>&1; then echo '不能删除用户网站数据'; exit 1; fi
rm "$SELF_WEB/user.txt"
confirm() { return 0; }
(uninstall_node) > "$TEST_DIR/uninstall.log" 2>&1 || { cat "$TEST_DIR/uninstall.log"; exit 1; }
[[ ! -e "$SELF_DIR" && ! -e "$SELF_WEB" && ! -e "$SELF_SITE" && ! -e "$SELF_RENEW_SERVICE" && ! -e "$SELF_RENEW_TIMER" && ! -e "$CONFIG_DIR" && ! -e "$MANAGER" && ! -e "$LINK_FILE" && ! -e "$SELF_POLICY" && ! -e "${SELF_RENEW_SERVICE%.service}-alert.service" ]]
