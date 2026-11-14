#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"; trap 'rm -rf -- "$TEST_DIR"' EXIT
CONFIG_DIR="$TEST_DIR/config"; CONFIG="$CONFIG_DIR/config.json"; MARKER="$CONFIG_DIR/.vless-reality-owned"
LINK_FILE="$TEST_DIR/link.txt"; SELF_DIR="$TEST_DIR/no-self-state"
mkdir -p "$CONFIG_DIR"
need_root() { :; }; chown() { :; }
# 老普通节点没有 dig 时只补 dnsutils；安装失败必须在提交地址前退出。
(
    command() { if [[ "$*" == '-v dig' ]]; then return 1; fi; builtin command "$@"; }
    need_command() { :; }
    apt-get() { printf '%s\n' "$*" >> "$TEST_DIR/packages"; }
    ensure_dns_tool >/dev/null
    [[ "$(< "$TEST_DIR/packages")" == $'update\ninstall -y dnsutils' ]]
    apt-get() { return 1; }
    if (ensure_dns_tool >/dev/null 2>&1); then exit 1; fi
)
ensure_dns_tool() { :; } # 以下 DNS 回复由替身提供，无需安装系统工具。
systemctl() { printf '%s\n' "$*" >> "$TEST_DIR/service-calls"; return 1; }
PUBLIC=203.0.113.1; DNS_CASE=valid
public_ipv4() { printf '%s' "$PUBLIC"; }
self_dns_query() {
    printf ';; status: NOERROR\n'
    case "$3" in
        A)
            if [[ "$DNS_CASE" == valid ]]; then printf '%s 60 IN A %s\n' "$2" "$PUBLIC";
            else printf '%s 60 IN A 203.0.113.99\n' "$2"; fi ;;
    esac
}
fixture() {
    NODE_MODE="$1"; ADDR_MODE=auto; ADDR_DOMAIN=''; SERVER_IP=203.0.113.1; PUBLIC=203.0.113.1; DNS_CASE=valid
    PORT=443; SNI=camouflage.example.net; NODE_NAME=Address-Test
    [[ "$NODE_MODE" != self ]] || SNI=self.example.com
    PUBLIC_KEY=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB; SHORT_ID=0123456789abcdef
    TFO_ENABLED=1; CLIENT_ENCRYPTION=mlkem768x25519plus.native.0rtt.testpub; VLESS_DECRYPTION=mlkem768x25519plus.native.600s.testkey
    write_config 00000000-0000-4000-8000-000000000000 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    write_marker; show_node >/dev/null
    config_before="$(sha256sum "$CONFIG")"
    identity_before="$(sed -n '1,3p;5,8p' "$MARKER")"
}
assert_identity() {
    [[ "$(sha256sum "$CONFIG")" == "$config_before" ]]
    [[ "$(sed -n '1,3p;5,8p' "$MARKER")" == "$identity_before" ]]
    [[ "$(< "$LINK_FILE")" == *'&sni='* && "$(< "$LINK_FILE")" == *'&flow=xtls-rprx-vision&'* ]]
    [[ "$(< "$LINK_FILE")" == *'encryption=mlkem768x25519plus.native.0rtt.testpub&'* && "$(< "$LINK_FILE")" == *'&tfo=1#'* ]]
    [[ "$(stat -c %a "$LINK_FILE")" == 600 && -z "$(find "$CONFIG_DIR" -name '.change-backup.*' -print)" ]]
    [[ ! -e "$TEST_DIR/service-calls" ]]
}
for bad in 256.0.0.1 01.2.3.4 1.2.3 1.2.3.4.5; do if valid_ipv4 "$bad"; then exit 1; fi; done
fixture external
[[ "$(client_address)" == "$SERVER_IP" ]]
address_node domain node.example.com >/dev/null
load_metadata
[[ "$ADDR_MODE" == domain && "$(client_address)" == node.example.com ]]
[[ "$(< "$LINK_FILE")" == *'@node.example.com:443?'* && "$(< "$LINK_FILE")" == *'&sni=camouflage.example.net&'* ]]
assert_identity
PUBLIC=203.0.113.2
address_node ip >/dev/null; load_metadata
[[ "$(client_address)" == "$PUBLIC" && "$ADDR_DOMAIN" == node.example.com ]]
assert_identity
address_node domain >/dev/null; load_metadata
[[ "$(client_address)" == node.example.com ]]
PUBLIC=203.0.113.3
refresh_ip >/dev/null; load_metadata
[[ "$(client_address)" == node.example.com && "$SERVER_IP" == "$PUBLIC" ]]
assert_identity
DNS_CASE=wrong
old="$(sha256sum "$MARKER" "$LINK_FILE")"
if (address_node domain other.example.com >/dev/null 2>&1); then exit 1; fi
[[ "$(sha256sum "$MARKER" "$LINK_FILE")" == "$old" ]]
DNS_CASE=valid
for bad in https://node.example.com node.example.com:443 'bad name'; do
    if (address_node domain "$bad" >/dev/null 2>&1); then exit 1; fi
