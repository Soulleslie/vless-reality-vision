#!/usr/bin/env bash
# self-update：只在下载内容完整、可运行且不降级时原子替换管理脚本；其余情况原脚本保持不变。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" == --child-menu ]]; then
    # shellcheck source=/dev/null
    source <(sed '$d' "$ROOT/install.sh")
    MARKER="$TEST_DIR_CHILD/no-marker"; MANAGER="$TEST_DIR_CHILD/manager"; SHORTCUT="$TEST_DIR_CHILD/shortcut"
    need_root() { :; }
    manager_update() { cp "$MANAGER" "$MANAGER.new" && mv -f "$MANAGER.new" "$MANAGER" && say 'TEST: replaced'; }
    interactive_menu; exit 0
fi
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"; trap 'rm -rf -- "$TEST_DIR"' EXIT
MANAGER="$TEST_DIR/vless-reality-setup.sh"; SELF_DIR="$TEST_DIR/no-self"; CONFIG_DIR="$TEST_DIR/no-config"
LINK_FILE="$TEST_DIR/link.txt"; XRAY_BIN="$TEST_DIR/bin/xray"; TFO_SYSCTL="$TEST_DIR/tfo.conf"
CHECKER_BIN="$TEST_DIR/bin/reality-checker"; SHORTCUT="$TEST_DIR/shortcut"
mkdir -p "$TEST_DIR/bin"
need_root() { :; }
REMOTE="$TEST_DIR/remote.sh"; DOWNLOAD=ok
curl() {
    local args=("$@") index out=''
    for ((index = 0; index < ${#args[@]}; index++)); do [[ "${args[index]}" != -o ]] || out="${args[index + 1]}"; done
    [[ " $* " == *" $MANAGER_URL "* && " $* " == *" --proto =https "* && -n "$out" ]] || return 90
    [[ "$DOWNLOAD" == ok ]] || return 22
    cp -- "$REMOTE" "$out"
}
reset_manager() { cp "$ROOT/install.sh" "$MANAGER"; chmod 700 "$MANAGER"; before="$(sha256sum "$MANAGER")"; }
unchanged() { [[ "$(sha256sum "$MANAGER")" == "$before" ]]; }
no_temp_left() { [[ -z "$(find "$TEST_DIR" -maxdepth 1 -name '.vless-reality-setup.*' -print)" ]]; }
current="$(script_version_of "$ROOT/install.sh")"
[[ "$current" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]
expect_refused() {
    local message="$1" output
    output="$( (manager_update) 2>&1 )" && { echo "应拒绝：$message"; exit 1; }
    [[ "$output" == *"$message"* ]] || { printf '%s\n' "$output"; exit 1; }
    unchanged; no_temp_left
}

# 与远端完全相同：不替换。
reset_manager; cp "$ROOT/install.sh" "$REMOTE"
inode="$(stat -c %i "$MANAGER")"
[[ "$(manager_update 2>&1)" == *"管理脚本已是最新：v$current"* ]]
[[ "$(stat -c %i "$MANAGER")" == "$inode" ]]; unchanged; no_temp_left

# 新版本：原子替换（新 inode，正在运行的旧进程不受影响），权限 700。
reset_manager
sed "s/^SCRIPT_VERSION='.*'\$/SCRIPT_VERSION='99.0.0'/" "$ROOT/install.sh" > "$REMOTE"
output="$(manager_update 2>&1)"
[[ "$output" == *"已从 v$current 更新到 v99.0.0"* && "$output" == *'Xray 未重启'* ]]
cmp -s "$REMOTE" "$MANAGER" && [[ "$(stat -c %a "$MANAGER")" == 700 && "$(stat -c %i "$MANAGER")" != "$inode" ]]
no_temp_left

# 同版本号但内容有修订：允许替换。
reset_manager
{ cat "$ROOT/install.sh"; printf '# revised\n'; } > "$REMOTE"
sed -i '$d' "$REMOTE"; sed -i '$d' "$REMOTE"; { printf '# revised\n'; printf 'main "$@"\n'; } >> "$REMOTE"
[[ "$(manager_update 2>&1)" == *"版本号仍为 v$current，内容有修订"* ]]
cmp -s "$REMOTE" "$MANAGER"

# 以下情况均不得修改原脚本，也不得遗留临时文件。
reset_manager
sed "s/^SCRIPT_VERSION='.*'\$/SCRIPT_VERSION='0.0.1'/" "$ROOT/install.sh" > "$REMOTE"
expect_refused '未降级'
printf 'if then\n' >> "$REMOTE"; sed -i "s/^SCRIPT_VERSION='.*'\$/SCRIPT_VERSION='99.0.0'/" "$REMOTE"
expect_refused '语法检查'
sed "s/^SCRIPT_VERSION='.*'\$/SCRIPT_VERSION='99.0.0'/; s/$MANAGER_TAG/other script/" "$ROOT/install.sh" > "$REMOTE"
expect_refused '不是本项目的管理脚本'
sed "/^SCRIPT_VERSION=/d" "$ROOT/install.sh" > "$REMOTE"
expect_refused '缺少有效版本号'
{ sed -n 1,3p "$ROOT/install.sh"; printf 'exit 1\n'; sed '1,3d' "$ROOT/install.sh"; } > "$REMOTE"
sed -i "s/^SCRIPT_VERSION='.*'\$/SCRIPT_VERSION='99.0.0'/" "$REMOTE"
expect_refused '无法正常启动'
cp "$ROOT/install.sh" "$REMOTE"; DOWNLOAD=fail
expect_refused '下载管理脚本失败'
DOWNLOAD=ok

# 管理脚本缺失、为符号链接或不属于本项目时不下载。
rm -f "$MANAGER"
[[ "$( (manager_update) 2>&1 )" == *'未找到管理脚本'* ]]
ln -s "$ROOT/install.sh" "$MANAGER"
[[ "$( (manager_update) 2>&1 )" == *'未找到管理脚本'* ]]
rm -f "$MANAGER"; printf '#!/bin/sh\n' > "$MANAGER"
[[ "$( (manager_update) 2>&1 )" == *'不是本项目的管理脚本'* ]]

# 被中断时遗留的暂存文件由卸载清理（与 README 手动更新使用同一命名）。
touch "$TEST_DIR/.vless-reality-setup.abcdef"
clean_runtime_residue
no_temp_left

# 菜单中更新成功后退出旧菜单进程，提示重新进入；未替换时照常返回菜单。
command -v script >/dev/null 2>&1 || { printf '缺少 script 命令\n' >&2; exit 1; }
export TEST_DIR_CHILD="$TEST_DIR"; cp "$ROOT/install.sh" "$TEST_DIR/manager"
printf -v child_command 'bash %q --child-menu' "$ROOT/tests/manager_update.bash"
output="$(printf '30\n' | script -q -e -c "$child_command" /dev/null)"
[[ "$output" == *'TEST: replaced'* && "$output" == *'请重新运行'*'进入新版菜单'* && "$output" != *'按回车返回主菜单'* ]]
printf '管理脚本更新：原子替换、降级/损坏/伪造/下载失败保护、暂存清理与菜单重新进入通过\n'
