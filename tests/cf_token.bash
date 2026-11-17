#!/usr/bin/env bash
# Token 事务故障注入；真实 Certbot/DNS-01 流程由隔离集成测试覆盖。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"; trap 'rm -rf -- "$TEST_DIR"' EXIT
OLD_TOKEN=old_cloudflare_token_fixture_1234567890
NEW_TOKEN=new_cloudflare_token_fixture_0987654321
export token=ambient_nonsecret_fixture
export current_token=ambient_nonsecret_fixture_two
STAGE=success
trap 'printf "Token 测试失败：%s，第 %s 行\n" "$STAGE" "$LINENO" >&2' ERR
need_root() { :; }; chown() { :; }
eval "$(declare -f self_scrub_logs | sed '1s/self_scrub_logs/real_cf_scrub_logs/')"
self_scrub_logs() { [[ "$STAGE" != scrub ]] && real_cf_scrub_logs "$@"; }
stat() {
    if [[ "$STAGE" == source-owner && "$*" == "-c %u $VLESS_CF_CREDENTIALS" ]]; then printf 123
    elif [[ "$*" == '-c %u '* ]]; then printf 0
    else command stat "$@"; fi
}
public_ipv4() { return 99; }; ensure_dependencies() { return 99; }; self_dns_check() { return 99; }
self_wait_tls() {
    printf 'tls\n' >> "$CASE_DIR/tls.calls"
    [[ "$STAGE" != baseline ]] && { [[ "$STAGE" != tls-late ]] || [[ "$(wc -l < "$CASE_DIR/tls.calls")" == 1 ]]; }
}
assert_token_environment() {
    python3 - "$SELF_DIR/cloudflare.ini" "$VLESS_CF_CREDENTIALS" <<'PY_ENV'
import os, pathlib, re, sys
for name in sys.argv[1:]:
    path=pathlib.Path(name)
    if not path.is_file(): continue
    matches=re.findall(r"^dns_cloudflare_api_token\s*=\s*([A-Za-z0-9_-]{20,200})\s*$",path.read_text(),re.M)
    assert not any(value in item for value in matches for item in os.environ.values()), "Token 被导出到子进程环境"
PY_ENV
}
systemctl() {
    case "$*" in
        'is-enabled --quiet vless-reality-cert.timer') [[ "$STAGE" != timer ]] ;;
        'is-active --quiet vless-reality-cert.timer')
            printf 'timer\n' >> "$CASE_DIR/timer.calls"
            [[ "$STAGE" != timer-late || "$(wc -l < "$CASE_DIR/timer.calls")" == 1 ]] ;;
        *) printf '%s\n' "$*" >> "$CASE_DIR/unexpected-service.calls"; return 1 ;;
    esac
}
certbot() {
    local args="$*" arg prior='' credentials='' conf='' logs=''
    [[ "$args" != *"$OLD_TOKEN"* && "$args" != *"$NEW_TOKEN"* ]]
    assert_token_environment
    for arg in "$@"; do
        case "$prior" in --dns-cloudflare-credentials) credentials="$arg" ;; --config-dir) conf="$arg" ;; --logs-dir) logs="$arg" ;; esac
        prior="$arg"
    done
    printf '%s\n' "$args" >> "$CASE_DIR/certbot.calls"
    if [[ "$1" == certonly ]]; then
        [[ "$args" == *'--dry-run'* && "$args" == *'--dns-cloudflare-propagation-seconds 60'* && "$args" == *'--no-directory-hooks'* ]]
        [[ "$args" == *'https://acme-staging-v02.api.letsencrypt.org/directory'* && "$args" == *'--config /dev/null'* ]]
        [[ "$credentials" == "$SELF_DIR/work/token-backup."*/new.ini && "$conf" == "$SELF_DIR/work/token-backup."*/probe/acme ]]
        [[ -z "$(find "$conf" -mindepth 1 -print)" && "$(< "$SELF_DIR/cloudflare.ini")" == *"$OLD_TOKEN"* ]]
        [[ "$(stat -c %a "$credentials")" == 600 && "$(< "$credentials")" == *"$NEW_TOKEN"* ]]
        touch "$conf/fresh-account-proof"
        printf '%s %s\n' "$OLD_TOKEN" "$NEW_TOKEN" > "$logs/provider.log"
        printf 'provider diagnostic %s %s\n' "$OLD_TOKEN" "$NEW_TOKEN"
        if [[ "$STAGE" == signal-probe ]]; then kill -TERM "$BASHPID"; return 1; fi
        [[ "$STAGE" != probe ]]
    elif [[ "$1" == renew ]]; then
        [[ "$args" == *'--dry-run'* && "$(< "$SELF_DIR/cloudflare.ini")" == *"$NEW_TOKEN"* ]]
        printf 'renew diagnostic %s %s\n' "$OLD_TOKEN" "$NEW_TOKEN"
        if [[ "$STAGE" == binding-late ]]; then printf '\n# changed during renewal\n' >> "$SELF_DIR/acme/renewal/$SNI.conf"; fi
        if [[ "$STAGE" == signal-renew ]]; then kill -TERM "$BASHPID"; return 1; fi
        [[ "$STAGE" != renewal && "$STAGE" != rollback ]]
    else return 99; fi
}
cp() {
    assert_token_environment
    [[ "$STAGE" != backup || "${@: -1}" != "$SELF_DIR/work/token-backup."*/old.ini ]] || return 1
    command cp "$@"
}
mv() {
    local destination="${@: -1}"
    if [[ "$STAGE" == publish && "$destination" == "$SELF_DIR/cloudflare.ini" && ! -e "$CASE_DIR/injected" ]]; then touch "$CASE_DIR/injected"; return 1; fi
    if [[ "$STAGE" == record && "$destination" == "$SELF_DIR/files.sha256" && ! -e "$CASE_DIR/injected" ]]; then touch "$CASE_DIR/injected"; return 1; fi
    if [[ "$STAGE" == renew-record && "$destination" == "$SELF_DIR/renew-test.json" && ! -e "$CASE_DIR/injected" ]]; then touch "$CASE_DIR/injected"; return 1; fi
    [[ "$STAGE" != rollback || "${@: -2:1}" != "$SELF_DIR/work/token-backup."*/restore.ini ]] || return 1
    command mv "$@"
}
rm() {
    if [[ "$STAGE" == cleanup && "$*" == *"$SELF_DIR/work/token-backup."* ]]; then return 1; fi
    command rm "$@"
}
fixture() {
    STAGE=success; CASE_DIR="$TEST_DIR/$1"; mkdir -p "$CASE_DIR/bin"
    CONFIG_DIR="$CASE_DIR/xray"; CONFIG="$CONFIG_DIR/config.json"; MARKER="$CONFIG_DIR/.vless-reality-owned"; LINK_FILE="$CASE_DIR/link"
    SELF_DIR="$CASE_DIR/self"; SELF_WEB="$CASE_DIR/web"; SELF_SITE="$CASE_DIR/site.conf"; SELF_POLICY="$CASE_DIR/policy"
    SELF_RENEW_SERVICE="$CASE_DIR/cert.service"; SELF_RENEW_TIMER="$CASE_DIR/cert.timer"
    mkdir -p "$CONFIG_DIR" "$SELF_WEB" "$SELF_DIR/"{work,logs,acme/renewal,acme/live/node.example.com,acme/renewal-hooks/deploy}
    chmod 700 "$SELF_DIR"; chmod 755 "$SELF_WEB"
    printf 'vless-reality-self-v1\n' > "$SELF_DIR/.owned"; : > "$SELF_DIR/files.sha256"
    : > "$SELF_DIR/cli.ini"; self_track "$SELF_DIR/cli.ini"
    printf '{"domain":"node.example.com","method":"cloudflare","email":"admin@example.com","nginx_active":false,"nginx_enabled":false}\n' > "$SELF_DIR/state.json"
    printf 'dns_cloudflare_api_token = %s\n' "$OLD_TOKEN" > "$SELF_DIR/cloudflare.ini"; chmod 600 "$SELF_DIR/cloudflare.ini"
    printf 'certificate\n' > "$SELF_DIR/acme/live/node.example.com/cert.pem"
    printf 'owned site\n' > "$SELF_SITE"; printf 'owned website\n' > "$SELF_WEB/index.html"
    printf 'timer\n' > "$SELF_RENEW_TIMER"; printf 'service\n' > "$SELF_RENEW_SERVICE"
    printf '[renewalparams]\nauthenticator = dns-cloudflare\ndns_cloudflare_credentials = %s\nserver = https://acme-v02.api.letsencrypt.org/directory\n' "$SELF_DIR/cloudflare.ini" > "$SELF_DIR/acme/renewal/node.example.com.conf"
    printf '{"domain":"node.example.com","result":"passed","time":"previous"}\n' > "$SELF_DIR/renew-test.json"
    printf 'previous log\n' > "$SELF_DIR/logs/renew-test.log"
    printf '{"result":"failed","time":"history"}\n' > "$SELF_DIR/renew-status.json"
    cat > "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx" <<'HOOK'
#!/bin/sh
printf 'reload nginx\n' >> "$VLESS_TOKEN_TEST_CASE/services.calls"
[ "$VLESS_TOKEN_TEST_STAGE" != hook ]
HOOK
    chmod 700 "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx"
    for path in "$SELF_DIR/state.json" "$SELF_DIR/cloudflare.ini" "$SELF_SITE" "$SELF_WEB/index.html" "$SELF_RENEW_TIMER" "$SELF_RENEW_SERVICE" "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx"; do self_track "$path"; done
    PORT=443; SNI=node.example.com; NODE_NAME=Existing; SERVER_IP=203.0.113.1; PUBLIC_KEY=pub; SHORT_ID=0123456789abcdef
    NODE_MODE=self; ADDR_MODE=ip; ADDR_DOMAIN=''; TFO_ENABLED=1; CLIENT_ENCRYPTION=mlkem768x25519plus.native.0rtt.test
    printf 'immutable xray configuration\n' > "$CONFIG"; write_marker; printf 'immutable client link\n' > "$LINK_FILE"
    export VLESS_CF_CREDENTIALS="$CASE_DIR/new.ini" VLESS_TOKEN_TEST_CASE="$CASE_DIR"
    printf 'dns_cloudflare_api_token = %s\n' "$NEW_TOKEN" > "$VLESS_CF_CREDENTIALS"; chmod 600 "$VLESS_CF_CREDENTIALS"
}
immutable() {
    sha256sum "$CONFIG" "$MARKER" "$LINK_FILE" "$SELF_SITE" "$SELF_WEB/index.html" "$SELF_DIR/state.json" \
        "$SELF_RENEW_SERVICE" "$SELF_RENEW_TIMER" "$SELF_DIR/acme/live/node.example.com/cert.pem" "$SELF_DIR/renew-status.json" "$SELF_DIR/acme/renewal/node.example.com.conf"
}
for stage in success absent-record same format source-mode source-owner source-link missing-input extra-arg trace modified missing-old http external binding binding-late backup record publish probe renewal renew-record hook baseline tls-late timer timer-late signal-probe signal-renew rollback scrub cleanup; do
    fixture "$stage"
    case "$stage" in
        absent-record) rm "$SELF_DIR/renew-test.json" "$SELF_DIR/logs/renew-test.log" ;;
        same) command cp "$SELF_DIR/cloudflare.ini" "$VLESS_CF_CREDENTIALS" ;;
        format) printf 'dns_cloudflare_api_token = invalid\n' > "$VLESS_CF_CREDENTIALS" ;;
        source-mode) chmod 644 "$VLESS_CF_CREDENTIALS" ;;
        source-link) command mv "$VLESS_CF_CREDENTIALS" "$CASE_DIR/source.ini"; ln -s "$CASE_DIR/source.ini" "$VLESS_CF_CREDENTIALS" ;;
        modified) printf '# user edit\n' >> "$SELF_DIR/cloudflare.ini" ;;
        missing-old) rm "$SELF_DIR/cloudflare.ini" ;;
        http) sed -i s/cloudflare/http/ "$SELF_DIR/state.json"; self_track "$SELF_DIR/state.json" ;;
        external) NODE_MODE=external; write_marker ;;
        binding) sed -i 's|^dns_cloudflare_credentials = .*|dns_cloudflare_credentials = /some/other.ini|' "$SELF_DIR/acme/renewal/$SNI.conf" ;;
    esac
    before="$(immutable)"; receipts="$(sha256sum "$SELF_DIR/files.sha256")"
    source_before="$(sha256sum "$VLESS_CF_CREDENTIALS")"
    old_credential=''; [[ ! -f "$SELF_DIR/cloudflare.ini" ]] || old_credential="$(sha256sum "$SELF_DIR/cloudflare.ini")"
    test_record=''; test_log=''
    [[ ! -f "$SELF_DIR/renew-test.json" ]] || test_record="$(sha256sum "$SELF_DIR/renew-test.json")"
    [[ ! -f "$SELF_DIR/logs/renew-test.log" ]] || test_log="$(sha256sum "$SELF_DIR/logs/renew-test.log")"
    STAGE="$stage"; export VLESS_TOKEN_TEST_STAGE="$STAGE"; rc=0
    case "$stage" in
        missing-input) (unset VLESS_CF_CREDENTIALS; self_cf_token_rotate </dev/null) > "$CASE_DIR/result.log" 2>&1 || rc=$? ;;
        extra-arg) (cert_command token unexpected) > "$CASE_DIR/result.log" 2>&1 || rc=$? ;;
        trace) (set -x; self_cf_token_rotate) > "$CASE_DIR/result.log" 2>&1 || rc=$? ;;
        *) (self_cf_token_rotate </dev/null) > "$CASE_DIR/result.log" 2>&1 || rc=$? ;;
    esac
    if [[ "$stage" == success || "$stage" == absent-record ]]; then
        [[ "$rc" == 0 && "$(< "$SELF_DIR/cloudflare.ini")" == *"$NEW_TOKEN"* && "$(stat -c %a "$SELF_DIR/cloudflare.ini")" == 600 ]]
        self_file_owned "$SELF_DIR/cloudflare.ini"; self_cleanup_preflight
        jq -e '.result=="passed"' "$SELF_DIR/renew-test.json" >/dev/null
        [[ "$(< "$CASE_DIR/services.calls")" == 'reload nginx' ]]
        [[ -z "$(find "$SELF_DIR/work" -mindepth 1 -print)" && -z "$(find "$SELF_DIR/logs" -name 'token-*')" ]]
    elif [[ "$stage" == same ]]; then
        [[ "$rc" != 0 && "$(sha256sum "$SELF_DIR/files.sha256")" == "$receipts" && ! -e "$CASE_DIR/certbot.calls" ]]
    elif [[ "$stage" == rollback || "$stage" == scrub || "$stage" == cleanup ]]; then
        [[ "$rc" != 0 && "$(< "$CASE_DIR/result.log")" != *'Cloudflare Token 已更换；'* ]]
        if [[ "$stage" == rollback ]]; then [[ "$(< "$CASE_DIR/result.log")" == *'回滚失败，保留备份：'* ]]; fi
        if [[ "$stage" == scrub ]]; then [[ "$(< "$CASE_DIR/result.log")" == *'日志脱敏失败，保留 root 专用备份：'* ]]; fi
        if [[ "$stage" == cleanup ]]; then [[ "$(< "$SELF_DIR/cloudflare.ini")" == *"$NEW_TOKEN"* ]]; fi
        backup="$(find "$SELF_DIR/work" -type d -name 'token-backup.*')"
        [[ -f "$backup/old.ini" && "$(stat -c %a "$backup")" == 700 && "$(stat -c %a "$backup/old.ini")" == 600 ]]
        STAGE=success; self_scrub_logs "$backup/old.ini" "$backup/new.ini"
        STAGE=success; command cp -a "$backup/old.ini" "$SELF_DIR/cloudflare.ini"; command cp -a "$backup/files.sha256" "$SELF_DIR/files.sha256"
        command cp -a "$backup/renewal.conf" "$SELF_DIR/acme/renewal/$SNI.conf"; rm -rf -- "$backup"
    else
        [[ "$rc" != 0 && "$(sha256sum "$SELF_DIR/files.sha256")" == "$receipts" ]]
        if [[ -n "$old_credential" ]]; then [[ "$(sha256sum "$SELF_DIR/cloudflare.ini")" == "$old_credential" ]]; else [[ ! -e "$SELF_DIR/cloudflare.ini" ]]; fi
        if [[ -n "$test_record" ]]; then [[ "$(sha256sum "$SELF_DIR/renew-test.json")" == "$test_record" ]]; else [[ ! -e "$SELF_DIR/renew-test.json" ]]; fi
        if [[ -n "$test_log" ]]; then [[ "$(sha256sum "$SELF_DIR/logs/renew-test.log")" == "$test_log" ]]; else [[ ! -e "$SELF_DIR/logs/renew-test.log" ]]; fi
    fi
    [[ "$(immutable)" == "$before" ]]
    [[ "$(sha256sum "$VLESS_CF_CREDENTIALS")" == "$source_before" ]]
    [[ -z "$(find "$SELF_DIR/work" -name 'token-backup.*')" && -z "$(find "$SELF_DIR" -name '.receipt.*' -o -name '.renew.*')" ]]
    if rg -q -F -e "$OLD_TOKEN" -e "$NEW_TOKEN" "$CASE_DIR/result.log" "$SELF_DIR/logs"; then echo 'Token 泄漏到输出或日志'; exit 1; fi
    [[ ! -e "$CASE_DIR/unexpected-service.calls" ]]
done
# 两个 Token 有前缀关系时也必须完整脱敏。
fixture prefix
printf 'dns_cloudflare_api_token = %s_extra\n' "$OLD_TOKEN" > "$CASE_DIR/long.ini"
printf '%s_extra %s\n' "$OLD_TOKEN" "$OLD_TOKEN" > "$SELF_DIR/logs/prefix.log"
self_scrub_logs "$CASE_DIR/long.ini"
[[ "$(< "$SELF_DIR/logs/prefix.log")" == '[REDACTED] [REDACTED]' ]]
# 与自动续期共用 operation.lock，不能在定时任务未完成时读写 Token。
fixture concurrent; export VLESS_TOKEN_TEST_STAGE=success
exec 8> "$SELF_DIR/operation.lock"; flock -x 8
(exec 8>&-; self_cf_token_rotate > "$CASE_DIR/result.log" 2>&1) & change_pid=$!
sleep 0.1; kill -0 "$change_pid"; [[ ! -e "$CASE_DIR/certbot.calls" ]]
exec 8>&-; wait "$change_pid"
self_file_owned "$SELF_DIR/cloudflare.ini"
printf 'Token 输入/权限、全新验证、归属/续期/信号回滚、日志脱敏、清理与自动续期互斥通过\n'