done
PUBLIC=999.0.0.1
if (address_node ip >/dev/null 2>&1); then exit 1; fi
[[ "$(sha256sum "$MARKER" "$LINK_FILE")" == "$old" ]]

fixture self
[[ "$(client_address)" == self.example.com ]]
address_node ip >/dev/null; load_metadata
[[ "$ADDR_MODE" == ip && "$(< "$LINK_FILE")" == *'@203.0.113.1:443?'* && "$(< "$LINK_FILE")" == *'&sni=self.example.com&'* ]]
security_link_check; assert_identity
DNS_CASE=wrong; PUBLIC=203.0.113.2
address_node ip >/dev/null; load_metadata
[[ "$SERVER_IP" == "$PUBLIC" ]]
old="$(sha256sum "$MARKER" "$LINK_FILE")"
if (address_node domain >/dev/null 2>&1); then exit 1; fi
[[ "$(sha256sum "$MARKER" "$LINK_FILE")" == "$old" ]]
DNS_CASE=valid
address_node domain >/dev/null; load_metadata
[[ "$(client_address)" == self.example.com ]]
if (address_node domain another.example.com >/dev/null 2>&1); then exit 1; fi
PUBLIC=203.0.113.3
refresh_ip >/dev/null; load_metadata
[[ "$SERVER_IP" == "$PUBLIC" && "$(client_address)" == self.example.com ]]
security_link_check; assert_identity

# 保存失败恢复两个文件；链接原先不存在时也恢复不存在，服务配置不受影响。
old="$(sha256sum "$MARKER" "$LINK_FILE")"
chown() { return 1; }
if (address_node ip >/dev/null 2>&1); then exit 1; fi
chown() { :; }
[[ "$(sha256sum "$MARKER" "$LINK_FILE")" == "$old" ]]
mv() {
    if [[ "${@: -1}" == "$LINK_FILE" && "${@: -2:1}" == "$LINK_FILE".?????? ]]; then return 1; fi
    command mv "$@"
}
if (address_node ip >/dev/null 2>&1); then exit 1; fi
[[ "$(sha256sum "$MARKER" "$LINK_FILE")" == "$old" ]]
rm "$LINK_FILE"
if (address_node ip >/dev/null 2>&1); then exit 1; fi
[[ ! -e "$LINK_FILE" ]]
unset -f mv
show_node >/dev/null; assert_identity

# 连恢复也失败时保留唯一备份并报错，不能假称恢复成功或删除旧链接。
mv() {
    if [[ "${@: -1}" == "$LINK_FILE" && "${@: -2:1}" == "$LINK_FILE".?????? ]]; then return 1; fi
    if [[ "${@: -1}" == "$MARKER" && "${@: -2:1}" == */.change-backup.*/.vless-reality-owned ]]; then return 1; fi
    command mv "$@"
}
if (address_node ip > "$TEST_DIR/rollback.log" 2>&1); then exit 1; fi
[[ "$(< "$TEST_DIR/rollback.log")" == *'回滚失败，保留备份'* ]]
backup="$(find "$CONFIG_DIR" -maxdepth 1 -type d -name '.change-backup.*')"
[[ -f "$backup/.vless-reality-owned" && -f "$backup/link.txt" ]]
unset -f mv
cp -a "$backup/.vless-reality-owned" "$MARKER"; cp -a "$backup/link.txt" "$LINK_FILE"; rm -rf "$backup"
[[ "$(sha256sum "$MARKER" "$LINK_FILE")" == "$old" ]]
load_metadata; assert_identity

