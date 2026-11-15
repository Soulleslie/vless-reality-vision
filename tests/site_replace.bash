#!/usr/bin/env bash
# 事务与故障注入使用本机 HTTPS 替身；真实服务/内容测试见 integration/self_tls.bash。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"; trap 'rm -rf -- "$TEST_DIR"' EXIT
need_root() { :; }; chown() { :; }
stat() {
    if [[ "$STAGE" == filesystem && "$*" == "-c %d $SELF_WEB/.well-known/acme-challenge" ]]; then printf 0
    elif [[ "$STAGE" == owner && "$*" == "-c %u $SELF_WEB/.well-known/acme-challenge" ]]; then printf 123
    elif [[ "$*" == '-c %u '* ]]; then printf 0
    else command stat "$@"; fi
}
config_ok() { self_config_policy "$CONFIG" "$SNI"; }
# 明确禁止更换网页调用联网/安装/服务变更路径。
ensure_dependencies() { return 99; }; public_ipv4() { return 99; }; self_dns_check() { return 99; }
self_issue_cert() { return 99; }; self_client_probe() { return 99; }; self_nginx_apply() { return 99; }
systemctl() {
    [[ "$*" == 'is-active --quiet nginx' && "$STAGE" != inactive ]] && return 0
    printf '%s\n' "$*" >> "$TEST_DIR/systemctl.calls"; return 1
}
eval "$(declare -f self_site_render | sed '1s/self_site_render/real_site_render/')"
self_site_render() {
    case "$STAGE" in
        render) printf partial; return 1 ;;
        empty) return 0 ;;
        signal-render) kill -TERM "$BASHPID"; return 1 ;;
        *) real_site_render "$@" ;;
    esac
}
# 计数持久保存在事务子 shell 外可见的位置。
self_site_http_matches() {
    printf 'http\n' >> "$SELF_DIR/work/http.calls"
    local calls
    calls="$(wc -l < "$SELF_DIR/work/http.calls")"
    [[ "$STAGE" != baseline ]] || return 1
    if [[ "$STAGE" == http || "$STAGE" == rollback ]] && [[ "$calls" == 2 ]]; then return 1; fi
    if [[ "$STAGE" == signal-publish && "$calls" == 2 ]]; then kill -TERM "$BASHPID"; return 1; fi
    [[ -s "$2" ]]
}
cp() {
    if [[ "$STAGE" == backup && "${@: -1}" == "$SELF_DIR/work/site-backup."*/index.html ]]; then return 1; fi
    if [[ "$STAGE" == rollback && "${1:-}" == -- && "${2:-}" == "$SELF_DIR/work/site-backup."*/index.html ]]; then return 1; fi
    command cp "$@"
}
mv() {
    if [[ "$STAGE" == publish && "${@: -1}" == "$SELF_WEB/index.html" && ! -e "$SELF_DIR/work/injected" ]]; then
        touch "$SELF_DIR/work/injected"; return 1
    fi
    if [[ "$STAGE" == record && "${@: -1}" == "$SELF_DIR/files.sha256" && ! -e "$SELF_DIR/work/injected" ]]; then
        touch "$SELF_DIR/work/injected"; return 1
    fi
    command mv "$@"
}
fixture() {
    STAGE=success
    SELF_DIR="$TEST_DIR/$1/self"; SELF_WEB="$TEST_DIR/$1/web"; CONFIG_DIR="$TEST_DIR/$1/config"
    CONFIG="$CONFIG_DIR/config.json"; MARKER="$CONFIG_DIR/.vless-reality-owned"; LINK_FILE="$TEST_DIR/$1/link"
    SELF_SITE="$TEST_DIR/$1/site.conf"; SELF_POLICY="$TEST_DIR/$1/policy"
    SELF_RENEW_SERVICE="$TEST_DIR/$1/cert.service"; SELF_RENEW_TIMER="$TEST_DIR/$1/cert.timer"; TFO_SYSCTL="$TEST_DIR/$1/tfo"
    mkdir -p "$CONFIG_DIR" "$SELF_DIR/"{work,logs,acme/live/node.example.com} "$SELF_WEB"
    chmod 700 "$SELF_DIR"; chmod 755 "$SELF_WEB"
    printf 'vless-reality-self-v1\n' > "$SELF_DIR/.owned"; : > "$SELF_DIR/files.sha256"
    printf '<!doctype html><html><body class="profile">原网页</body></html>\n' > "$SELF_WEB/index.html"
    chmod 644 "$SELF_WEB/index.html"
    printf '{"domain":"node.example.com","method":"cloudflare","nginx_active":false,"nginx_enabled":false}\n' > "$SELF_DIR/state.json"
    printf 'owned nginx configuration\n' > "$SELF_SITE"
    printf 'timer\n' > "$SELF_RENEW_TIMER"; printf 'service\n' > "$SELF_RENEW_SERVICE"
    printf 'certificate\n' > "$SELF_DIR/acme/live/node.example.com/cert.pem"
    printf 'credentials\n' > "$SELF_DIR/cloudflare.ini"; chmod 600 "$SELF_DIR/cloudflare.ini"
    printf 'tfo\n' > "$TFO_SYSCTL"
    for path in "$SELF_WEB/index.html" "$SELF_SITE" "$SELF_DIR/state.json" "$SELF_RENEW_SERVICE" "$SELF_RENEW_TIMER" "$SELF_DIR/cloudflare.ini"; do self_track "$path"; done
    PORT=443; SNI=node.example.com; NODE_NAME=Existing; SERVER_IP=203.0.113.1; PUBLIC_KEY=pub
    SHORT_ID=0123456789abcdef; NODE_MODE=self; ADDR_MODE=ip; ADDR_DOMAIN=''; TFO_ENABLED=1
    CLIENT_ENCRYPTION=mlkem768x25519plus.native.0rtt.test; VLESS_DECRYPTION=none
    write_config 00000000-0000-4000-8000-000000000000 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    write_marker; printf 'protected link\n' > "$LINK_FILE"
}
immutable() {
    sha256sum "$CONFIG" "$MARKER" "$LINK_FILE" "$SELF_SITE" "$SELF_DIR/state.json" "$SELF_RENEW_SERVICE" "$SELF_RENEW_TIMER" \
        "$SELF_DIR/acme/live/node.example.com/cert.pem" "$SELF_DIR/cloudflare.ini" "$TFO_SYSCTL"
}
for stage in success legacy render empty backup record publish baseline http rollback signal-render signal-publish inactive modified unknown symlink directory-link writable filesystem owner; do
    fixture "$stage"
    case "$stage" in
        legacy) printf '<!doctype html><title>旧网页</title>\n' > "$SELF_WEB/index.html"; self_track "$SELF_WEB/index.html" ;;
        modified) printf 'user change\n' >> "$SELF_WEB/index.html" ;;
        unknown) printf 'user data\n' > "$SELF_WEB/user.txt" ;;
        symlink) command mv "$SELF_WEB/index.html" "$TEST_DIR/foreign"; ln -s "$TEST_DIR/foreign" "$SELF_WEB/index.html" ;;
        directory-link) ln -s "$TEST_DIR" "$SELF_WEB/.well-known" ;;
        writable) chmod 777 "$SELF_WEB" ;;
    esac
    before="$(immutable)"; page_before="$(sha256sum "$SELF_WEB/index.html" "$SELF_DIR/files.sha256")"
    STAGE="$stage"; rc=0
    (website_random) > "$TEST_DIR/$stage/result.log" 2>&1 || rc=$?
    [[ "$(immutable)" == "$before" ]]
    if [[ "$stage" == success || "$stage" == legacy ]]; then
        [[ "$rc" == 0 && "$(sha256sum "$SELF_WEB/index.html" "$SELF_DIR/files.sha256")" != "$page_before" ]]
        [[ "$(< "$SELF_WEB/index.html")" == *'<body class="'* ]]
        [[ "$stage" != success || "$(< "$SELF_WEB/index.html")" != *'<body class="profile"'* ]]
        self_file_owned "$SELF_WEB/index.html"; self_cleanup_preflight
        [[ "$(stat -c %a "$SELF_WEB/index.html")" == 644 ]]
    elif [[ "$stage" == rollback ]]; then
        [[ "$rc" != 0 && "$(< "$TEST_DIR/$stage/result.log")" == *'回滚失败，保留备份：'* ]]
        backup="$(find "$SELF_DIR/work" -type d -name 'site-backup.*')"
        [[ -f "$backup/index.html" && -f "$backup/files.sha256" ]]
        STAGE=success; self_site_atomic_publish "$backup/index.html"; command cp -a "$backup/files.sha256" "$SELF_DIR/files.sha256"
        rm -rf -- "$backup"
        [[ "$(sha256sum "$SELF_WEB/index.html" "$SELF_DIR/files.sha256")" == "$page_before" ]]
    else
        [[ "$rc" != 0 && "$(sha256sum "$SELF_WEB/index.html" "$SELF_DIR/files.sha256")" == "$page_before" ]]
    fi
    [[ -z "$(find "$SELF_DIR/work" -name 'site-backup.*' -o -name 'site-response.*')" ]]
    [[ -z "$(find "$SELF_WEB" -name '.page.*')" && -z "$(find "$SELF_DIR" -name '.receipt.*')" ]]
