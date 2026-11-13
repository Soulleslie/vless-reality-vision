#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"; [[ -z "${node_stage:-}" ]] || rm -rf -- "$node_stage"' EXIT
mkdir -p "$TEST_DIR/bin"
CHECKER_BIN="$TEST_DIR/bin/reality-checker"
CHECKER_MARKER="$TEST_DIR/bin/.vless-reality-checker-owned"
need_root() { :; }
ensure_dependencies() { :; }
asset="$(checker_asset)"
printf 'fake release archive\n' > "$TEST_DIR/archive.zip"
digest="$(sha256sum "$TEST_DIR/archive.zip" | awk '{print $1}')"
jq -n --arg name "$asset" --arg digest "sha256:$digest" \
    --arg url "https://github.com/V2RaySSR/RealityChecker/releases/download/v2.2.3/$asset" \
    '{tag_name:"v2.2.3",draft:false,prerelease:false,
      assets:[{name:$name,digest:$digest,browser_download_url:$url}]}' \
    > "$TEST_DIR/release.json"
curl() {
    local output='' previous='' item
    for item in "$@"; do
        if [[ "$previous" == -o ]]; then output="$item"; fi
        previous="$item"
    done
    [[ -n "$output" ]] || return 1
    case "${@: -1}" in
        "$CHECKER_API") cp -- "$TEST_DIR/release.json" "$output" ;;
        https://github.com/V2RaySSR/RealityChecker/releases/download/*)
            cp -- "$TEST_DIR/archive.zip" "$output" ;;
        *) return 1 ;;
    esac
}
unzip() {
    local destination="${@: -1}"
    printf '#!/usr/bin/env bash\nprintf "arg:%%s\\n" "$@"\n' > "$destination/reality-checker"
}

checker_command install >/dev/null
[[ -x "$CHECKER_BIN" && -f "$CHECKER_MARKER" ]]
checker_binary_is_ours
[[ "$(checker_command status)" == *'v2.2.3'* ]]
[[ "$(checker_command check example.com)" == $'arg:check\narg:example.com' ]]
[[ "$(checker_command batch Apple.com tesla.com microsoft.com)" \
    == $'arg:batch\narg:apple.com\narg:tesla.com\narg:microsoft.com' ]]
printf 'domain\nexample.com\n' > "$TEST_DIR/domains with space.csv"
[[ "$(checker_command csv "$TEST_DIR/domains with space.csv")" \
    == $'arg:csv\n'"arg:$TEST_DIR/domains with space.csv" ]]
if (checker_command batch example.com 'https://bad.example.com' >/dev/null 2>&1); then
    printf '批量检测应拒绝 URL\n' >&2
    exit 1
fi
if (checker_command csv "$TEST_DIR/missing.csv" >/dev/null 2>&1); then
    printf 'CSV 检测应拒绝不存在的文件\n' >&2
    exit 1
fi
menu_output="$(printf '3\nApple.com tesla.com\n' | checker_menu)"
[[ "$menu_output" == *$'arg:batch\narg:apple.com\narg:tesla.com'* ]]
menu_output="$(printf '2\nApple.com\n' | checker_menu)"
[[ "$menu_output" == *$'arg:check\narg:apple.com'* ]]
menu_output="$(printf '4\n%s\n' "$TEST_DIR/domains with space.csv" | checker_menu)"
[[ "$menu_output" == *$'arg:csv\n'"arg:$TEST_DIR/domains with space.csv"* ]]
chmod 600 "$CHECKER_BIN"
[[ "$(checker_command status)" == *'执行权限已丢失'* ]]
checker_command install >/dev/null
[[ -x "$CHECKER_BIN" ]]

printf 'modified\n' >> "$CHECKER_BIN"
if (checker_command uninstall >/dev/null 2>&1); then
    printf '修改后的 RealityChecker 不应被删除\n' >&2
    exit 1
fi
[[ -f "$CHECKER_BIN" && -f "$CHECKER_MARKER" ]]
sed -i '$d' "$CHECKER_BIN"
checker_command uninstall >/dev/null
[[ ! -e "$CHECKER_BIN" && ! -e "$CHECKER_MARKER" ]]

printf 'foreign\n' > "$CHECKER_BIN"
if (checker_command install >/dev/null 2>&1); then
    printf '不应覆盖已有同名程序\n' >&2
    exit 1
fi
[[ "$(< "$CHECKER_BIN")" == foreign ]]
rm -f -- "$CHECKER_BIN"

stage="$(mktemp -d "$TEST_DIR/bin/.vless-reality-checker-stage.XXXXXX")"
printf 'vless-reality-setup\n' > "$stage/.vless-reality-owned"
touch "$stage/release.json" "$stage/reality-checker.zip" "$stage/reality-checker" "$stage/receipt"
node_stage="$(mktemp -d /tmp/vless-reality-update.XXXXXX)"
printf 'vless-reality-setup\n' > "$node_stage/.vless-reality-owned"
touch "$node_stage/xray.zip"
checker_command uninstall >/dev/null
[[ ! -e "$stage" ]]
[[ -d "$node_stage" ]]
clean_runtime_residue
[[ ! -e "$node_stage" ]]

printf 'changed archive\n' > "$TEST_DIR/archive.zip"
if (checker_command install >/dev/null 2>&1); then
    printf '校验失败的压缩包不应被安装\n' >&2
    exit 1
fi
[[ ! -e "$CHECKER_BIN" && ! -e "$CHECKER_MARKER" ]]
printf 'RealityChecker 安装与清理验证通过\n'
