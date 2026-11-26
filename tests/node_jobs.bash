#!/usr/bin/env bash
# 会重启 Xray 的前台命令必须交给 systemd 后台任务提交，并在任务结束后按实际配置核对结果。
# systemd-run 用替身在当前进程内执行真实的 __*-apply 分派，不触碰主机服务。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"; trap 'rm -rf -- "$TEST_DIR"' EXIT
CONFIG_DIR="$TEST_DIR/config"; CONFIG="$CONFIG_DIR/config.json"; MARKER="$CONFIG_DIR/.vless-reality-owned"
LINK_FILE="$TEST_DIR/link.txt"; SELF_DIR="$TEST_DIR/no-self-state"; SHORTCUT="$TEST_DIR/shortcut"
SCRIPT_PATH="$ROOT/install.sh"; JOB_LOG="$TEST_DIR/jobs"
mkdir -p "$CONFIG_DIR"
need_root() { :; }; chown() { :; }
systemctl() { return 1; } # Xray 视为停止：事务不重启服务。
config_ok() { return 0; }
port_free() { return 0; }
target_tls_ok() { [[ "$1" != broken.example.net ]]; }
test_xray() { [[ "$1" == uuid ]] && printf '22222222-2222-4222-8222-222222222222\n'; }
XRAY_BIN=test_xray
generate_reality_keys() { printf '%s\n' AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD; }
JOB_MODE=run
systemd-run() {
    [[ " $* " == *' --wait '* && " $* " == *' --collect '* ]] || return 99
    local args=("$@") index unit=''
    for ((index = 0; index < ${#args[@]}; index++)); do
        [[ "${args[index]}" != --unit=* ]] || unit="${args[index]#--unit=}"
        if [[ "${args[index]}" == /bin/bash ]]; then break; fi
    done
    [[ "${args[index + 1]}" == "$(readlink -f -- "$SCRIPT_PATH")" ]] || return 98
    printf '%s %s\n' "$unit" "${args[*]:index + 2}" >> "$JOB_LOG"
    case "$JOB_MODE" in
        run) ( main "${args[@]:index + 2}" ) ;;
        noop) return 0 ;;
        fail) return 1 ;;
    esac
}
fixture() {
    NODE_MODE=external; ADDR_MODE=auto; ADDR_DOMAIN=''; SERVER_IP=203.0.113.1; XHTTP_PATH=''
    PORT=443; SNI=camouflage.example.net; NODE_NAME=Job-Test
    PUBLIC_KEY=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB; SHORT_ID=0123456789abcdef
    TFO_ENABLED=0; CLIENT_ENCRYPTION=none; VLESS_DECRYPTION=none
    write_config 00000000-0000-4000-8000-000000000000 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    write_marker; show_node >/dev/null
    : > "$JOB_LOG"; JOB_MODE=run
}
no_backup_left() { [[ -z "$(find "$CONFIG_DIR" -name '.change-backup.*' -print)" ]]; }

# 端口：前台预检，后台提交；结束后配置、安装记录和链接一致。
fixture
output="$(port_node 8443 2>&1)"
[[ "$(< "$JOB_LOG")" == 'vless-reality-port __port-apply 8443' ]]
[[ "$output" == *'如果 SSH 经过此节点，连接可能中断。后台任务会继续执行'* && "$output" == *'端口已改为 TCP 8443'* ]]
load_metadata
[[ "$PORT" == 8443 && "$(jq -r '.inbounds[0].port' "$CONFIG")" == 8443 && "$(< "$LINK_FILE")" == *'@203.0.113.1:8443?'* ]]
no_backup_left
# 前台预检失败时不启动后台任务。
: > "$JOB_LOG"
if (port_node 8443 >/dev/null 2>&1); then exit 1; fi
if (port_node 70000 >/dev/null 2>&1); then exit 1; fi
[[ ! -s "$JOB_LOG" ]]

# 伪装域名：手动域名先在前台做 TLS 校验，后台只提交已确认的域名。
fixture
if (sni_node broken.example.net >/dev/null 2>&1); then exit 1; fi
[[ ! -s "$JOB_LOG" ]]
sni_node www.example.org >/dev/null 2>&1
[[ "$(< "$JOB_LOG")" == 'vless-reality-sni __sni-apply www.example.org' ]]
load_metadata
[[ "$SNI" == www.example.org && "$(jq -r '.inbounds[0].streamSettings.realitySettings.target' "$CONFIG")" == www.example.org:443 ]]
no_backup_left
# 自动优选在前台完成；结果与当前相同则不启动任务。
select_fastest_sni() { SNI=www.example.org; }
: > "$JOB_LOG"
[[ "$(sni_node auto 2>&1)" == *'已是本次测试的最优选项'* && ! -s "$JOB_LOG" ]]
select_fastest_sni() { SNI=www.example.com; }
sni_node auto >/dev/null 2>&1
[[ "$(< "$JOB_LOG")" == 'vless-reality-sni __sni-apply www.example.com' ]]

