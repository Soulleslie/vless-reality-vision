#!/usr/bin/env bash
# 双向交易回滚、旧安装兼容与现有管理动作。真实握手由隔离 Xray/Nginx 测试覆盖。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
CONFIG_DIR="$TEST_DIR/xray"; CONFIG="$CONFIG_DIR/config.json"; MARKER="$CONFIG_DIR/.vless-reality-owned"
SELF_DIR="$TEST_DIR/self"; LINK_FILE="$TEST_DIR/link.txt"
mkdir -p "$CONFIG_DIR"
need_root() { :; }
chown() { :; }
XRAY_BIN="$TEST_DIR/xray-bin"
cat > "$XRAY_BIN" <<'XRAY'
#!/bin/sh
[ "$1" = uuid ] || exit 1
printf '11111111-1111-4111-8111-111111111111\n'
XRAY
chmod 700 "$XRAY_BIN"
PORT=24443; SNI=www.example.com; SERVER_IP=203.0.113.1; NODE_NAME=Legacy
SHORT_ID=0123456789abcdef; PUBLIC_KEY=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB; TFO_ENABLED=1
uuid=22222222-2222-4222-8222-222222222222
write_config "$uuid" AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
write_marker; sed -i '7,$d' "$MARKER"  # Release 1.x marker.
show_node >/dev/null
hash_before="$(sha256sum "$CONFIG" "$MARKER" "$LINK_FILE")"
snapshot="$(jq -S . "$CONFIG" | sha256sum)"
link_before="$(< "$LINK_FILE")"
FAIL_STAGE=none; ACTIVE=1
config_ok() { [[ "$FAIL_STAGE" != config || "$#" == 0 ]]; }
systemctl() {
    case "$1" in
        is-active) [[ "$ACTIVE" == 1 ]] ;;
        restart)
            printf '%s\n' "$(config_transport)" >> "$TEST_DIR/restarts"
            [[ "$FAIL_STAGE" != restart ]] || [[ "$(config_transport)" != xhttp ]] ;;
        *) return 1 ;;
    esac
}
wait_service() { [[ "$FAIL_STAGE" != listen || "$(config_transport)" != xhttp ]]; }
self_client_probe() {
    [[ "$2:$3" == '127.0.0.1:24443' && "$4" == switch ]] || return 2
    printf '%s\n' "$(config_transport)" >> "$TEST_DIR/probes"
    if [[ "$FAIL_STAGE" == signal ]]; then kill -TERM "$BASHPID"; fi
    if [[ "$FAIL_STAGE" == kill-after-config ]]; then kill -KILL "$BASHPID"; fi
    if [[ "$FAIL_STAGE" == targets ]]; then return 3; fi
    [[ "$FAIL_STAGE" != proxy ]]
}
sync() {
    if [[ "$FAIL_STAGE" == kill-after-link && "$*" == "-- $CONFIG $MARKER" ]]; then kill -KILL "$BASHPID"; fi
    command sync "$@"
}
mv() {
    if [[ "$FAIL_STAGE" == link && "${@: -1}" == "$LINK_FILE" ]]; then return 1; fi
    command mv "$@"
}
for FAIL_STAGE in config restart listen proxy targets link signal; do
    rc=0; transport_apply xhttp > "$TEST_DIR/result" 2>&1 || rc=$?
    [[ "$rc" != 0 && "$(sha256sum "$CONFIG" "$MARKER" "$LINK_FILE")" == "$hash_before" ]]
    [[ -z "$(find "$CONFIG_DIR" -mindepth 1 -name '.change-backup.*' -o -name '.config.json.*')" ]]
    if [[ "$FAIL_STAGE" == config ]]; then [[ ! -f "$TEST_DIR/restarts" ]];
    else [[ "$(tail -1 "$TEST_DIR/restarts")" == tcp ]]; fi
    if [[ "$FAIL_STAGE" == targets ]]; then [[ "$(< "$TEST_DIR/result")" == *'代理与本机直连都无法访问测试站点'* ]]; fi
done
for FAIL_STAGE in kill-after-config kill-after-link; do
    rc=0; transport_apply xhttp > "$TEST_DIR/result" 2>&1 || rc=$?
    [[ "$rc" == 137 && "$(config_transport)" == xhttp ]]
    transport_pending
    if [[ "$FAIL_STAGE" == kill-after-config ]]; then [[ "$(< "$LINK_FILE")" == "$link_before" ]];
    else [[ "$(< "$LINK_FILE")" == *'&type=xhttp&'* ]]; fi
    rc=0; transport_command status >/dev/null 2>&1 || rc=$?; [[ "$rc" == 3 ]]
    rc=0; show_node >/dev/null 2>&1 || rc=$?; [[ "$rc" == 3 ]]
    rc=0; (change_uuid >/dev/null 2>&1) || rc=$?; [[ "$rc" == 3 ]]
    # 不覆盖中断后管理员手工写入的配置。
    cp "$CONFIG" "$TEST_DIR/interrupted.json"
    printf '\n' >> "$CONFIG"
    if transport_recover >/dev/null 2>&1; then echo '不应覆盖手改配置'; exit 1; fi
    transport_pending
    cp "$TEST_DIR/interrupted.json" "$CONFIG"
    FAIL_STAGE=none
    transport_recover >/dev/null
    [[ "$(sha256sum "$CONFIG" "$MARKER" "$LINK_FILE")" == "$hash_before" ]]
    if transport_pending; then echo '恢复后不应还有挂起记录'; exit 1; fi
