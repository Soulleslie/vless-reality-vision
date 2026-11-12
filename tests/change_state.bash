#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
CONFIG="$TEST_DIR/config.json"
MARKER="$TEST_DIR/.vless-reality-owned"
PORT=443
restart_calls=0
systemctl() { (( restart_calls += 1 )); return 0; }
wait_service() { return 0; }
config_ok() { return 0; }
show_node() { return 0; }

make_backup() {
    local backup="$1"
    mkdir -p "$backup"
    printf 'old-config\n' > "$backup/config.json"
    printf 'old-marker\n' > "$backup/.vless-reality-owned"
    printf 'new-config\n' > "$CONFIG"
    printf 'new-marker\n' > "$MARKER"
}

make_backup "$TEST_DIR/backup-stopped"
restore_state "$TEST_DIR/backup-stopped" 0
[[ "$restart_calls" == 0 && "$(< "$CONFIG")" == old-config ]]

make_backup "$TEST_DIR/backup-running"
restore_state "$TEST_DIR/backup-running" 1
[[ "$restart_calls" == 1 && "$(< "$MARKER")" == old-marker ]]

mkdir -p "$TEST_DIR/commit-stopped"
commit_change "$TEST_DIR/commit-stopped" 443 '已修改' 0 >/dev/null
[[ "$restart_calls" == 1 ]]
mkdir -p "$TEST_DIR/commit-running"
commit_change "$TEST_DIR/commit-running" 443 '已修改' 1 >/dev/null
[[ "$restart_calls" == 2 ]]
printf '服务状态保持验证通过\n'