done
# 六种现有布局都必须换成其他布局，节点信息仍保持。
for kind in profile journal studio gallery library trail; do
    fixture "layout-$kind"
    printf '<!doctype html><html><body class="%s">旧布局</body></html>\n' "$kind" > "$SELF_WEB/index.html"
    self_track "$SELF_WEB/index.html"; before="$(immutable)"
    website_random >/dev/null
    [[ "$(< "$SELF_WEB/index.html")" != *"<body class=\"$kind\""* && "$(immutable)" == "$before" ]]
    self_file_owned "$SELF_WEB/index.html"
done
# 与其他管理操作共用目录锁，等待期间不提前读取或生成新网页。
fixture concurrent
exec 9< "$CONFIG_DIR"; flock -x 9
(exec 9<&-; website_random > "$TEST_DIR/concurrent/result.log" 2>&1) & replace_pid=$!
sleep 0.1
kill -0 "$replace_pid"; [[ ! -e "$SELF_DIR/work/http.calls" ]]
exec 9<&-
wait "$replace_pid"; self_file_owned "$SELF_WEB/index.html"
# 非自有域名模式及非法参数必须无修改拒绝。
fixture external; NODE_MODE=external; write_marker; before="$(immutable)"
if (website_random >/dev/null 2>&1); then exit 1; fi
[[ "$(immutable)" == "$before" ]]
if (website_random unexpected >/dev/null 2>&1); then exit 1; fi
[[ ! -e "$TEST_DIR/systemctl.calls" || "$(< "$TEST_DIR/systemctl.calls")" == 'is-active --quiet nginx' ]]
printf '已有网页迁移、节点/证书/链接保留、免重启、失败/信号回滚、归属保护与暂存清理通过\n'