done
FAIL_STAGE=none
transport_apply xhttp > "$TEST_DIR/result"
path="$(config_xhttp_path)"
[[ "$(config_uuid)" == "$uuid" && "$(tail -1 "$TEST_DIR/probes")" == xhttp ]]
[[ "$(< "$LINK_FILE")" == "vless://$uuid@203.0.113.1:24443?"*"&type=xhttp&path=%2F${path#/}&mode=auto&tfo=1#"* ]]
[[ "$(< "$LINK_FILE")" != *'&flow='* && "$(stat -c %a "$LINK_FILE")" == 600 ]]
[[ "$(transport_command status)" == *"XHTTP + REALITY"*"$path"* ]]
restarts="$(wc -l < "$TEST_DIR/restarts")"
transport_apply xhttp >/dev/null
[[ "$(config_xhttp_path)" == "$path" && "$(wc -l < "$TEST_DIR/restarts")" == "$restarts" ]]
first_xhttp_link="$(< "$LINK_FILE")"
# v2.5.0 已运行 XHTTP 但记录里尚无 Path，升级后应接管正在用的 Path。
sed -i '11,$d' "$MARKER"
show_node >/dev/null; [[ "$(< "$LINK_FILE")" == "$first_xhttp_link" ]]
transport_apply tcp >/dev/null
[[ "$(jq -S . "$CONFIG" | sha256sum)" == "$snapshot" && "$(< "$LINK_FILE")" == "$link_before" ]]
[[ "$(sed -n '11p' "$MARKER")" == "$path" ]]

# 关闭状态只检查配置并保存链接，UUID 管理仍能读取 XHTTP 用户。
ACTIVE=0
restarts="$(wc -l < "$TEST_DIR/restarts")"; probes="$(wc -l < "$TEST_DIR/probes")"
transport_apply xhttp > "$TEST_DIR/result"
[[ "$(< "$TEST_DIR/result")" == *'实际连接需在启动后检查'* ]]
[[ "$(config_xhttp_path)" == "$path" && "$(< "$LINK_FILE")" == "$first_xhttp_link" ]]
(change_uuid >/dev/null)
[[ "$(config_uuid)" == 11111111-1111-4111-8111-111111111111 && "$(< "$LINK_FILE")" == *'&type=xhttp&'* ]]
[[ "$(wc -l < "$TEST_DIR/restarts")" == "$restarts" && "$(wc -l < "$TEST_DIR/probes")" == "$probes" ]]

curl() {
    printf '%s\n' "$*" >> "$TEST_DIR/curls"
    if [[ "$*" == *'--proxy '* ]]; then
        if [[ "$PROBE_CASE" == first || ( "$PROBE_CASE" == backup && "$*" == *www.cloudflare.com* ) ]]; then return 0; fi
        return 28
    else [[ "$PROBE_CASE" == direct ]]; fi
}
for PROBE_CASE in first backup direct unreachable; do
    : > "$TEST_DIR/curls"
    rc=0; transport_probe_https 23456 2> "$TEST_DIR/curl-diagnostics" || rc=$?
    count="$(wc -l < "$TEST_DIR/curls")"
    case "$PROBE_CASE" in
        first) [[ "$rc/$count" == 0/1 ]] ;;
        backup) [[ "$rc/$count" == 0/2 ]] ;;
        direct) [[ "$rc/$count" == 1/3 ]] ;;
        unreachable) [[ "$rc/$count" == 3/4 ]] ;;
    esac
    if grep -Eqv -- '--max-time (2|8) ' "$TEST_DIR/curls"; then echo '探测请求缺少时间上限'; exit 1; fi
    if grep -F -- '--proxy ' "$TEST_DIR/curls" | grep -Fqv -- '--connect-timeout 8 --max-time 8 '; then
        echo '代理探测的 TLS 握手必须能使用完整请求预算'; exit 1
    fi
    if [[ "$PROBE_CASE" == first ]]; then [[ ! -s "$TEST_DIR/curl-diagnostics" ]]
    else [[ "$(< "$TEST_DIR/curl-diagnostics")" == *www.debian.org*'curl 退出码 28'* ]]; fi
done
printf '旧记录兼容、Path 复用、故障分级、停止状态、正常回滚与两种 SIGKILL 恢复通过\n'