# UUID 与 REALITY 密钥。
fixture
uuid_node >/dev/null 2>&1
[[ "$(< "$JOB_LOG")" == 'vless-reality-uuid __uuid-apply' && "$(config_uuid)" == 22222222-2222-4222-8222-222222222222 ]]
[[ "$(< "$LINK_FILE")" == 'vless://22222222-2222-4222-8222-222222222222@'* ]]
no_backup_left
fixture
rotate_keys_node >/dev/null 2>&1
load_metadata
[[ "$(< "$JOB_LOG")" == 'vless-reality-keys __keys-apply' && "$PUBLIC_KEY" == DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD ]]
[[ "$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG")" == AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA ]]
no_backup_left

# 后台任务失败，或报告成功但配置未变化，前台都不能显示成功。
fixture; JOB_MODE=fail
output="$( (port_node 8443) 2>&1 )" && exit 1
[[ "$output" == *'journalctl -u vless-reality-port'* && "$output" != *'端口已改为'* ]]
fixture; JOB_MODE=noop
output="$( (uuid_node) 2>&1 )" && exit 1
[[ "$output" == *'UUID 未改变'* ]]

# 升级：前台按实际版本报告结果。
fixture
printf '26.1.1' > "$TEST_DIR/version" # 后台任务在子进程运行，版本状态用文件传递。
installed_version() { cat "$TEST_DIR/version"; }
update_xray() { printf '26.2.0' > "$TEST_DIR/version"; }
[[ "$(update_node 2>&1)" == *'Xray 已从 26.1.1 升级到 26.2.0'* && "$(< "$JOB_LOG")" == 'vless-reality-update __update-apply' ]]
update_xray() { :; }
[[ "$(update_node 2>&1)" == *'Xray 版本未变化：26.2.0'* ]]
# 指定版本：可回退；版本号带或不带 v 均可，后台任务只接收规范化后的 vX.Y.Z。
update_xray() { [[ $# == 1 && "$1" == v* ]] && printf '%s' "${1#v}" > "$TEST_DIR/version"; }
: > "$JOB_LOG"
output="$(update_node 26.1.1 2>&1)"
[[ "$(< "$JOB_LOG")" == 'vless-reality-update __update-apply v26.1.1' && "$(< "$TEST_DIR/version")" == 26.1.1 ]]
[[ "$output" == *'将从 26.2.0 回退到 26.1.1'* && "$output" == *'Xray 已从 26.2.0 切换到 26.1.1'* ]]
: > "$JOB_LOG"
[[ "$(update_node v26.3.0 2>&1)" == *'Xray 已从 26.1.1 切换到 26.3.0'* && "$(< "$JOB_LOG")" == 'vless-reality-update __update-apply v26.3.0' ]]
# 目标即当前版本、格式错误：不启动后台任务。
: > "$JOB_LOG"
[[ "$(update_node v26.3.0 2>&1)" == *'当前已是 Xray 26.3.0'* ]]
for bad in 26.3 v26.3.0-beta latest2 ../26.1.1; do
    if (update_node "$bad" >/dev/null 2>&1); then echo "应拒绝版本号 $bad"; exit 1; fi
done
[[ ! -s "$JOB_LOG" ]]
# 后台任务结束但版本不是目标版本：不能报告成功。
update_xray() { :; }
output="$( (update_node v26.4.0) 2>&1 )" && exit 1
[[ "$output" == *'不是 26.4.0'* && "$output" != *'切换到'* ]]

# 传输切换未完成时拒绝启动其他后台任务，只允许恢复任务。
fixture
mkdir "$CONFIG_DIR/.transport-pending"
rc=0; (port_node 8443 >/dev/null 2>&1) || rc=$?
[[ "$rc" == 3 && ! -s "$JOB_LOG" ]]
JOB_MODE=noop
run_node_job vless-reality-transport test __transport-recover >/dev/null 2>&1
[[ "$(< "$JOB_LOG")" == 'vless-reality-transport __transport-recover' ]]
rmdir "$CONFIG_DIR/.transport-pending"

# 修改写入失败：恢复原配置并删除备份（此前 UUID 修改会遗留含旧配置的备份目录）。
fixture
before="$(sha256sum "$CONFIG" "$MARKER")"
(
    edit_config_private() { printf 'partial\n' > "$CONFIG"; return 1; }
    if (change_uuid >/dev/null 2>&1); then exit 1; fi
)
[[ "$(sha256sum "$CONFIG" "$MARKER")" == "$before" ]]
no_backup_left
(
    edit_port_config() { printf 'partial\n' > "$CONFIG"; return 1; }
    PORT=9443
    if (node_change 443 unused edit_port_config >/dev/null 2>&1); then exit 1; fi
)
[[ "$(sha256sum "$CONFIG" "$MARKER")" == "$before" ]]
no_backup_left

# 安装记录损坏时，菜单状态行给出提示而不退出整个菜单。
fixture
sed -i '2s/.*/bad host!/' "$MARKER"
output="$(menu_status 2>&1)"
[[ "$output" == *'安装记录无效'*'26'* ]]
printf '后台任务提交、结果核对、未完成传输保护、写入失败清理和损坏记录菜单测试通过\n'
