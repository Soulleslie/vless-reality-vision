#!/usr/bin/env bash
# 用法：bash tests/reality_handshake.bash /path/to/xray
set -Eeuo pipefail

XRAY_TEST_BIN="${1:?请传入 Xray 二进制路径}"
TEST_DIR="$(mktemp -d)"
server_pid=''
client_pid=''
target_pid=''
cleanup() {
    [[ -z "$client_pid" ]] || kill "$client_pid" 2>/dev/null || true
    [[ -z "$server_pid" ]] || kill "$server_pid" 2>/dev/null || true
    [[ -z "$target_pid" ]] || kill "$target_pid" 2>/dev/null || true
    rm -rf -- "$TEST_DIR"
}
trap cleanup EXIT

port() {
    python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}
server_port="$(port)"
client_port="$(port)"
target_port="$(port)"
uuid="$($XRAY_TEST_BIN uuid)"
key_output="$($XRAY_TEST_BIN x25519)"
private="$(awk -F': *' '/^PrivateKey:/ {print $2; exit}' <<< "$key_output")"
public="$(awk -F': *' '/^Password \(PublicKey\):/ {print $2; exit}' <<< "$key_output")"
short_id='0123456789abcdef'
[[ -n "$private" && -n "$public" ]]
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj '/CN=www.amazon.com' -keyout "$TEST_DIR/target.key" \
    -out "$TEST_DIR/target.crt" >/dev/null 2>&1
openssl s_server -quiet -accept "127.0.0.1:${target_port}" \
    -cert "$TEST_DIR/target.crt" -key "$TEST_DIR/target.key" \
    -tls1_3 -alpn h2,http/1.1 > "$TEST_DIR/target.log" 2>&1 &
target_pid=$!

jq -n --arg id "$uuid" --arg private "$private" --arg sid "$short_id" \
    --arg target "127.0.0.1:${target_port}" --argjson port "$server_port" '{
      log: {loglevel: "debug"},
      inbounds: [{listen: "127.0.0.1", port: $port, protocol: "vless",
        settings: {clients: [{id: $id, flow: "xtls-rprx-vision"}], decryption: "none"},
        streamSettings: {network: "tcp", security: "reality", realitySettings: {
          target: $target, serverNames: ["www.amazon.com"],
          privateKey: $private, shortIds: [$sid]}}}],
      outbounds: [{protocol: "freedom"}]
    }' > "$TEST_DIR/server.json"

jq -n --arg id "$uuid" --arg public "$public" --arg sid "$short_id" \
    --argjson server_port "$server_port" --argjson client_port "$client_port" '{
      log: {loglevel: "warning"},
      inbounds: [{listen: "127.0.0.1", port: $client_port, protocol: "socks",
        settings: {auth: "noauth", udp: false}}],
      outbounds: [{protocol: "vless", settings: {vnext: [{address: "127.0.0.1",
        port: $server_port, users: [{id: $id, flow: "xtls-rprx-vision", encryption: "none"}]}]},
        streamSettings: {network: "tcp", security: "reality", realitySettings: {
          serverName: "www.amazon.com", fingerprint: "chrome",
          publicKey: $public, shortId: $sid}}}]
    }' > "$TEST_DIR/client.json"

"$XRAY_TEST_BIN" run -test -config "$TEST_DIR/server.json" >/dev/null
"$XRAY_TEST_BIN" run -test -config "$TEST_DIR/client.json" >/dev/null
"$XRAY_TEST_BIN" run -config "$TEST_DIR/server.json" > "$TEST_DIR/server.log" 2>&1 &
server_pid=$!
"$XRAY_TEST_BIN" run -config "$TEST_DIR/client.json" > "$TEST_DIR/client.log" 2>&1 &
client_pid=$!
for attempt in 1 2 3 4 5; do
    curl -fsS --connect-timeout 2 --max-time 4 --noproxy '' \
        --proxy "socks5h://127.0.0.1:${client_port}" \
        'http://127.0.0.1:18080/' -o /dev/null 2>/dev/null || true
    if rg -q 'proxy/vless/inbound: received request' "$TEST_DIR/server.log" \
        && rg -q 'Xtls Unpadding' "$TEST_DIR/server.log"; then
        printf 'REALITY + Vision 握手通过（本地回环目标被 Xray 规则阻断）\n'
        exit 0
    fi
done
printf 'REALITY + Vision 握手失败\n' >&2
sed -n '1,100p' "$TEST_DIR/server.log" >&2
sed -n '1,100p' "$TEST_DIR/client.log" >&2
exit 1
