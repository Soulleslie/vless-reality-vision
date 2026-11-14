#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"; [[ -z "${node_stage:-}" ]] || rm -rf -- "$node_stage"; [[ -z "${csv_stage:-}" ]] || rm -rf -- "$csv_stage"' EXIT
mkdir -p "$TEST_DIR/bin"
CHECKER_BIN="$TEST_DIR/bin/reality-checker"
CHECKER_MARKER="$TEST_DIR/bin/.vless-reality-checker-owned"
# RealityChecker 已移除，只验证旧版安装的安全清理。
if declare -F checker_command >/dev/null || declare -F install_checker >/dev/null; then
    printf '不应保留 RealityChecker 安装或检测入口\n' >&2
    exit 1
fi
[[ "$(print_help)" != *checker* ]]
[[ "$(show_menu)" != *RealityChecker* ]]
if legacy_numeric_action 18; then exit 1; fi
printf 'legacy checker\n' > "$CHECKER_BIN"
digest="$(sha256sum "$CHECKER_BIN" | awk '{print $1}')"
printf '%s\nversion=v2.2.3\nsha256=%s\n' "$CHECKER_TAG" "$digest" > "$CHECKER_MARKER"
checker_binary_is_ours
printf 'modified\n' >> "$CHECKER_BIN"
if remove_checker >/dev/null 2>&1; then
    printf '修改后的 RealityChecker 不应被删除\n' >&2
    exit 1
fi
[[ -f "$CHECKER_BIN" && -f "$CHECKER_MARKER" ]]
sed -i '$d' "$CHECKER_BIN"
remove_checker
[[ ! -e "$CHECKER_BIN" && ! -e "$CHECKER_MARKER" ]]
printf 'foreign\n' > "$CHECKER_BIN"
remove_checker
[[ "$(< "$CHECKER_BIN")" == foreign ]]
rm -f -- "$CHECKER_BIN"

stage="$(mktemp -d "$TEST_DIR/bin/.vless-reality-checker-stage.XXXXXX")"
printf 'vless-reality-setup\n' > "$stage/.vless-reality-owned"
touch "$stage/release.json" "$stage/reality-checker.zip" "$stage/reality-checker" "$stage/receipt"
node_stage="$(mktemp -d /tmp/vless-reality-update.XXXXXX)"
printf 'vless-reality-setup\n' > "$node_stage/.vless-reality-owned"
touch "$node_stage/xray.zip"
csv_stage="$(mktemp -d /tmp/vless-reality-checker-csv.XXXXXX)"
printf 'vless-reality-setup\n' > "$csv_stage/.vless-reality-owned"
touch "$csv_stage/normalized.csv"
clean_checker_stage
[[ ! -e "$stage" ]]
[[ ! -e "$csv_stage" ]]
[[ -d "$node_stage" ]]
clean_runtime_residue
[[ ! -e "$node_stage" ]]

printf 'RealityChecker 旧版本清理验证通过\n'
