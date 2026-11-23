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
stat() {
    if [[ "$*" == "-c %u:%a $LINK_FILE" ]]; then printf '0:%s\n' "$(command stat -c %a "$LINK_FILE")";
    else command stat "$@"; fi
}
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
    [[ "$2:$3" == '127.0.0.1:24443' ]] || return 2
    printf '%s\n' "$(config_transport)" >> "$TEST_DIR/probes"
    if [[ "$FAIL_STAGE" == signal ]]; then kill -TERM "$BASHPID"; fi
    [[ "$FAIL_STAGE" != proxy ]]
}
mv() {
    if [[ "$FAIL_STAGE" == link && "${@: -1}" == "$LINK_FILE" ]]; then return 1; fi
    command mv "$@"
}
for FAIL_STAGE in config restart listen proxy link signal; do
    rc=0; transport_apply xhttp > "$TEST_DIR/result" 2>&1 || rc=$?
    [[ "$rc" != 0 && "$(sha256sum "$CONFIG" "$MARKER" "$LINK_FILE")" == "$hash_before" ]]
    [[ -z "$(find "$CONFIG_DIR" -mindepth 1 -name '.change-backup.*' -o -name '.config.json.*')" ]]
    if [[ "$FAIL_STAGE" == config ]]; then [[ ! -f "$TEST_DIR/restarts" ]];
    else [[ "$(tail -1 "$TEST_DIR/restarts")" == tcp ]]; fi
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
transport_apply tcp >/dev/null
[[ "$(jq -S . "$CONFIG" | sha256sum)" == "$snapshot" && "$(< "$LINK_FILE")" == "$link_before" ]]

# 关闭状态只检查配置并保存链接，UUID 管理仍能读取 XHTTP 用户。
ACTIVE=0
restarts="$(wc -l < "$TEST_DIR/restarts")"; probes="$(wc -l < "$TEST_DIR/probes")"
transport_apply xhttp > "$TEST_DIR/result"
[[ "$(< "$TEST_DIR/result")" == *'实际连接需在启动后检查'* ]]
(change_uuid >/dev/null)
[[ "$(config_uuid)" == 11111111-1111-4111-8111-111111111111 && "$(< "$LINK_FILE")" == *'&type=xhttp&'* ]]
[[ "$(wc -l < "$TEST_DIR/restarts")" == "$restarts" && "$(wc -l < "$TEST_DIR/probes")" == "$probes" ]]
printf '旧记录兼容、双向切换、UUID 管理、停止状态以及启动/代理/链接/信号故障回滚通过\n'