# 地址更换等待其他管理操作完成后重读元数据，不能覆盖并发写入的新记录。
fixture external
(
    exec 9< "$CONFIG_DIR"; flock -x 9
    touch "$TEST_DIR/locked"
    sleep 0.5
    NODE_NAME=Concurrent-Update; write_marker
) & holder=$!
for attempt in {1..50}; do [[ ! -f "$TEST_DIR/locked" ]] || break; sleep 0.02; done
[[ -f "$TEST_DIR/locked" ]]
(show_node >/dev/null; touch "$TEST_DIR/read-finished") & reader=$!
sleep 0.05
[[ ! -e "$TEST_DIR/read-finished" ]]
address_node domain node.example.com >/dev/null
wait "$holder"; wait "$reader"
load_metadata
[[ "$NODE_NAME" == Concurrent-Update && "$(client_address)" == node.example.com ]]
[[ "$(< "$LINK_FILE")" == *'@node.example.com:443?'* ]]
[[ "$(sha256sum "$CONFIG")" == "$config_before" && ! -e "$TEST_DIR/service-calls" ]]

# 等待锁期间节点被卸载/重新建立时，旧操作不能应用到新目录。
fixture external
old_link="$(sha256sum "$LINK_FILE")"
(
    exec 9< "$CONFIG_DIR"; flock -x 9
    touch "$TEST_DIR/replace-locked"; sleep 0.4
    mv "$CONFIG_DIR" "$TEST_DIR/previous-config"; mkdir "$CONFIG_DIR"
    cp -a "$TEST_DIR/previous-config/.vless-reality-owned" "$TEST_DIR/previous-config/config.json" "$CONFIG_DIR/"
    NODE_NAME=New-Node; write_marker
) & holder=$!
for attempt in {1..50}; do [[ ! -f "$TEST_DIR/replace-locked" ]] || break; sleep 0.02; done
[[ -f "$TEST_DIR/replace-locked" ]]
if (address_node ip >/dev/null 2>&1); then exit 1; fi
wait "$holder"; load_metadata
[[ "$NODE_NAME" == New-Node && "$ADDR_MODE" == auto && "$(sha256sum "$LINK_FILE")" == "$old_link" ]]

# 常规管理重新生成链接时也必须保留已选地址，而不是退回各模式的默认值。
config_ok() { return 0; }
address_xray() { [[ "$1" == uuid ]] && printf '11111111-1111-4111-8111-111111111111\n'; }
XRAY_BIN=address_xray
generate_reality_keys() { printf '%s\n' AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC; }
generate_vless_encryption_pair() { printf 'mlkem768x25519plus.%s.600s.newkey\nmlkem768x25519plus.%s.0rtt.newpub\n' "$1" "$1"; }
for node_mode in external self; do
    fixture "$node_mode"
    if [[ "$node_mode" == external ]]; then address_node domain node.example.com >/dev/null;
    else address_node ip >/dev/null; fi
    load_metadata; chosen_address="$(client_address)"
    (change_uuid >/dev/null); load_metadata
    [[ "$(client_address)" == "$chosen_address" && "$(< "$LINK_FILE")" == *"@$chosen_address:443?"* ]]
    (rotate_keys >/dev/null); load_metadata
    [[ "$(client_address)" == "$chosen_address" && "$PUBLIC_KEY" == CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC ]]
    (vlessenc_apply on random >/dev/null); load_metadata
    [[ "$(client_address)" == "$chosen_address" && "$(< "$LINK_FILE")" == *"@$chosen_address:443?encryption=mlkem768x25519plus.random.0rtt.newpub&"* ]]
done
printf '两种安装模式的 IP/域名切换、参数保留、DNS/IPv4 校验、回滚与并发保护通过\n'
