#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
LINK_FILE="$TEST_DIR/link.txt"
printf 'old-link\n' > "$LINK_FILE"
need_root() { return 0; }
load_metadata() {
    PORT=443
    SNI=www.amazon.com
    NODE_NAME=Reality-Test
    SERVER_IP=203.0.113.1
    PUBLIC_KEY=test-public-key
    SHORT_ID=0123456789abcdef
}
config_uuid() { printf '00000000-0000-4000-8000-000000000000'; }

mv() { return 1; }
if show_node >/dev/null 2>&1; then
    printf '链接替换失败时不应返回成功\n' >&2
    exit 1
fi
[[ "$(< "$LINK_FILE")" == old-link ]]

unset -f mv
show_node >/dev/null
[[ "$(< "$LINK_FILE")" == vless://* ]]
printf '客户端链接原子写入验证通过\n'
