#!/usr/bin/env bash
# VLESS + REALITY + Vision 节点管理脚本：Debian/Ubuntu + Xray-core。
# 请先下载为普通文件后运行，不支持 curl | bash（安装过程需要读取终端输入）。
# shellcheck disable=SC2016 # 下方单引号内的 $name 是 jq 变量，不由 Bash 展开。
set -Eeuo pipefail
umask 077

SCRIPT_VERSION='1.6.0'
SCRIPT_PATH="${BASH_SOURCE[0]}"
XRAY_API='https://api.github.com/repos/XTLS/Xray-core/releases'
XRAY_BIN='/usr/local/bin/xray'
CHECKER_API='https://api.github.com/repos/V2RaySSR/RealityChecker/releases/latest'
CHECKER_BIN='/usr/local/bin/reality-checker'
CHECKER_MARKER='/usr/local/bin/.vless-reality-checker-owned'
CHECKER_TAG='# vless-reality-setup: RealityChecker'
CONFIG_DIR='/usr/local/etc/xray'
CONFIG='/usr/local/etc/xray/config.json'
MARKER='/usr/local/etc/xray/.vless-reality-owned'
SERVICE='/etc/systemd/system/xray.service'
MANAGER='/root/vless-reality-setup.sh'
SHORTCUT='/usr/local/bin/vless-reality'
SHORTCUT_TAG='# vless-reality-setup shortcut'
LINK_FILE='/root/vless-reality-link.txt'
TFO_SYSCTL='/etc/sysctl.d/99-vless-reality-tfo.conf'
TFO_TAG='# vless-reality-setup: TCP Fast Open'
TEMP_DIR=''
TEMP_BIN=''
RELEASE_VERSION=''
RELEASE_URL=''
RELEASE_SHA256=''
PORT=''
SNI=''
NODE_NAME=''
SERVER_IP=''
PUBLIC_KEY=''
SHORT_ID=''
INSTALL_STARTED=0
INSTALL_COMMITTED=0
MANAGER_COPIED=0
TFO_ENABLED=0
VLESS_DECRYPTION='none'
CLIENT_ENCRYPTION='none'
SNI_CANDIDATES=(
    www.amazon.com www.samsung.com www.nvidia.com
    digitalassets.tesla.com electronics.sony.com www.xbox.com amd.com
    assets-xbxweb.xbox.com s7mbrstream.scene7.com d.impactradius-event.com
    www.oracle.com acctcdn.msftauth.net cdn-dynmedia-1.microsoft.com
    j.6sc.co lpcdn.lpsnmedia.net ds-aksb-a.akamaihd.net
    gray-config-prod.api.arc-cdn.net img-prod-cms-rt-microsoft-com.akamaized.net
    vscjava.gallerycdn.vsassets.io th.bing.com d2c.aws.amazon.com
    gsp-ssl.ls.apple.com rum.hlx.page www.wowt.com www.amd.com
    sisu.xboxlive.com cdn.userway.org assets.adobedtm.com www.tesla.com
    catalog.gamepass.com cdnssl.clicktale.net aws.com res-1.cdn.office.net
    www.aws.com ts3.tc.mm.bing.net beacon.gtv-pub.com
    d3agakyjgjv5i8.cloudfront.net drivers.amd.com fpinit.itunes.apple.com
    api.company-target.com tag-logger.demandbase.com cua-chat-ui.tesla.com
    store-images.s-microsoft.com gray-wowt-prod.gtv-cdn.com www.sony.com
    cdn77.api.userway.org downloadmirror.intel.com c.6sc.co
    downloaddispatch.itunes.apple.com devblogs.microsoft.com
    static.cloud.coveo.com a.b.cdn.console.awsstatic.com cdn.bizible.com
    apps.mzstatic.com gray.video-player.arcpublishing.com www.xilinx.com
    prod.us-east-1.ui.gcr-chat.marketing.aws.dev snap.licdn.com
    gray-config-prod.api.cdn.arcpublishing.com c.s-microsoft.com
    aadcdn.msftauth.net www.bing.com cdn.bizibly.com s.go-mpulse.net
    publisher.liveperson.net mscom.demdex.net prod.log.shortbread.aws.dev
    visualstudio.microsoft.com
)

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
    GREEN=$'\033[32m' RED=$'\033[31m' YELLOW=$'\033[33m' BOLD=$'\033[1m' RESET=$'\033[0m'
else
    GREEN='' RED='' YELLOW='' BOLD='' RESET=''
fi

say() { printf '%s\n' "$*"; }
ok() { printf '%s%s%s\n' "$GREEN" "$*" "$RESET"; }
warn() { printf '%s%s%s\n' "$YELLOW" "$*" "$RESET"; }
step() { printf '%s%s%s\n' "$BOLD" "$*" "$RESET"; }
fail() { printf '%s错误：%s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }
need_root() { [[ $EUID -eq 0 ]] || fail '请以 root 身份运行（可先执行 sudo -i）。'; }
need_command() { command -v "$1" >/dev/null 2>&1 || fail "缺少命令：$1"; }

valid_host() {
    (( ${#1} <= 253 )) || return 1
    [[ "$1" == *.* && "$1" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]([a-z0-9-]{0,61}[a-z0-9])?$ ]]
}
valid_port() {
    [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}
valid_node_name() {
    [[ -n "$1" && ${#1} -le 64 && "$1" != *$'\n'* ]]
}
port_free() {
    local listeners
    if command -v ss >/dev/null 2>&1; then
        listeners="$(ss -H -ltn "sport = :$1")" || fail "无法检查本机 TCP ${1}。"
        [[ -z "$listeners" ]]
    else
        [[ -r /proc/net/tcp && -r /proc/net/tcp6 ]] || fail '无法检查本机 TCP 端口。'
        awk -v port="$(printf '%04X' "$1")" \
            '$4 == "0A" && $2 ~ (":" port "$") { occupied = 1 } END { exit occupied }' \
            /proc/net/tcp /proc/net/tcp6
    fi
}
choose_port() {
    local raw
    while true; do
        read -r -p '请输入节点 TCP 端口（直接回车使用 443）：' raw || fail '已取消输入。'
        [[ -n "$raw" ]] || raw=443
        if ! valid_port "$raw"; then
            warn '端口无效，请输入 1–65535 的数字。' >&2
            continue
        fi
        if ! port_free "$((10#$raw))"; then
            warn "本机 TCP $((10#$raw)) 已被占用，请输入其他端口（例如 8443）。" >&2
            continue
        fi
        PORT="$((10#$raw))"
        return 0
    done
}
public_ipv4() {
    local url ip
    for url in https://api.ipify.org https://ipv4.icanhazip.com https://ifconfig.me/ip; do
        ip="$(curl -4fsS --connect-timeout 5 --max-time 10 "$url" 2>/dev/null | tr -d '[:space:]')" || continue
        if [[ "$ip" =~ ^[0-9]{1,3}([.][0-9]{1,3}){3}$ ]]; then
            printf '%s' "$ip"
            return 0
        fi
    done
    return 1
}
confirm() {
    local answer default="${2:-n}"
    while true; do
        read -r -p "$1" answer || return 1
        [[ -n "$answer" ]] || answer="$default"
        case "$answer" in
            y|Y|yes|YES) return 0 ;;
            n|N|no|NO) return 1 ;;
            *) warn '请输入 y 或 n。' ;;
        esac
    done
}

ensure_dependencies() {
    need_command apt-get
    local command_name packages=()
    command -v curl >/dev/null 2>&1 || packages+=(curl)
    command -v jq >/dev/null 2>&1 || packages+=(jq)
    command -v unzip >/dev/null 2>&1 || packages+=(unzip)
    command -v openssl >/dev/null 2>&1 || packages+=(openssl)
    command -v ss >/dev/null 2>&1 || packages+=(iproute2)
    command -v sysctl >/dev/null 2>&1 || packages+=(procps)
    if ! dpkg-query -W -f='${Status}' ca-certificates 2>/dev/null | grep -q 'install ok installed'; then
        packages+=(ca-certificates)
    fi
    if (( ${#packages[@]} )); then
        say "安装缺失的基础工具：${packages[*]}"
        apt-get update
        apt-get install -y "${packages[@]}"
    fi
    for command_name in curl jq unzip openssl ss awk sed sort tr date systemctl sysctl sha256sum getent install timeout dpkg; do
        need_command "$command_name"
    done
}

config_tfo_enabled() {
    [[ "$(jq -r '[.inbounds[] | select(.protocol == "vless") | .streamSettings.sockopt.tcpFastOpen][0] // false' "$CONFIG" 2>/dev/null)" == true ]]
}
kernel_tfo_value() {
    local value
    value="$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || cat /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null)" || return 1
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    printf '%s' "$value"
}
kernel_tfo_server() {
    local value
    value="$(kernel_tfo_value)" || return 1
    (( (value & 2) != 0 ))
}
tfo_sysctl_is_ours() {
    [[ -f "$TFO_SYSCTL" && ! -L "$TFO_SYSCTL" ]] \
        && [[ "$(sed -n '1p' "$TFO_SYSCTL")" == "$TFO_TAG" ]]
}
tfo_sysctl_field() {
    local value
    value="$(sed -n "s/^# ${1}=\\([0-9]*\\)$/\\1/p" "$TFO_SYSCTL")" || return 1
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    printf '%s' "$value"
}
enable_kernel_tfo() {
    local current original applied tmp
    current="$(kernel_tfo_value)" || return 1
    if tfo_sysctl_is_ours; then
        original="$(tfo_sysctl_field original)" || return 1
    elif [[ -e "$TFO_SYSCTL" || -L "$TFO_SYSCTL" ]]; then
        if (( (current & 2) != 0 )); then
            warn '内核 TFO 已由其他设置开启；沿用当前内核设置，不修改已有 sysctl 文件。' >&2
            return 0
        fi
        warn "$TFO_SYSCTL 已存在且不属于本脚本，未修改。" >&2
        return 1
    else
        original="$current"
    fi
    applied=$((current | 2))
    tmp="$(mktemp "${TFO_SYSCTL}.XXXXXX")" || return 1
    if ! printf '%s\n# original=%s\n# applied=%s\nnet.ipv4.tcp_fastopen = %s\n' \
        "$TFO_TAG" "$original" "$applied" "$applied" > "$tmp" \
        || ! chmod 644 "$tmp" || ! mv -f -- "$tmp" "$TFO_SYSCTL"; then
        rm -f -- "$tmp"
        return 1
    fi
    sysctl -q -w "net.ipv4.tcp_fastopen=$applied" >/dev/null || return 1
    kernel_tfo_server
}
disable_kernel_tfo() {
    local original applied current
    tfo_sysctl_is_ours || return 0
    original="$(tfo_sysctl_field original)" || return 1
    applied="$(tfo_sysctl_field applied)" || return 1
    current="$(kernel_tfo_value)" || return 1
    if (( current == applied && current != original )); then
        sysctl -q -w "net.ipv4.tcp_fastopen=$original" >/dev/null || return 1
    elif (( current != applied )); then
        warn '内核 TFO 值已被其他程序修改；保留当前值，只移除本脚本的持久化设置。' >&2
    fi
    rm -f -- "$TFO_SYSCTL"
}

arch_asset() {
    case "$(dpkg --print-architecture 2>/dev/null)" in
        amd64) printf 'Xray-linux-64.zip' ;;
        arm64) printf 'Xray-linux-arm64-v8a.zip' ;;
        *) fail "不支持的架构：$(dpkg --print-architecture 2>/dev/null || uname -m)" ;;
    esac
}

fetch_release_metadata() {
    local selector="$1" asset="$2" api_url release_file tag asset_json url digest
    [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] || fail '临时目录未准备好。'
    if [[ "$selector" == latest ]]; then
        api_url="$XRAY_API/latest"
    elif [[ "$selector" =~ ^v[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
        api_url="$XRAY_API/tags/$selector"
    else
        fail "无效的 Xray 版本：$selector"
    fi
    release_file="$TEMP_DIR/release.json"
    curl -fLsS --retry 3 --connect-timeout 10 --max-time 30 \
        -H 'Accept: application/vnd.github+json' -o "$release_file" "$api_url" \
        || fail '无法查询 XTLS/Xray-core 官方 GitHub 发布信息。'
    tag="$(jq -er '.tag_name | select(type == "string")' "$release_file")" \
        || fail '官方发布信息缺少版本号。'
    [[ "$tag" =~ ^v[0-9]+[.][0-9]+[.][0-9]+$ ]] || fail "官方版本号格式异常：$tag"
    [[ "$(jq -r '[.draft, .prerelease] | join(",")' "$release_file")" == 'false,false' ]] \
        || fail '查询到的不是正式稳定版。'
    asset_json="$(jq -c --arg name "$asset" \
        '[(.assets // [])[] | select(.name == $name)] | if length == 1 then .[0] else null end' "$release_file")"
    [[ "$asset_json" != null ]] || fail "官方稳定版 $tag 没有找到 ${asset}。"
    url="$(jq -er '.browser_download_url | select(type == "string")' <<< "$asset_json")" \
        || fail '官方安装包缺少下载地址。'
    digest="$(jq -er '.digest | select(type == "string")' <<< "$asset_json")" \
        || fail '官方安装包缺少 SHA-256。'
    [[ "$url" == "https://github.com/XTLS/Xray-core/releases/download/$tag/$asset" ]] \
        || fail '官方安装包下载地址格式异常。'
    [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || fail '官方安装包 SHA-256 格式异常。'
    RELEASE_VERSION="${tag#v}"
    RELEASE_URL="$url"
    RELEASE_SHA256="${digest#sha256:}"
}

download_verified_release() {
    local target="$1"
    curl -fL --retry 3 --connect-timeout 10 --max-time 180 -o "$target" "$RELEASE_URL" \
        || fail '下载 Xray 官方安装包失败。'
    printf '%s  %s\n' "$RELEASE_SHA256" "$target" | sha256sum --check --status \
        || fail '安装包 SHA-256 与 GitHub 官方发布信息不一致，已停止。'
}

checker_asset() {
    case "$(dpkg --print-architecture 2>/dev/null)" in
        amd64) printf 'reality-checker-linux-amd64.zip' ;;
        arm64) printf 'reality-checker-linux-arm64.zip' ;;
        *) fail 'RealityChecker 仅提供 amd64 和 arm64 安装包。' ;;
    esac
}
checker_marker_is_ours() {
    [[ -f "$CHECKER_MARKER" && ! -L "$CHECKER_MARKER" ]] \
        && [[ "$(sed -n '1p' "$CHECKER_MARKER")" == "$CHECKER_TAG" ]] \
        && [[ "$(sed -n '2p' "$CHECKER_MARKER")" =~ ^version=v[0-9]+[.][0-9]+[.][0-9]+$ ]] \
        && [[ "$(sed -n '3p' "$CHECKER_MARKER")" =~ ^sha256=[0-9a-f]{64}$ ]]
}
checker_binary_is_ours() {
    local expected actual
    checker_marker_is_ours || return 1
    [[ -f "$CHECKER_BIN" && ! -L "$CHECKER_BIN" ]] || return 1
    expected="$(sed -n '3s/^sha256=//p' "$CHECKER_MARKER")"
    actual="$(sha256sum -- "$CHECKER_BIN" | awk '{print $1}')" || return 1
    [[ "$actual" == "$expected" ]]
}
checker_cleanup_preflight() {
    checker_marker_is_ours || return 0
    if [[ -e "$CHECKER_BIN" || -L "$CHECKER_BIN" ]]; then
        checker_binary_is_ours || { warn 'RealityChecker 文件与安装记录不符；已保留，请先检查。' >&2; return 1; }
    fi
}
remove_checker() {
    checker_cleanup_preflight || return 1
    checker_marker_is_ours || return 0
    if [[ -e "$CHECKER_BIN" || -L "$CHECKER_BIN" ]]; then
        rm -f -- "$CHECKER_BIN" || return 1
    fi
    rm -f -- "$CHECKER_MARKER" || return 1
    [[ ! -e "$CHECKER_BIN" && ! -L "$CHECKER_BIN" && ! -e "$CHECKER_MARKER" ]] || return 1
}
install_checker() (
    need_root
    if checker_binary_is_ours; then
        if [[ ! -x "$CHECKER_BIN" ]]; then
            chmod 755 "$CHECKER_BIN" || fail '恢复 RealityChecker 执行权限失败。'
        fi
        ok "RealityChecker 已安装：$(sed -n '2s/^version=//p' "$CHECKER_MARKER")。"
        return 0
    fi
    [[ ! -e "$CHECKER_BIN" && ! -L "$CHECKER_BIN" \
        && ! -e "$CHECKER_MARKER" && ! -L "$CHECKER_MARKER" ]] \
        || fail '发现已有 RealityChecker 程序或安装记录；为避免覆盖，已停止。'
    ensure_dependencies
    local asset stage_dir release_tag asset_json url digest archive binary_hash
    asset="$(checker_asset)" || fail '无法选择 RealityChecker 安装包。'
    stage_dir="$(mktemp -d "${CHECKER_BIN%/*}/.vless-reality-checker-stage.XXXXXX")" \
        || fail '无法创建 RealityChecker 暂存目录。'
    trap 'rm -rf -- "$stage_dir"' EXIT
    printf 'vless-reality-setup\n' > "$stage_dir/.vless-reality-owned" \
        || fail '无法标记 RealityChecker 暂存目录。'
    curl -fLsS --retry 3 --connect-timeout 10 --max-time 30 \
        -H 'Accept: application/vnd.github+json' -o "$stage_dir/release.json" "$CHECKER_API" \
        || fail '无法查询 RealityChecker 官方 GitHub Release。'
    release_tag="$(jq -er '.tag_name | select(type == "string")' "$stage_dir/release.json")" \
        || fail 'RealityChecker 发布信息缺少版本号。'
    [[ "$release_tag" =~ ^v[0-9]+[.][0-9]+[.][0-9]+$ ]] || fail 'RealityChecker 版本号格式异常。'
    [[ "$(jq -r '[.draft, .prerelease] | join(",")' "$stage_dir/release.json")" == 'false,false' ]] \
        || fail 'RealityChecker 最新发布不是正式稳定版。'
    asset_json="$(jq -c --arg name "$asset" \
        '[(.assets // [])[] | select(.name == $name)] | if length == 1 then .[0] else null end' \
        "$stage_dir/release.json")"
    [[ "$asset_json" != null ]] || fail "RealityChecker 发布中没有 $asset。"
    url="$(jq -er '.browser_download_url | select(type == "string")' <<< "$asset_json")" \
        || fail 'RealityChecker 下载地址缺失。'
    digest="$(jq -er '.digest | select(type == "string")' <<< "$asset_json")" \
        || fail 'RealityChecker SHA-256 摘要缺失。'
    [[ "$url" == "https://github.com/V2RaySSR/RealityChecker/releases/download/$release_tag/$asset" ]] \
        || fail 'RealityChecker 下载地址异常。'
    [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || fail 'RealityChecker SHA-256 摘要格式异常。'
    archive="$stage_dir/reality-checker.zip"
    curl -fL --retry 3 --connect-timeout 10 --max-time 180 -o "$archive" "$url" \
        || fail '下载 RealityChecker 失败。'
    printf '%s  %s\n' "${digest#sha256:}" "$archive" | sha256sum --check --status \
        || fail 'RealityChecker 压缩包 SHA-256 校验失败。'
    unzip -q "$archive" reality-checker -d "$stage_dir" || fail '解压 RealityChecker 失败。'
    [[ -f "$stage_dir/reality-checker" && ! -L "$stage_dir/reality-checker" \
        && -s "$stage_dir/reality-checker" ]] || fail '压缩包中的程序文件异常。'
    chmod 755 "$stage_dir/reality-checker" || fail '设置 RealityChecker 执行权限失败。'
    binary_hash="$(sha256sum -- "$stage_dir/reality-checker" | awk '{print $1}')" \
        || fail '无法记录 RealityChecker 程序摘要。'
    printf '%s\nversion=%s\nsha256=%s\n' "$CHECKER_TAG" "$release_tag" "$binary_hash" \
        > "$stage_dir/receipt" || fail '写入 RealityChecker 安装记录失败。'
    chmod 600 "$stage_dir/receipt" || fail '设置 RealityChecker 安装记录权限失败。'
    mv -- "$stage_dir/receipt" "$CHECKER_MARKER" || fail '写入 RealityChecker 安装记录失败。'
    if ! mv -- "$stage_dir/reality-checker" "$CHECKER_BIN"; then
        rm -f -- "$CHECKER_MARKER"
        fail '安装 RealityChecker 程序失败。'
    fi
    checker_binary_is_ours || fail 'RealityChecker 安装后校验失败，请运行 checker uninstall 清理。'
    ok "RealityChecker ${release_tag} 已安装：$CHECKER_BIN"
)
checker_status() {
    if checker_binary_is_ours; then
        if [[ -x "$CHECKER_BIN" ]]; then
            say "RealityChecker：已安装 $(sed -n '2s/^version=//p' "$CHECKER_MARKER")（本脚本管理）"
        else
            warn 'RealityChecker：程序内容正常，但执行权限已丢失；运行 checker install 可恢复。'
        fi
    elif checker_marker_is_ours; then
        warn 'RealityChecker：安装记录存在，但程序缺失或内容已改变。'
    elif [[ -e "$CHECKER_MARKER" || -L "$CHECKER_MARKER" ]]; then
        warn 'RealityChecker：发现无法确认归属的安装记录，已保留。'
    elif [[ -e "$CHECKER_BIN" || -L "$CHECKER_BIN" ]]; then
        warn 'RealityChecker：发现同名程序，但不属于本脚本。'
    else
        say 'RealityChecker：未安装。'
    fi
}
checker_require_ready() {
    checker_binary_is_ours || fail '请先安装本脚本管理的 RealityChecker。'
    [[ -x "$CHECKER_BIN" ]] || fail 'RealityChecker 没有执行权限；请运行 checker install 修复。'
}
checker_csv() (
    local input="$1" stage_dir count
    checker_require_ready
    if ! command -v python3 >/dev/null 2>&1; then
        need_command apt-get
        say '安装 CSV 解析所需的 Python 3…'
        apt-get update && apt-get install -y python3 || fail '安装 Python 3 失败。'
    fi
    stage_dir="$(mktemp -d /tmp/vless-reality-checker-csv.XXXXXX)" || fail '无法创建 CSV 暂存目录。'
    trap 'rm -rf -- "$stage_dir"' EXIT
    printf 'vless-reality-setup\n' > "$stage_dir/.vless-reality-owned" || fail '无法标记 CSV 暂存目录。'
    count="$(python3 - "$input" "$stage_dir/normalized.csv" <<'PY'
import csv
import re
import sys

source, destination = sys.argv[1:]
host_pattern = re.compile(r'(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$')
try:
    with open(source, newline='', encoding='utf-8-sig') as original:
        reader = csv.DictReader(original)
        fields = {name.strip().upper(): name for name in (reader.fieldnames or [])}
        field = fields.get('CERT_DOMAIN') or fields.get('DOMAIN')
        if field is None:
            raise ValueError('缺少 CERT_DOMAIN 或 DOMAIN 列')
        seen = set()
        with open(destination, 'w', newline='', encoding='utf-8') as normalized:
            writer = csv.writer(normalized, lineterminator='\n')
            writer.writerow(('IP', 'ORIGIN', 'CERT_DOMAIN'))
            for row in reader:
                host = (row.get(field) or '').strip().strip('"').lower()
                if host_pattern.fullmatch(host) and host not in seen:
                    writer.writerow(('', '', host))
                    seen.add(host)
        if not seen:
            raise ValueError('域名列中没有有效域名')
        print(len(seen))
except (OSError, UnicodeError, csv.Error, ValueError) as exc:
    print(f'CSV 解析失败：{exc}', file=sys.stderr)
    sys.exit(1)
PY
)" || fail 'CSV 无法转换为 RealityChecker 可读取的域名列。'
    say "从 CSV 域名列提取到 $count 个有效域名；正在检测…"
    "$CHECKER_BIN" csv "$stage_dir/normalized.csv"
)
checker_command() {
    local action="${1:-status}" host="${2:-}" candidate file
    local -a domains=()
    need_root
    case "$action" in
        status) [[ $# -le 1 ]] || fail '用法：checker status'; checker_status ;;
        install) [[ $# -le 1 ]] || fail '用法：checker install'; install_checker ;;
        uninstall)
            [[ $# -le 1 ]] || fail '用法：checker uninstall'
            if ! checker_marker_is_ours; then
                clean_checker_stage || fail 'RealityChecker 暂存文件未清理。'
                say '没有本脚本管理的 RealityChecker；未删除其他程序。'
                return 0
            fi
            remove_checker || fail 'RealityChecker 未清理；请检查程序与安装记录。'
            clean_checker_stage || fail 'RealityChecker 暂存文件未清理。'
            ok '本脚本安装的 RealityChecker 已清理。'
            ;;
        check)
            [[ $# -eq 2 ]] || fail '用法：checker check 域名'
            host="${host,,}"
            valid_host "$host" || fail '请输入纯域名。'
            checker_require_ready
            "$CHECKER_BIN" check "$host"
            ;;
        batch)
            [[ $# -ge 2 ]] || fail '用法：checker batch 域名1 域名2 ...'
            shift
            for candidate in "$@"; do
                candidate="${candidate,,}"
                valid_host "$candidate" || fail "批量检测中含有无效域名：$candidate"
                domains+=("$candidate")
            done
            checker_require_ready
            "$CHECKER_BIN" batch "${domains[@]}"
            ;;
        csv)
            [[ $# -eq 2 ]] || fail '用法：checker csv 文件路径'
            file="$host"
            [[ -f "$file" && -r "$file" ]] || fail "CSV 文件不可读取：$file"
            [[ "$file" != -* ]] || file="./$file"
            checker_csv "$file"
            ;;
        *) fail '用法：checker [status|install|uninstall|check 域名|batch 域名...|csv 文件]' ;;
    esac
}
checker_menu() {
    need_root
    checker_status
    local choice host file
    local -a domains=()
    read -r -p 'RealityChecker [1 安装 / 2 单域名 / 3 批量 / 4 CSV / 5 卸载 / 0 返回]：' choice || return 0
    case "$choice" in
        1) checker_command install ;;
        2) read -r -p '请输入纯域名：' host || return 0; checker_command check "$host" ;;
        3)
            read -r -p '请输入多个域名（空格分隔）：' host || return 0
            read -r -a domains <<< "$host"
            checker_command batch "${domains[@]}"
            ;;
        4) read -r -p '请输入 CSV 文件路径：' file || return 0; checker_command csv "$file" ;;
        5) checker_command uninstall ;;
        0|'') return 0 ;;
        *) warn '请输入 0–5。' ;;
    esac
}

installed_version() {
    if [[ -x "$XRAY_BIN" ]]; then
        "$XRAY_BIN" version 2>/dev/null | awk 'NR == 1 {print $2}'
    fi
}

target_tls_ok() {
    local host="$1" timeout_seconds="${2:-10}" output
    output="$(timeout "$timeout_seconds" openssl s_client -connect "${host}:443" -servername "$host" \
        -tls1_3 -verify_hostname "$host" -verify_return_error -CApath /etc/ssl/certs \
        </dev/null 2>&1 || true)"
    [[ "$output" == *'Verify return code: 0 (ok)'* && "$output" == *'TLSv1.3'* ]]
}
probe_target_latency() {
    local host="$1" start end
    start="$(date +%s%3N)" || return 1
    target_tls_ok "$host" 5 || return 1
    end="$(date +%s%3N)" || return 1
    [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ && "$end" -ge "$start" ]] || return 1
    printf '%s' "$((end - start))"
}
select_fastest_sni() {
    local host first second score index pid line probe_dir count=0
    local -a pids=() valid_indices=() ranked=() finalists=()
    say "正在从 VPS 并发初筛 ${#SNI_CANDIDATES[@]} 个域名（TLS 1.3 与证书校验）…"
    probe_dir="$(mktemp -d /tmp/vless-reality-sni.XXXXXX)" || return 1
    if ! printf '%s\n' vless-reality-setup > "$probe_dir/.vless-reality-owned"; then
        rm -rf -- "$probe_dir"
        return 1
    fi
    for ((index = 0; index < ${#SNI_CANDIDATES[@]}; index++)); do
        host="${SNI_CANDIDATES[index]}"
        (probe_target_latency "$host" > "$probe_dir/result.$index") &
        pids+=("$!")
        if (( ${#pids[@]} >= 16 || index == ${#SNI_CANDIDATES[@]} - 1 )); then
            for pid in "${pids[@]}"; do wait "$pid" || true; done
            pids=()
            say "  已初筛 $((index + 1))/${#SNI_CANDIDATES[@]} 个域名"
        fi
    done
    for ((index = 0; index < ${#SNI_CANDIDATES[@]}; index++)); do
        [[ -f "$probe_dir/result.$index" ]] || continue
        first="$(< "$probe_dir/result.$index")"
        [[ "$first" =~ ^[0-9]+$ ]] || continue
        valid_indices+=("$index")
    done
    if (( ${#valid_indices[@]} == 0 )); then
        rm -rf -- "$probe_dir"
        return 1
    fi
    say "初筛通过 ${#valid_indices[@]} 个域名；正在并发复测全部可用候选…"
    for index in "${valid_indices[@]}"; do
        host="${SNI_CANDIDATES[index]}"
        (probe_target_latency "$host" > "$probe_dir/result2.$index") &
        pids+=("$!")
        count=$((count + 1))
        if (( ${#pids[@]} >= 16 || count == ${#valid_indices[@]} )); then
            for pid in "${pids[@]}"; do wait "$pid" || true; done
            pids=()
            say "  已复测 $count/${#valid_indices[@]} 个域名"
        fi
    done
    for index in "${valid_indices[@]}"; do
        [[ -f "$probe_dir/result2.$index" ]] || continue
        second="$(< "$probe_dir/result2.$index")"
        [[ "$second" =~ ^[0-9]+$ ]] || continue
        first="$(< "$probe_dir/result.$index")"
        score=$(((first + second) / 2))
        ranked+=("$score ${SNI_CANDIDATES[index]}")
    done
    rm -rf -- "$probe_dir"
    (( ${#ranked[@]} > 0 )) || return 1
    mapfile -t finalists < <(printf '%s\n' "${ranked[@]}" | sort -n | sed -n '1,5p')
    say '平均握手耗时最低的候选：'
    for line in "${finalists[@]}"; do
        say "  ${line#* }：约 ${line%% *} ms"
    done
    SNI="${finalists[0]#* }"
    ok "实测延迟最低的域名：$SNI（约 ${finalists[0]%% *} ms）"
}

show_fastest_sni() (
    local command_name
    for command_name in openssl timeout date sort sed mktemp; do
        need_command "$command_name"
    done
    select_fastest_sni || fail '候选域名均不可用，请检查 VPS 网络或手动指定伪装域名。'
    say '此操作只显示测速结果，不修改节点配置。'
)

generate_reality_keys() {
    local output private public
    output="$($XRAY_BIN x25519)" || return 1
    private="$(awk -F': *' '/^(PrivateKey|Private key):/ {print $2; exit}' <<< "$output")"
    public="$(awk -F': *' '/^(Password \(PublicKey\)|PublicKey|Public key):/ {print $2; exit}' <<< "$output")"
    [[ "$private" =~ ^[A-Za-z0-9_-]{43}$ && "$public" =~ ^[A-Za-z0-9_-]{43}$ ]] || return 1
    printf '%s\n%s\n' "$private" "$public"
}
valid_vlessenc_mode() {
    case "$1" in native|xorpub|random) return 0 ;; *) return 1 ;; esac
}
vlessenc_pair_mode() {
    local mode
    for mode in native xorpub random; do
        if [[ "$1" =~ ^mlkem768x25519plus[.]$mode[.]600s[.][A-Za-z0-9_-]+$ \
            && "$2" =~ ^mlkem768x25519plus[.]$mode[.]0rtt[.][A-Za-z0-9_-]+$ ]]; then
            printf '%s\n' "$mode"
            return 0
        fi
    done
    return 1
}
show_vlessenc_modes() {
    say '  native：原始格式（默认）；适合当前 REALITY 节点。'
    say '  xorpub：在原始格式上隐藏公钥部分。'
    say '  random：隐藏记录头，流量外观看起来更像随机数据。'
    say '  三种模式的客户端与服务端必须一致；切换后需重新导入链接。'
}
generate_vless_encryption_pair() {
    local mode="${1:-native}" output server client
    valid_vlessenc_mode "$mode" || return 1
    output="$($XRAY_BIN vlessenc)" || return 1
    server="$(awk -F '"' '/"decryption":/ {print $4; exit}' <<< "$output")"
    client="$(awk -F '"' '/"encryption":/ {print $4; exit}' <<< "$output")"
    [[ "$server" =~ ^mlkem768x25519plus[.]native[.]600s[.][A-Za-z0-9_-]+$ \
        && "$client" =~ ^mlkem768x25519plus[.]native[.]0rtt[.][A-Za-z0-9_-]+$ ]] || return 1
    # xray vlessenc 默认生成 native；三种模式共用密钥格式，必须同时修改配对的两端。
    server="${server/.native./.$mode.}"
    client="${client/.native./.$mode.}"
    printf '%s\n%s\n' "$server" "$client"
}

write_marker() {
    local tmp
    tmp="$(mktemp "$CONFIG_DIR/.marker.XXXXXX")" || return 1
    if printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
        "$PORT" "$SNI" "$NODE_NAME" "$SERVER_IP" "$PUBLIC_KEY" "$SHORT_ID" "$CLIENT_ENCRYPTION" > "$tmp" \
        && chown root:xray "$tmp" && chmod 640 "$tmp" && mv -f -- "$tmp" "$MARKER"; then
        return 0
    fi
    rm -f -- "$tmp"
    return 1
}

load_metadata() {
    [[ -f "$MARKER" && -f "$CONFIG" ]] || fail '未发现本脚本安装的节点。'
    local lines=()
    mapfile -t lines < "$MARKER"
    PORT="${lines[0]:-}"
    SNI="${lines[1]:-}"
    NODE_NAME="${lines[2]:-}"
    SERVER_IP="${lines[3]:-}"
    PUBLIC_KEY="${lines[4]:-}"
    SHORT_ID="${lines[5]:-}"
    CLIENT_ENCRYPTION="${lines[6]:-none}"
    valid_port "$PORT" || fail '安装记录中的端口无效。'
    valid_host "$SNI" || fail '安装记录中的 SNI 无效。'
    [[ -n "$NODE_NAME" && -n "$SERVER_IP" && -n "$PUBLIC_KEY" && -n "$SHORT_ID" ]] \
        || fail '安装记录不完整。'
    [[ "$CLIENT_ENCRYPTION" == none || "$CLIENT_ENCRYPTION" =~ ^mlkem768x25519plus[.](native|xorpub|random)[.]0rtt[.][A-Za-z0-9_-]+$ ]] \
        || fail '安装记录中的 VLESS Encryption 参数无效。'
}

config_uuid() {
    jq -er '[.inbounds[] | select(.protocol == "vless") | .settings.clients[] | select(.flow == "xtls-rprx-vision") | .id][0]' "$CONFIG"
}

edit_config() {
    local tmp
    tmp="$(mktemp "$CONFIG_DIR/.config.json.XXXXXX")" || return 1
    if jq "$@" "$CONFIG" > "$tmp" && chown root:xray "$tmp" && chmod 640 "$tmp" \
        && mv -f -- "$tmp" "$CONFIG"; then
        return 0
    fi
    rm -f -- "$tmp"
    return 1
}

config_ok() {
    "$XRAY_BIN" run -test -config "$CONFIG" >/dev/null 2>&1
}
service_ok() {
    systemctl is-active --quiet xray && [[ -n "$(ss -H -ltn "sport = :$PORT" 2>/dev/null)" ]]
}
wait_service() {
    local attempt
    for ((attempt = 1; attempt <= ${1:-10}; attempt++)); do
        service_ok && return 0
        sleep 1
    done
    return 1
}

save_manager() {
    local source_file="${BASH_SOURCE[0]}"
    [[ -f "$source_file" && "$source_file" != /dev/fd/* && "$source_file" != /proc/*/fd/* ]] \
        || fail '请先将脚本下载为普通文件后运行，例如 /root/vless-reality-setup.sh；不支持 curl | bash。'
    if [[ ! "$source_file" -ef "$MANAGER" ]]; then
        [[ ! -e "$MANAGER" ]] || fail "$MANAGER 已存在；请先检查该文件，脚本不会覆盖它。"
        install -m 700 -- "$source_file" "$MANAGER"
        MANAGER_COPIED=1
    fi
}
shortcut_is_ours() {
    [[ -f "$SHORTCUT" ]] && grep -qF -- "$SHORTCUT_TAG" "$SHORTCUT" 2>/dev/null
}
ensure_shortcut() {
    local quiet="${1:-}"
    [[ -f "$MANAGER" ]] || return 1
    if [[ -e "$SHORTCUT" || -L "$SHORTCUT" ]]; then
        shortcut_is_ours && return 0
        [[ -n "$quiet" ]] || warn "$SHORTCUT 已被占用，未创建快捷命令。"
        return 1
    fi
    printf '#!/usr/bin/env bash\n%s\nexec bash %s "$@"\n' "$SHORTCUT_TAG" "$MANAGER" > "$SHORTCUT"
    chmod 755 "$SHORTCUT"
}
cmd_name() {
    if shortcut_is_ours; then printf 'vless-reality'; else printf 'bash %s' "$MANAGER"; fi
}

check_install_eligibility() {
    if [[ -f "$MARKER" && -f "$CONFIG" ]]; then
        fail "检测到本脚本已经安装节点，请运行 $(cmd_name) 打开管理菜单。"
    fi
    [[ ! -e "$CONFIG_DIR" && ! -L "$CONFIG_DIR" ]] || fail "$CONFIG_DIR 已存在；为保护现有配置，已停止。"
    [[ ! -e "$SERVICE" && ! -L "$SERVICE" ]] || fail "$SERVICE 已存在；为保护现有服务，已停止。"
    [[ ! -e "$XRAY_BIN" && ! -L "$XRAY_BIN" ]] || fail "$XRAY_BIN 已存在；为保护现有安装，已停止。"
    if command -v systemctl >/dev/null 2>&1 && systemctl cat xray.service >/dev/null 2>&1; then
        fail '检测到已有 xray.service；本脚本不会覆盖现有服务。'
    fi
    [[ ! -e "$LINK_FILE" ]] || fail "$LINK_FILE 已存在；为避免覆盖，已停止。"
    if getent passwd xray >/dev/null 2>&1; then
        fail '系统中已存在 xray 用户；为避免误用或卸载时误删，已停止。'
    fi
    if getent group xray >/dev/null 2>&1; then
        fail '系统中已存在 xray 用户组；为避免误用或卸载时误删，已停止。'
    fi
    return 0
}

purge_node_files() {
    if systemctl is-active --quiet xray; then
        systemctl stop xray >/dev/null 2>&1 || return 1
    fi
    systemctl is-active --quiet xray && return 1
    if systemctl is-enabled --quiet xray; then
        systemctl disable xray >/dev/null 2>&1 || return 1
    fi
    disable_kernel_tfo || return 1
    rm -f -- "$SERVICE" || return 1
    systemctl daemon-reload >/dev/null 2>&1 || return 1
    rm -f -- "$XRAY_BIN" "$LINK_FILE" || return 1
    if getent passwd xray >/dev/null 2>&1; then userdel xray >/dev/null 2>&1 || return 1; fi
    if getent group xray >/dev/null 2>&1; then groupdel xray >/dev/null 2>&1 || return 1; fi
    rm -rf -- "$CONFIG_DIR" || return 1
    return 0
}
# 卸载时只处理脚本创建的文件；目录里新增的其他内容留给管理员。
clean_config_residue() (
    local backup entry unknown
    shopt -s nullglob dotglob
    for backup in "$CONFIG_DIR"/.change-backup.??????; do
        [[ -d "$backup" && ! -L "$backup" ]] || continue
        unknown=0
        for entry in "$backup"/*; do
            case "${entry##*/}" in
                config.json|.vless-reality-owned|tfo.sysctl) ;;
                *) unknown=1 ;;
            esac
        done
        rm -f -- "$backup/config.json" "$backup/.vless-reality-owned" "$backup/tfo.sysctl" || return 1
        if (( unknown )); then
            warn "保留含有其他文件的备份目录：$backup" >&2
        else
            rmdir -- "$backup" || return 1
        fi
    done
    for entry in "$CONFIG_DIR"/.config.json.??????; do
        [[ -f "$entry" && ! -L "$entry" ]] || continue
        rm -f -- "$entry" || return 1
    done
    for entry in "$CONFIG_DIR"/.marker.??????; do
        [[ -f "$entry" && ! -L "$entry" ]] || continue
        rm -f -- "$entry" || return 1
    done
)
# 清理 RealityChecker 安装中断留下的、带有脚本标记的暂存目录。
clean_checker_stage() (
    local dir entry owner file unknown
    shopt -s nullglob dotglob
    for dir in "${CHECKER_BIN%/*}"/.vless-reality-checker-stage.?????? \
        /tmp/vless-reality-checker-csv.??????; do
        [[ -d "$dir" && ! -L "$dir" ]] || continue
        owner="$(stat -c %u -- "$dir")" || return 1
        [[ "$owner" == "$EUID" ]] || { warn "暂存目录不属于当前用户，已保留：$dir" >&2; continue; }
        if [[ ! -f "$dir/.vless-reality-owned" || -L "$dir/.vless-reality-owned" \
            || "$(< "$dir/.vless-reality-owned")" != vless-reality-setup ]]; then
            warn "暂存目录没有本脚本的标记，已保留：$dir" >&2
            continue
        fi
        unknown=0
        for entry in "$dir"/*; do
            case "${entry##*/}" in
                .vless-reality-owned) ;;
                release.json|reality-checker.zip|reality-checker|receipt|normalized.csv)
                    [[ -f "$entry" && ! -L "$entry" ]] || unknown=1 ;;
                *) unknown=1 ;;
            esac
        done
        if (( unknown )); then
            warn "暂存目录含有其他文件，已保留：$dir" >&2
            continue
        fi
        for file in release.json reality-checker.zip reality-checker receipt normalized.csv; do
            entry="$dir/$file"
            [[ -f "$entry" && ! -L "$entry" ]] || continue
            rm -f -- "$entry" || return 1
        done
        rm -f -- "$dir/.vless-reality-owned" || return 1
        rmdir -- "$dir" || return 1
    done
)
# 清理被中断的链接写入或程序升级留下的、当前用户创建的临时文件。
clean_runtime_residue() (
    local entry owner dir file
    shopt -s nullglob
    for entry in "${LINK_FILE}".?????? "${XRAY_BIN%/*}"/.xray-update.??????; do
        [[ -f "$entry" && ! -L "$entry" ]] || continue
        owner="$(stat -c %u -- "$entry")" || return 1
        if [[ "$owner" != "$EUID" ]]; then
            warn "临时文件不属于当前用户，已保留：$entry" >&2
            continue
        fi
        rm -f -- "$entry" || return 1
    done
    for entry in "${TFO_SYSCTL}".??????; do
        [[ -f "$entry" && ! -L "$entry" ]] || continue
        [[ "$(sed -n '1p' "$entry")" == "$TFO_TAG" ]] || continue
        owner="$(stat -c %u -- "$entry")" || return 1
        [[ "$owner" == "$EUID" ]] || continue
        rm -f -- "$entry" || return 1
    done
    for dir in /tmp/vless-reality-install.?????? /tmp/vless-reality-update.?????? /tmp/vless-reality-sni.??????; do
        [[ -d "$dir" && ! -L "$dir" ]] || continue
        owner="$(stat -c %u -- "$dir")" || return 1
        if [[ "$owner" != "$EUID" ]]; then
            warn "临时目录不属于当前用户，已保留：$dir" >&2
            continue
        fi
        if [[ ! -f "$dir/.vless-reality-owned" || -L "$dir/.vless-reality-owned" \
            || "$(< "$dir/.vless-reality-owned")" != vless-reality-setup ]]; then
            warn "临时目录没有本脚本的标记，已保留：$dir" >&2
            continue
        fi
        for file in release.json xray.zip xray xray.old; do
            entry="$dir/$file"
            [[ -f "$entry" && ! -L "$entry" ]] || continue
            rm -f -- "$entry" || return 1
        done
        if [[ "$dir" == /tmp/vless-reality-sni.?????? ]]; then
            for entry in "$dir"/result.* "$dir"/result2.*; do
                [[ -f "$entry" && ! -L "$entry" ]] || continue
                rm -f -- "$entry" || return 1
            done
        fi
        rm -f -- "$dir/.vless-reality-owned" || return 1
        rmdir -- "$dir" 2>/dev/null || warn "临时目录含有其他文件，已保留：$dir" >&2
    done
    clean_checker_stage
)
finish_install() {
    local result=$? cleanup_ok=1
    trap - EXIT
    if (( INSTALL_COMMITTED == 0 )); then
        if (( INSTALL_STARTED )); then
            warn '安装未完成，正在撤销本次创建的服务和文件…' >&2
            if ! purge_node_files; then
                cleanup_ok=0
                warn '自动回滚未完成；已保留管理脚本，请检查 Xray 服务和节点文件。' >&2
            fi
        fi
        if (( MANAGER_COPIED && cleanup_ok )); then rm -f -- "$MANAGER" || true; fi
    fi
    [[ -z "$TEMP_DIR" ]] || rm -rf -- "$TEMP_DIR"
    return "$result"
}

write_config() {
    local uuid="$1" private_key="$2"
    jq -n \
        --arg uuid "$uuid" --arg privateKey "$private_key" --arg shortId "$SHORT_ID" \
        --arg sni "$SNI" --arg decryption "$VLESS_DECRYPTION" --argjson port "$PORT" --argjson tfo "$TFO_ENABLED" '
        {
          log: {loglevel: "warning"},
          inbounds: [{
            listen: "0.0.0.0",
            port: $port,
            protocol: "vless",
            settings: {
              clients: [{id: $uuid, flow: "xtls-rprx-vision", email: "default"}],
              decryption: $decryption
            },
            streamSettings: {
              network: "tcp",
              security: "reality",
              sockopt: {tcpFastOpen: ($tfo == 1)},
              realitySettings: {
                show: false,
                target: ($sni + ":443"),
                xver: 0,
                serverNames: [$sni],
                privateKey: $privateKey,
                shortIds: [$shortId]
              }
            },
            sniffing: {enabled: true, destOverride: ["http", "tls", "quic"], routeOnly: true}
          }],
          outbounds: [{protocol: "freedom", tag: "direct"}, {protocol: "blackhole", tag: "blocked"}]
        }' > "$CONFIG"
    chown root:xray "$CONFIG"
    chmod 640 "$CONFIG"
}

install_node() {
    need_root
    [[ $# -le 6 ]] || fail "用法：$(cmd_name) install [端口] [伪装域名] [节点名称] [TFO:on|off] [VLESS加密:on|off] [模式:native|xorpub|random]"
    [[ -r /etc/os-release ]] || fail '无法识别系统。'
    # shellcheck source=/dev/null
    . /etc/os-release
    [[ "${ID:-}" == debian || "${ID:-}" == ubuntu ]] || fail '这个脚本仅支持 Debian 和 Ubuntu。'
    check_install_eligibility
    local interactive=0 raw_port="${1:-}" answer default_name auto_sni=0 tfo_choice="${4:-off}" enc_choice="${5:-off}" enc_mode="${6:-native}" checker_choice=0
    default_name="Reality-$(hostname -s)"

    if [[ -z "$raw_port" ]]; then
        [[ -t 0 ]] || fail '非交互运行时，请指定端口、伪装域名和节点名称。'
        interactive=1
        choose_port
        raw_port="$PORT"
    fi
    valid_port "$raw_port" || fail '端口必须是 1–65535 的数字。'
    PORT="$((10#$raw_port))"
    port_free "$PORT" || fail "本机 TCP $PORT 已被占用。"

    SNI="${2:-}"
    if [[ -z "$SNI" ]]; then
        [[ -t 0 ]] || fail '非交互运行时，请指定伪装域名或 auto。'
        interactive=1
        read -r -p 'REALITY 伪装域名（直接回车默认选实测延迟最低的域名，或输入自定义域名）：' SNI || fail '已取消输入。'
        SNI="${SNI:-auto}"
    fi
    SNI="${SNI,,}"
    if [[ "$SNI" == auto ]]; then
        auto_sni=1
        ensure_dependencies
        select_fastest_sni || fail '候选域名均不可用，请手动指定可从 VPS 访问的伪装域名。'
    else
        valid_host "$SNI" || fail '伪装域名格式不正确；只填域名，不要带 https://、端口或路径。'
    fi

    NODE_NAME="${3:-$default_name}"
    if (( interactive )); then
        read -r -p "请输入节点名称（直接回车使用 ${default_name}）：" answer || fail '已取消输入。'
        [[ -z "$answer" ]] || NODE_NAME="$answer"
    fi
    valid_node_name "$NODE_NAME" || fail '节点名称不能为空、不能超过 64 个字符或包含换行。'

    if (( interactive )); then
        if confirm '是否开启 TCP Fast Open？默认关闭 [y/N]：'; then tfo_choice=on; fi
    fi
    case "$tfo_choice" in
        on) TFO_ENABLED=1 ;;
        off) TFO_ENABLED=0 ;;
        *) fail 'TFO 参数必须为 on 或 off。' ;;
    esac
    if (( interactive )) && confirm '是否开启 VLESS Encryption？默认关闭 [y/N]：'; then
        enc_choice=on
    fi
    case "$enc_choice" in on|off) ;; *) fail 'VLESS Encryption 参数必须为 on 或 off。' ;; esac
    if [[ "$enc_choice" == on ]]; then
        if (( interactive )); then
            show_vlessenc_modes
            read -r -p '选择 VLESS Encryption 模式（直接回车使用 native）：' answer || fail '已取消输入。'
            enc_mode="${answer:-native}"
        fi
        valid_vlessenc_mode "$enc_mode" || fail '模式只能是 native、xorpub 或 random。'
    elif [[ $# -ge 6 ]]; then
        fail '指定 VLESS Encryption 模式时，必须同时开启 VLESS Encryption。'
    fi
    if (( interactive )) && confirm '是否安装 RealityChecker 检测工具？默认不安装 [y/N]：'; then
        checker_choice=1
    fi

    if (( interactive )); then
        say
        step '—————————— 确认安装信息 ——————————'
        say "  协议：VLESS + REALITY + Vision"
        say "  端口：TCP $PORT"
        if (( auto_sni )); then say "  SNI： $SNI:443（自动优选）"; else say "  SNI： $SNI:443"; fi
        say "  名称：$NODE_NAME"
        if (( TFO_ENABLED )); then say '  TFO： 开启'; else say '  TFO： 关闭'; fi
        if [[ "$enc_choice" == on ]]; then say "  VLESS Encryption：开启（$enc_mode）"; else say '  VLESS Encryption：关闭'; fi
        if (( checker_choice )); then say '  RealityChecker： 安装'; else say '  RealityChecker： 不安装'; fi
        warn "  请确认云安全组已放行 TCP ${PORT}，无需开放 TCP 80"
        step '————————————————————————————————'
        confirm '开始安装？[y/N]：' || { say '已取消安装。'; return 0; }
    fi

    step '[1/5] 检查系统和安装环境…'
    ensure_dependencies
    check_install_eligibility
    port_free "$PORT" || fail "本机 TCP $PORT 已被占用。"
    SERVER_IP="$(public_ipv4)" || fail '无法查询此 VPS 的公网 IPv4。'
    step '[2/5] 验证 REALITY 伪装站点…'
    target_tls_ok "$SNI" || fail "$SNI:443 未通过 TLS 1.3 与证书校验，请更换可从本机访问的伪装域名。"
    ok "伪装站点可用：$SNI:443（TLS 1.3）"

    trap finish_install EXIT
    save_manager
    TEMP_DIR="$(mktemp -d /tmp/vless-reality-install.XXXXXX)"
    printf 'vless-reality-setup\n' > "$TEMP_DIR/.vless-reality-owned"
    INSTALL_STARTED=1
    step '[3/5] 下载并校验 Xray-core 官方稳定版…'
    local asset archive
    asset="$(arch_asset)"
    archive="$TEMP_DIR/xray.zip"
    fetch_release_metadata latest "$asset"
    say "下载 Xray ${RELEASE_VERSION}（${asset}）…"
    download_verified_release "$archive"
    unzip -q "$archive" xray -d "$TEMP_DIR"
    [[ -x "$TEMP_DIR/xray" || -f "$TEMP_DIR/xray" ]] || fail '安装包中没有找到 xray 程序。'
    install -m 755 "$TEMP_DIR/xray" "$XRAY_BIN"
    if [[ "$enc_choice" == on ]]; then
        local enc_pair=()
        mapfile -t enc_pair < <(generate_vless_encryption_pair "$enc_mode")
        (( ${#enc_pair[@]} == 2 )) || fail '生成 VLESS Encryption 配对参数失败；安装将回滚。'
        VLESS_DECRYPTION="${enc_pair[0]}"
        CLIENT_ENCRYPTION="${enc_pair[1]}"
    fi

    step '[4/5] 生成 UUID、REALITY 密钥和配置…'
    if ! getent group xray >/dev/null 2>&1; then groupadd --system xray; fi
    if ! getent passwd xray >/dev/null 2>&1; then
        useradd --system --gid xray --home-dir /nonexistent --shell /usr/sbin/nologin xray
    fi
    install -d -o root -g xray -m 750 "$CONFIG_DIR"
    local uuid key_lines private_key
    uuid="$($XRAY_BIN uuid)"
    mapfile -t key_lines < <(generate_reality_keys)
    (( ${#key_lines[@]} == 2 )) || fail 'REALITY 密钥生成失败。'
    private_key="${key_lines[0]}"
    PUBLIC_KEY="${key_lines[1]}"
    SHORT_ID="$(openssl rand -hex 8)"
    write_config "$uuid" "$private_key"
    write_marker
    if (( TFO_ENABLED )); then
        enable_kernel_tfo || fail '开启内核 TCP Fast Open 失败；安装将回滚。'
    fi
    config_ok || fail 'Xray 配置校验失败。'

    cat > "$SERVICE" <<'EOF'
[Unit]
Description=Xray VLESS REALITY Service
Documentation=https://github.com/XTLS/Xray-core
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=xray
Group=xray
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=3s
LimitNOFILE=1048576
PrivateTmp=true
ProtectHome=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 "$SERVICE"

    step '[5/5] 启动服务并检查监听端口…'
    systemctl daemon-reload
    systemctl enable --now xray
    wait_service 10 || fail "Xray 未正常监听 TCP $PORT；请查看 journalctl -u xray。"
    show_node
    ensure_shortcut || true
    INSTALL_COMMITTED=1
    trap - EXIT
    rm -rf -- "$TEMP_DIR"
    TEMP_DIR=''
    ok "安装完成：Xray ${RELEASE_VERSION} 正在监听 TCP ${PORT}。"
    warn "请确认云安全组已放行 TCP ${PORT}。导入链接包含 UUID，请勿公开分享。"
    if (( checker_choice )); then
        if ! install_checker; then
            warn '节点已安装，但 RealityChecker 安装失败；稍后可从菜单第 18 项重试。' >&2
        fi
    fi
}

show_node() {
    need_root
    load_metadata
    local uuid label link tmp enc_param
    uuid="$(config_uuid)" || fail '无法从配置读取 UUID。'
    label="$(jq -rn --arg v "$NODE_NAME" '$v | @uri')" || return 1
    enc_param="$(jq -rn --arg v "$CLIENT_ENCRYPTION" '$v | @uri')" || return 1
    link="vless://${uuid}@${SERVER_IP}:${PORT}?encryption=${enc_param}&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#${label}"
    tmp="$(mktemp "${LINK_FILE}.XXXXXX")" || return 1
    if ! printf '%s\n' "$link" > "$tmp" || ! chmod 600 "$tmp" || ! mv -f -- "$tmp" "$LINK_FILE"; then
        rm -f -- "$tmp"
        warn '保存客户端导入链接失败。' >&2
        return 1
    fi
    say
    say 'VLESS 导入链接：'
    printf '%s%s%s\n' "$BOLD" "$link" "$RESET"
    say
    say "已保存到：$LINK_FILE"
}

status_node() {
    need_root
    load_metadata
    local state current_ip version flow server_enc enc_mode
    state="$(systemctl is-active xray 2>/dev/null || true)"
    version="$(installed_version)"
    say "服务状态：$state"
    say "Xray 版本：${version:-未知}"
    say "监听地址：${SERVER_IP}:${PORT}/TCP"
    say "REALITY SNI：${SNI}:443"
    flow="$(jq -r '[.inbounds[] | select(.protocol == "vless") | .settings.clients[0].flow][0] // empty' "$CONFIG" 2>/dev/null || true)"
    if [[ "$flow" == xtls-rprx-vision ]]; then
        ok 'Vision flow：xtls-rprx-vision'
    else
        warn "Vision flow：${flow:-未配置}"
    fi
    server_enc="$(jq -r '[.inbounds[] | select(.protocol == "vless") | .settings.decryption][0] // "none"' "$CONFIG" 2>/dev/null || true)"
    if [[ "$server_enc" == none && "$CLIENT_ENCRYPTION" == none ]]; then
        say 'VLESS Encryption：未开启'
    elif enc_mode="$(vlessenc_pair_mode "$server_enc" "$CLIENT_ENCRYPTION")"; then
        ok "VLESS Encryption：已开启（$enc_mode，服务端与客户端参数均已记录）"
    else
        warn 'VLESS Encryption：服务端与客户端参数不一致，请检查配置和安装记录。'
    fi
    if config_ok; then ok '配置检查：通过'; else warn '配置检查：失败'; fi
    if [[ -n "$(ss -H -ltn "sport = :$PORT" 2>/dev/null)" ]]; then ok '端口监听：正常'; else warn '端口监听：未发现'; fi
    current_ip="$(public_ipv4 || true)"
    if [[ -n "$current_ip" && "$current_ip" != "$SERVER_IP" ]]; then
        warn "公网 IPv4 已变化：当前 $current_ip，链接中仍为 $SERVER_IP；请运行 $(cmd_name) refresh-ip。"
    fi
    if target_tls_ok "$SNI"; then ok '伪装站点：TLS 1.3 正常'; else warn '伪装站点：当前验证失败'; fi
    if config_tfo_enabled && kernel_tfo_server; then
        ok 'TCP Fast Open：已开启（Xray 与内核均生效）'
    elif config_tfo_enabled || tfo_sysctl_is_ours; then
        warn "TCP Fast Open：设置不一致，可运行 $(cmd_name) tfo on 修复或 tfo off 关闭。"
    else
        say 'TCP Fast Open：未开启'
    fi
}

backup_state() {
    local dir="$1"
    cp -a -- "$CONFIG" "$MARKER" "$dir/"
}
restore_state() {
    local dir="$1" was_active="$2"
    cp -a -- "$dir/config.json" "$CONFIG" || return 1
    cp -a -- "$dir/.vless-reality-owned" "$MARKER" || return 1
    if (( was_active )); then
        systemctl restart xray >/dev/null 2>&1 && wait_service 10 || return 1
    fi
    return 0
}
restore_tfo_snapshot() {
    local backup="$1" old_kernel="$2" old_foreign="$3"
    if [[ -f "$backup/tfo.sysctl" ]]; then
        cp -a -- "$backup/tfo.sysctl" "$TFO_SYSCTL" || return 1
    elif (( old_foreign )); then
        :
    elif tfo_sysctl_is_ours; then
        rm -f -- "$TFO_SYSCTL" || return 1
    elif [[ -e "$TFO_SYSCTL" || -L "$TFO_SYSCTL" ]]; then
        return 1
    fi
    sysctl -q -w "net.ipv4.tcp_fastopen=$old_kernel" >/dev/null
}
commit_change() {
    local backup="$1" old_port="$2" description="$3" was_active="$4"
    if config_ok && { (( was_active == 0 )) || { systemctl restart xray && wait_service 10; }; }; then
        if show_node; then
            rm -rf -- "$backup"
            ok "$description"
            return 0
        fi
    fi
    PORT="$old_port"
    if ! restore_state "$backup" "$was_active"; then
        fail "恢复旧配置或服务失败，备份保留在 $backup；请立即检查服务状态。"
    fi
    rm -rf -- "$backup"
    fail '修改后的配置启动或链接保存失败，已恢复原配置。'
}

tfo_apply() {
    need_root
    [[ $# -eq 1 ]] || fail "用法：$(cmd_name) tfo [on|off]"
    load_metadata
    need_command sysctl
    local action="${1:-}" backup old_kernel was_active=0 changed=1 old_foreign=0 rollback_ok=1
    case "$action" in
        on)
            if config_tfo_enabled && kernel_tfo_server && tfo_sysctl_is_ours; then
                ok 'TCP Fast Open 已开启。'
                return 0
            fi
            ;;
        off)
            if ! config_tfo_enabled && ! tfo_sysctl_is_ours; then ok 'TCP Fast Open 已关闭。'; return 0; fi
            ;;
        *) fail "用法：$(cmd_name) tfo [on|off]" ;;
    esac
    old_kernel="$(kernel_tfo_value)" || fail '无法读取内核 TCP Fast Open 参数。'
    if [[ -e "$TFO_SYSCTL" || -L "$TFO_SYSCTL" ]] && ! tfo_sysctl_is_ours; then old_foreign=1; fi
    backup="$(mktemp -d "$CONFIG_DIR/.change-backup.XXXXXX")" || fail '无法创建配置备份。'
    backup_state "$backup" || fail "备份节点配置失败，备份保留在 $backup。"
    if tfo_sysctl_is_ours; then
        cp -a -- "$TFO_SYSCTL" "$backup/tfo.sysctl" || fail "备份 TFO 设置失败，备份保留在 $backup。"
    fi
    if systemctl is-active --quiet xray; then was_active=1; fi
    if (( was_active )); then
        warn '即将重启 Xray；如果当前 SSH 经过此节点，连接可能中断。请使用 VPS 直连 SSH 操作。'
    fi
    if [[ "$action" == on ]]; then
        enable_kernel_tfo || changed=0
        if (( changed )); then
            edit_config '(.inbounds[] | select(.protocol == "vless") | .streamSettings.sockopt.tcpFastOpen) = true' || changed=0
        fi
    else
        edit_config '(.inbounds[] | select(.protocol == "vless") | .streamSettings.sockopt.tcpFastOpen) = false' || changed=0
        if (( changed )); then disable_kernel_tfo || changed=0; fi
    fi
    if (( changed )) && config_ok \
        && { (( was_active == 0 )) || { systemctl restart xray && wait_service 10; }; }; then
        rm -rf -- "$backup"
        if [[ "$action" == on ]]; then
            ok "TCP Fast Open 已开启（内核值 $(kernel_tfo_value)）。"
        else
            ok 'TCP Fast Open 已关闭；本脚本修改的内核设置已恢复。'
        fi
        say '客户端若支持 TFO，还需要在客户端单独开启。'
        return 0
    fi
    restore_tfo_snapshot "$backup" "$old_kernel" "$old_foreign" || rollback_ok=0
    restore_state "$backup" "$was_active" || rollback_ok=0
    if (( rollback_ok == 0 )); then
        fail "TFO 修改失败且回滚未完成，备份保留在 $backup；请检查 Xray 服务和内核参数。"
    fi
    rm -rf -- "$backup"
    fail 'TFO 修改或验证失败，已恢复原配置。'
}

tfo_node() {
    need_root
    [[ $# -le 1 ]] || fail "用法：$(cmd_name) tfo [on|off]"
    load_metadata
    local action="${1:-}" script_path unit
    if [[ -z "$action" ]]; then
        if config_tfo_enabled && kernel_tfo_server; then
            say 'TCP Fast Open：已开启'
            [[ -t 0 ]] || return 0
            confirm '是否关闭 TCP Fast Open？[y/N]：' || { say '未修改。'; return 0; }
            action=off
        else
            say 'TCP Fast Open：未开启'
            [[ -t 0 ]] || return 0
            confirm '是否开启 TCP Fast Open？默认关闭 [y/N]：' || { say '未修改。'; return 0; }
            action=on
        fi
    fi
    case "$action" in on|off) ;; *) fail "用法：$(cmd_name) tfo [on|off]" ;; esac
    need_command systemd-run
    need_command readlink
    script_path="$(readlink -f -- "$SCRIPT_PATH")" || fail '无法找到当前管理脚本。'
    [[ -f "$script_path" && -r "$script_path" ]] || fail '当前管理脚本不是可读取的普通文件。'
    unit='vless-reality-tfo'
    warn '切换 TFO 将重启 Xray；如果 SSH 经过此节点，连接可能中断。后台任务会继续执行。'
    say "后台任务：$unit；重连后可运行 $(cmd_name) status 查看结果。"
    if systemd-run --quiet --wait --collect --unit="$unit" \
        --property=SyslogIdentifier=vless-reality-tfo \
        /bin/bash "$script_path" __tfo-apply "$action"; then
        if [[ "$action" == on ]] && config_tfo_enabled && kernel_tfo_server; then
            ok 'TCP Fast Open 已开启。'
        elif [[ "$action" == off ]] && ! config_tfo_enabled && ! tfo_sysctl_is_ours; then
            ok 'TCP Fast Open 已关闭。'
        else
            fail "后台任务已结束，但 TFO 状态未达到预期；请查看 journalctl -u $unit。"
        fi
    else
        fail "TFO 后台任务失败；请查看 journalctl -u $unit。"
    fi
}

vlessenc_apply() {
    need_root
    [[ $# -ge 1 && $# -le 2 ]] || fail '用法：vlessenc on [native|xorpub|random] 或 vlessenc off'
    load_metadata
    local action="$1" mode="${2:-}" current_mode='' backup was_active=0 old_port="$PORT" server_enc pair=()
    case "$action" in on|off) ;; *) fail '用法：vlessenc on [native|xorpub|random] 或 vlessenc off' ;; esac
    [[ "$action" == on || -z "$mode" ]] || fail '关闭加密时无需指定模式。'
    server_enc="$(jq -r '[.inbounds[] | select(.protocol == "vless") | .settings.decryption][0] // "none"' "$CONFIG")" \
        || fail '无法读取服务端 VLESS Encryption 状态。'
    current_mode="$(vlessenc_pair_mode "$server_enc" "$CLIENT_ENCRYPTION" || true)"
    if [[ "$action" == on ]]; then
        mode="${mode:-${current_mode:-native}}"
        valid_vlessenc_mode "$mode" || fail '模式只能是 native、xorpub 或 random。'
    fi
    if [[ "$action" == on && "$current_mode" == "$mode" ]]; then
        ok "VLESS Encryption 已开启（$mode）。"; return 0
    fi
    if [[ "$action" == off && "$server_enc" == none && "$CLIENT_ENCRYPTION" == none ]]; then
        ok 'VLESS Encryption 已关闭。'; return 0
    fi
    if [[ "$action" == on ]]; then
        mapfile -t pair < <(generate_vless_encryption_pair "$mode")
        (( ${#pair[@]} == 2 )) || fail 'Xray 无法生成 VLESS Encryption 配对参数。'
        VLESS_DECRYPTION="${pair[0]}"
        CLIENT_ENCRYPTION="${pair[1]}"
    else
        VLESS_DECRYPTION=none
        CLIENT_ENCRYPTION=none
    fi
    backup="$(mktemp -d "$CONFIG_DIR/.change-backup.XXXXXX")" || fail '无法创建配置备份。'
    backup_state "$backup" || fail "备份节点配置失败，备份保留在 $backup。"
    if systemctl is-active --quiet xray; then was_active=1; fi
    if ! edit_config --arg decryption "$VLESS_DECRYPTION" \
        '(.inbounds[] | select(.protocol == "vless") | .settings.decryption) = $decryption' \
        || ! write_marker; then
        restore_state "$backup" "$was_active" || fail "恢复旧配置失败，备份保留在 $backup。"
        rm -rf -- "$backup"
        fail '写入 VLESS Encryption 配置失败，已恢复。'
    fi
    if config_ok && { (( was_active == 0 )) || { systemctl restart xray && wait_service 10; }; } \
        && (show_node >/dev/null); then
        rm -rf -- "$backup"
        if [[ "$action" == on ]]; then ok "VLESS Encryption 已开启（$mode）。"; else ok 'VLESS Encryption 已关闭。'; fi
        return 0
    fi
    PORT="$old_port"
    restore_state "$backup" "$was_active" || fail "VLESS Encryption 修改失败，回滚未完成；备份保留在 $backup。"
    rm -rf -- "$backup"
    fail 'VLESS Encryption 修改失败，已恢复原配置。'
}
vlessenc_node() {
    need_root
    [[ $# -le 2 ]] || fail "用法：$(cmd_name) vlessenc on [native|xorpub|random] 或 vlessenc off"
    load_metadata
    local action="${1:-}" mode="${2:-}" current_mode='' answer server_enc script_path unit='vless-reality-enc'
    server_enc="$(jq -r '[.inbounds[] | select(.protocol == "vless") | .settings.decryption][0] // "none"' "$CONFIG")" \
        || fail '无法读取服务端 VLESS Encryption 状态。'
    current_mode="$(vlessenc_pair_mode "$server_enc" "$CLIENT_ENCRYPTION" || true)"
    if [[ -z "$action" ]]; then
        if [[ -n "$current_mode" ]]; then
            say "VLESS Encryption：已开启（$current_mode）"
            [[ -t 0 ]] || return 0
            show_vlessenc_modes
            read -r -p '输入新模式切换；输入 off 关闭；直接回车不修改：' answer || fail '已取消输入。'
            [[ -n "$answer" ]] || { say '未修改。'; return 0; }
            if [[ "$answer" == off ]]; then action=off; else action=on; mode="$answer"; fi
        else
            say 'VLESS Encryption：未开启'
            [[ -t 0 ]] || return 0
            confirm '是否开启 VLESS Encryption？默认关闭 [y/N]：' || { say '未修改。'; return 0; }
            action=on
            show_vlessenc_modes
            read -r -p '选择模式（直接回车使用 native）：' answer || fail '已取消输入。'
            mode="${answer:-native}"
        fi
    fi
    case "$action" in on|off) ;; *) fail "用法：$(cmd_name) vlessenc on [native|xorpub|random] 或 vlessenc off" ;; esac
    if [[ "$action" == on ]]; then
        mode="${mode:-${current_mode:-native}}"
        valid_vlessenc_mode "$mode" || fail '模式只能是 native、xorpub 或 random。'
        if [[ "$mode" == "$current_mode" ]]; then ok "VLESS Encryption 已开启（$mode）。"; return 0; fi
    elif [[ -n "$mode" ]]; then
        fail '关闭加密时无需指定模式。'
    elif [[ "$server_enc" == none && "$CLIENT_ENCRYPTION" == none ]]; then
        ok 'VLESS Encryption 已关闭。'; return 0
    fi
    need_command systemd-run
    need_command readlink
    script_path="$(readlink -f -- "$SCRIPT_PATH")" || fail '无法找到当前管理脚本。'
    [[ -f "$script_path" && -r "$script_path" ]] || fail '当前管理脚本不是可读取的普通文件。'
    warn '切换 VLESS Encryption 将重启 Xray，旧客户端链接会失效；建议使用 VPS 直连 SSH 或服务商控制台，后台任务会完成修改或回滚。'
    say "后台任务：$unit；若连接中断，重连后运行 $(cmd_name) status 查看结果。"
    systemd-run --quiet --wait --collect --unit="$unit" \
        --property=SyslogIdentifier=vless-reality-enc \
        /bin/bash "$script_path" __vlessenc-apply "$action" "$mode" \
        || fail "VLESS Encryption 后台任务失败；请查看 journalctl -u $unit。"
    load_metadata
    server_enc="$(jq -r '[.inbounds[] | select(.protocol == "vless") | .settings.decryption][0] // "none"' "$CONFIG")"
    if [[ "$action" == on && "$(vlessenc_pair_mode "$server_enc" "$CLIENT_ENCRYPTION" || true)" == "$mode" ]] \
        || [[ "$action" == off && "$server_enc" == none && "$CLIENT_ENCRYPTION" == none ]]; then
        show_node
    else
        fail "后台任务已结束，但加密状态未达到预期；请查看 journalctl -u $unit。"
    fi
}

change_port() {
    need_root
    [[ $# -le 1 ]] || fail "用法：$(cmd_name) port [新端口]"
    load_metadata
    local raw="${1:-}" old_port="$PORT" backup was_active=0
    if [[ -z "$raw" ]]; then
        [[ -t 0 ]] || fail '非交互运行时请指定新端口。'
        read -r -p "当前端口 $PORT，请输入新端口：" raw || fail '已取消输入。'
    fi
    valid_port "$raw" || fail '端口必须是 1–65535 的数字。'
    PORT="$((10#$raw))"
    (( PORT != old_port )) || fail '新端口与当前端口相同。'
    port_free "$PORT" || fail "本机 TCP $PORT 已被占用。"
    if systemctl is-active --quiet xray; then was_active=1; fi
    backup="$(mktemp -d "$CONFIG_DIR/.change-backup.XXXXXX")"
    backup_state "$backup"
    if ! edit_config --argjson port "$PORT" '(.inbounds[] | select(.protocol == "vless") | .port) = $port' \
        || ! write_marker; then
        PORT="$old_port"
        restore_state "$backup" "$was_active" || fail "恢复旧配置或服务失败，备份保留在 $backup。"
        rm -rf -- "$backup"
        fail '修改端口文件失败，已恢复原配置。'
    fi
    commit_change "$backup" "$old_port" "端口已改为 TCP $PORT；请放行新端口，确认可用后再关闭旧端口 $old_port。" "$was_active"
}

change_sni() {
    need_root
    [[ $# -le 1 ]] || fail "用法：$(cmd_name) sni [新域名]"
    load_metadata
    local new="${1:-}" old_port="$PORT" old_sni="$SNI" backup was_active=0 auto_sni=0
    if [[ -z "$new" ]]; then
        [[ -t 0 ]] || fail '非交互运行时请指定新伪装域名。'
        read -r -p "当前 SNI $SNI，请输入新域名（回车自动优选）：" new || fail '已取消输入。'
        new="${new:-auto}"
    fi
    new="${new,,}"
    if [[ "$new" == auto ]]; then
        auto_sni=1
        select_fastest_sni || fail '候选域名均不可用，请手动指定伪装域名。'
        new="$SNI"
        SNI="$old_sni"
    else
        valid_host "$new" || fail '伪装域名格式不正确。'
    fi
    if [[ "$new" == "$SNI" ]]; then
        if (( auto_sni )); then ok "当前域名 $SNI 已是本次测试的最优选项，无需修改。"; return 0; fi
        fail '新域名与当前域名相同。'
    fi
    if (( ! auto_sni )); then
        target_tls_ok "$new" || fail "$new:443 未通过 TLS 1.3 与证书校验。"
    fi
    if systemctl is-active --quiet xray; then was_active=1; fi
    backup="$(mktemp -d "$CONFIG_DIR/.change-backup.XXXXXX")"
    backup_state "$backup"
    SNI="$new"
    if ! edit_config --arg sni "$SNI" \
        '(.inbounds[] | select(.protocol == "vless") | .streamSettings.realitySettings.target) = ($sni + ":443") |
         (.inbounds[] | select(.protocol == "vless") | .streamSettings.realitySettings.serverNames) = [$sni]' \
        || ! write_marker; then
        restore_state "$backup" "$was_active" || fail "恢复旧配置或服务失败，备份保留在 $backup。"
        rm -rf -- "$backup"
        fail '修改 SNI 文件失败，已恢复原配置。'
    fi
    commit_change "$backup" "$old_port" "REALITY 伪装域名已改为 $SNI。" "$was_active"
}

change_uuid() {
    need_root
    load_metadata
    local new old_port="$PORT" backup was_active=0
    new="$($XRAY_BIN uuid)"
    if systemctl is-active --quiet xray; then was_active=1; fi
    backup="$(mktemp -d "$CONFIG_DIR/.change-backup.XXXXXX")"
    backup_state "$backup"
    edit_config --arg id "$new" \
        '(.inbounds[] | select(.protocol == "vless") | .settings.clients[] | select(.flow == "xtls-rprx-vision") | .id) = $id' \
        || { restore_state "$backup" "$was_active" || fail "恢复失败，备份保留在 $backup。"; fail '写入配置失败。'; }
    commit_change "$backup" "$old_port" 'UUID 已重新生成，旧链接立即失效。' "$was_active"
}

rotate_keys() {
    need_root
    load_metadata
    local key_lines private old_port="$PORT" backup was_active=0
    mapfile -t key_lines < <(generate_reality_keys)
    (( ${#key_lines[@]} == 2 )) || fail 'REALITY 密钥生成失败。'
    private="${key_lines[0]}"
    PUBLIC_KEY="${key_lines[1]}"
    SHORT_ID="$(openssl rand -hex 8)"
    if systemctl is-active --quiet xray; then was_active=1; fi
    backup="$(mktemp -d "$CONFIG_DIR/.change-backup.XXXXXX")"
    backup_state "$backup"
    if ! edit_config --arg private "$private" --arg sid "$SHORT_ID" \
        '(.inbounds[] | select(.protocol == "vless") | .streamSettings.realitySettings.privateKey) = $private |
         (.inbounds[] | select(.protocol == "vless") | .streamSettings.realitySettings.shortIds) = [$sid]' \
        || ! write_marker; then
        restore_state "$backup" "$was_active" || fail "恢复旧配置或服务失败，备份保留在 $backup。"
        rm -rf -- "$backup"
        fail '修改 REALITY 密钥文件失败，已恢复原配置。'
    fi
    commit_change "$backup" "$old_port" 'REALITY 密钥和 Short ID 已轮换，旧链接立即失效。' "$was_active"
}

rename_node() {
    need_root
    [[ $# -le 1 ]] || fail "用法：$(cmd_name) rename [新名称]"
    load_metadata
    local new="${1:-}"
    if [[ -z "$new" ]]; then
        [[ -t 0 ]] || fail '非交互运行时请指定新名称。'
        read -r -p "当前名称 $NODE_NAME，请输入新名称：" new || fail '已取消输入。'
    fi
    valid_node_name "$new" || fail '名称不能为空、不能超过 64 个字符或包含换行。'
    NODE_NAME="$new"
    write_marker
    ok '节点名称已修改，无需重启服务。'
    show_node
}

refresh_ip() {
    need_root
    load_metadata
    local ip
    ip="$(public_ipv4)" || fail '无法查询当前公网 IPv4。'
    if [[ "$ip" == "$SERVER_IP" ]]; then ok "公网 IPv4 未变化：$ip"; return 0; fi
    SERVER_IP="$ip"
    write_marker
    ok "链接中的服务器地址已更新为 $SERVER_IP，服务无需重启。"
    show_node
}

update_xray() {
    need_root
    load_metadata
    ensure_dependencies
    local current asset archive candidate backup was_active=0
    current="$(installed_version)"
    TEMP_DIR="$(mktemp -d /tmp/vless-reality-update.XXXXXX)"
    printf 'vless-reality-setup\n' > "$TEMP_DIR/.vless-reality-owned"
    trap '[[ -z "$TEMP_BIN" ]] || rm -f -- "$TEMP_BIN"; [[ -z "$TEMP_DIR" ]] || rm -rf -- "$TEMP_DIR"' EXIT
    asset="$(arch_asset)"
    archive="$TEMP_DIR/xray.zip"
    fetch_release_metadata latest "$asset"
    if [[ "$current" == "$RELEASE_VERSION" ]]; then
        ok "当前已是官方最新稳定版：$current"
        return 0
    fi
    if [[ "$current" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] \
        && dpkg --compare-versions "$current" gt "$RELEASE_VERSION"; then
        warn "当前版本 $current 高于官方最新稳定版 ${RELEASE_VERSION}，未执行降级。"
        return 0
    fi
    say "准备从 ${current:-未知} 升级到 ${RELEASE_VERSION}…"
    download_verified_release "$archive"
    unzip -q "$archive" xray -d "$TEMP_DIR"
    candidate="$TEMP_DIR/xray"
    chmod 755 "$candidate"
    "$candidate" run -test -config "$CONFIG" >/dev/null || fail '新版 Xray 不接受当前配置，已停止升级。'
    backup="$TEMP_DIR/xray.old"
    cp -a -- "$XRAY_BIN" "$backup"
    if systemctl is-active --quiet xray; then was_active=1; fi
    TEMP_BIN="$(mktemp "${XRAY_BIN%/*}/.xray-update.XXXXXX")"
    install -m 755 "$candidate" "$TEMP_BIN" || fail '准备新版 Xray 程序失败，旧版本未修改。'
    mv -f -- "$TEMP_BIN" "$XRAY_BIN" || fail '替换 Xray 程序失败，旧版本未修改。'
    TEMP_BIN=''
    if (( was_active == 0 )) || { systemctl restart xray && wait_service 10; }; then
        ok "Xray 已升级到 ${RELEASE_VERSION}。"
        return 0
    fi
    TEMP_BIN="$(mktemp "${XRAY_BIN%/*}/.xray-update.XXXXXX")"
    if ! install -m 755 "$backup" "$TEMP_BIN" || ! mv -f -- "$TEMP_BIN" "$XRAY_BIN"; then
        trap - EXIT
        rm -f -- "$TEMP_BIN"
        fail "升级失败且自动恢复程序失败；旧版本备份保留在 $backup，请手动恢复。"
    fi
    TEMP_BIN=''
    if ! systemctl restart xray || ! wait_service 10; then
        trap - EXIT
        fail "旧版程序已恢复，但服务仍无法启动；备份保留在 $backup，请检查日志。"
    fi
    fail "升级后服务未正常运行，已恢复 Xray ${current:-旧版本}。"
}

start_node() {
    need_root; load_metadata
    if systemctl is-active --quiet xray; then ok '服务已在运行。'; return 0; fi
    systemctl start xray || fail '启动失败，请查看日志。'
    wait_service 10 || fail '服务已启动但端口未正常监听，请查看日志。'
    ok '服务已启动。'
}
stop_node() {
    need_root; load_metadata
    if ! systemctl is-active --quiet xray; then ok '服务已经停止。'; return 0; fi
    if [[ -t 0 ]] && ! confirm '停止后节点将无法连接，确定停止？[y/N]：'; then say '已取消。'; return 0; fi
    systemctl stop xray
    ok '服务已停止。'
}
restart_node() {
    need_root; load_metadata
    config_ok || fail '配置检查失败，未重启。'
    systemctl restart xray || fail '重启失败，请查看日志。'
    wait_service 10 || fail '重启后端口未正常监听，请查看日志。'
    ok '服务已重启。'
}
log_node() {
    need_root
    local arg="${1:-50}"
    if [[ "$arg" == -f ]]; then journalctl -u xray -f --no-pager; return 0; fi
    [[ "$arg" =~ ^[0-9]{1,5}$ ]] || fail '行数必须是数字，例如 log 100。'
    journalctl -u xray -n "$arg" --no-pager
}

uninstall_node() {
    need_root
    if [[ ! -e "$MARKER" && ! -L "$MARKER" ]]; then
        [[ ! -e "$SERVICE" && ! -e "$XRAY_BIN" && ! -e "$CONFIG" && ! -e "$LINK_FILE" ]] \
            || fail '安装记录已不存在，但仍发现 Xray 文件；无法确认归属，已停止。'
        if systemctl is-active --quiet xray || getent passwd xray >/dev/null 2>&1 \
            || getent group xray >/dev/null 2>&1; then
            fail '安装记录已不存在，但仍发现 Xray 服务或账号；无法确认归属，已停止。'
        fi
        if [[ -e "$MANAGER" || -L "$MANAGER" ]]; then
            if [[ ! -f "$MANAGER" || -L "$MANAGER" ]] \
                || ! grep -qF 'VLESS + REALITY + Vision 节点管理脚本' "$MANAGER"; then
                fail '管理脚本文件无法确认归属，未删除。'
            fi
        fi
        if [[ -e "$SHORTCUT" || -L "$SHORTCUT" ]]; then
            shortcut_is_ours || fail '快捷命令不属于本脚本，未删除。'
        fi
        if [[ ! -e "$MANAGER" && ! -e "$SHORTCUT" ]] \
            && ! tfo_sysctl_is_ours && ! checker_marker_is_ours; then
            fail '没有发现本脚本的残留文件。'
        fi
        confirm '节点记录已不存在，清理本脚本的残留管理入口和 TFO 设置？[y/N]：' \
            || { say '已取消清理。'; return 0; }
        checker_cleanup_preflight || fail 'RealityChecker 程序已改变，未继续清理。'
        remove_checker || fail '清理 RealityChecker 失败。'
        disable_kernel_tfo || fail '清理残留 TFO 设置失败。'
        clean_runtime_residue || fail '清理临时文件失败。'
        if shortcut_is_ours; then rm -f -- "$SHORTCUT" || fail '删除快捷命令失败。'; fi
        if [[ -f "$MANAGER" ]]; then rm -f -- "$MANAGER" || fail '删除管理脚本失败。'; fi
        ok '本脚本的残留文件已清理。'
        return 0
    fi
    [[ -f "$MARKER" && ! -L "$MARKER" ]] || fail '安装记录异常，已停止以保护现有服务。'
    confirm '确定卸载节点并清理本脚本创建的全部文件？[y/N]：' || { say '已取消卸载。'; return 0; }
    checker_cleanup_preflight || fail 'RealityChecker 程序已改变，未继续卸载。'
    if [[ -e "$SERVICE" ]]; then
        [[ -f "$SERVICE" && ! -L "$SERVICE" ]] || fail '服务文件不是普通文件，已停止以保护现有服务。'
        grep -qFx 'ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json' "$SERVICE" \
            || fail '服务文件已被其他程序修改，已停止以保护现有服务。'
        systemctl stop xray || fail '停止 Xray 失败；未继续删除文件，请检查 systemctl status xray。'
        if systemctl is-enabled --quiet xray; then
            systemctl disable xray || fail '禁用 Xray 开机启动失败；未继续删除文件。'
        fi
    elif systemctl is-active --quiet xray; then
        fail '发现运行中的 xray 服务，但本脚本的服务文件已不存在；未继续删除。'
    fi
    systemctl is-active --quiet xray && fail 'Xray 仍在运行，未继续删除文件。'
    remove_checker || fail '删除 RealityChecker 失败；保留节点安装记录以便重试。'
    disable_kernel_tfo || fail '恢复内核 TCP Fast Open 设置失败；保留节点文件以便重试。'
    rm -f -- "$SERVICE" || fail '删除 systemd 服务文件失败。'
    systemctl daemon-reload || fail '刷新 systemd 失败；保留安装记录以便重试。'
    rm -f -- "$XRAY_BIN" "$LINK_FILE" || fail '删除 Xray 程序或节点链接失败。'
    rm -f -- "$CONFIG" || fail '删除节点配置失败。'
    clean_config_residue || fail '清理配置备份失败；保留安装记录以便重试。'
    clean_runtime_residue || fail '清理临时文件失败；保留安装记录以便重试。'
    if getent passwd xray >/dev/null 2>&1; then
        userdel xray || fail '删除 xray 用户失败；保留安装记录以便重试。'
    fi
    if getent group xray >/dev/null 2>&1; then
        groupdel xray || fail '删除 xray 用户组失败；保留安装记录以便重试。'
    fi
    if shortcut_is_ours; then rm -f -- "$SHORTCUT" || fail '删除快捷命令失败。'; fi
    rm -f -- "$MANAGER" || fail '删除管理脚本失败。'
    [[ ! -e "$XRAY_BIN" && ! -e "$SERVICE" && ! -e "$CONFIG" \
        && ! -e "$LINK_FILE" ]] || fail '卸载后仍发现节点文件，请手动检查。'
    checker_marker_is_ours && fail '卸载后仍发现本脚本的 RealityChecker。'
    tfo_sysctl_is_ours && fail '卸载后仍发现本脚本的 TFO 设置。'
    if getent passwd xray >/dev/null 2>&1 || getent group xray >/dev/null 2>&1 \
        || systemctl is-active --quiet xray; then
        fail '卸载后仍发现 xray 服务或专用账号，请手动检查。'
    fi
    rm -f -- "$MARKER" || fail '删除安装记录失败。'
    if ! rmdir -- "$CONFIG_DIR" 2>/dev/null; then
        warn "$CONFIG_DIR 中还有其他文件，已保留该目录及其中内容。"
    fi
    ok '节点和本脚本创建的文件已清理。云安全组规则、客户端节点、基础工具和系统日志未改动。'
}

print_help() {
    local cmd
    cmd="$(cmd_name)"
    cat <<EOF
VLESS + REALITY + Vision 节点管理脚本 v${SCRIPT_VERSION}
用法：${cmd} [命令]
  install [端口] [SNI] [名称] [TFO:on|off] [VLESS加密:on|off] [模式]  安装节点
  show                         显示 vless:// 导入链接
  status                       查看服务、配置、端口和伪装站点状态
  port [新端口]                修改端口
  sni [新域名|auto]            修改或自动优选 REALITY 伪装域名
  sni-best                     查看当前测速延迟最低的域名，不修改节点
  checker [status|install|uninstall|check 域名|batch 域名...|csv 文件]  管理 RealityChecker
  tfo [on|off]                 查看或切换 TCP Fast Open
  vlessenc [on [native|xorpub|random]|off]  查看或切换 VLESS Encryption 模式
  uuid                         重新生成 UUID
  rotate-keys                  轮换 REALITY 密钥和 Short ID
  rename [新名称]              修改节点名称
  refresh-ip                   更新链接中的公网 IPv4
  start|stop|restart           管理服务
  log [-f|行数]                查看日志
  update                       升级 Xray-core
  uninstall                    卸载并清理
EOF
}

menu_status() {
    if [[ ! -f "$MARKER" ]]; then say " 当前状态：${RED}● 未安装${RESET}"; return 0; fi
    if [[ ! -f "$CONFIG" ]]; then
        warn ' 当前状态：● 节点文件不完整；可选择 2 重试卸载'
        return 0
    fi
    local state color label
    state="$(systemctl is-active xray 2>/dev/null || true)"
    case "$state" in
        active) color="$GREEN"; label='运行中' ;;
        failed) color="$RED"; label='运行失败' ;;
        *) color="$YELLOW"; label="${state:-未知}" ;;
    esac
    load_metadata
    say " 当前状态：${GREEN}● 已安装${RESET} [Xray $(installed_version)]  ${color}● ${label}${RESET}"
    say " 当前节点：${NODE_NAME}（${SERVER_IP}:${PORT}，SNI ${SNI}）"
}

show_menu() {
    [[ -t 1 ]] && clear 2>/dev/null || true
    say '=================================='
    say " VLESS + REALITY + Vision ${RED}[v${SCRIPT_VERSION}]${RESET}"
    say '=================================='
    say '  1. 安装节点'
    say '  2. 卸载节点'
    say '  3. 升级 Xray-core'
    say '----------------------------------'
    say '  4. 启动服务'
    say '  5. 停止服务'
    say '  6. 重启服务'
    say '----------------------------------'
    say '  7. 修改端口'
    say '  8. 修改伪装域名（支持自动优选）'
    say '  9. 重新生成 UUID'
    say ' 10. 轮换 REALITY 密钥'
    say ' 11. 修改节点名称'
    say ' 12. 刷新公网 IP'
    say '----------------------------------'
    say ' 13. 查看导入链接'
    say ' 14. 查看运行状态'
    say ' 15. 查看运行日志'
    say ' 16. 查看当前测速延迟最低的域名'
    say ' 17. 开关 TCP Fast Open'
    say ' 18. 管理 RealityChecker（可选）'
    say ' 19. 开关 VLESS Encryption / 修改模式'
    say ' 00. 退出'
    say '=================================='
    menu_status
    say
}
menu_action() {
    case "$1" in
        1) install_node ;; 2) uninstall_node ;; 3) update_xray ;;
        4) start_node ;; 5) stop_node ;; 6) restart_node ;;
        7) change_port ;; 8) change_sni ;;
        9) warn '操作后旧链接立即失效。'; change_uuid ;;
        10) warn '操作后旧链接立即失效。'; rotate_keys ;;
        11) rename_node ;; 12) refresh_ip ;; 13) show_node ;;
        14) status_node ;; 15) log_node ;; 16) show_fastest_sni ;;
        17) tfo_node ;; 18) checker_menu ;; 19) vlessenc_node ;; *) return 2 ;;
    esac
}
interactive_menu() {
    if [[ ! -t 0 ]]; then print_help; return 0; fi
    need_root
    if [[ -f "$MARKER" ]]; then ensure_shortcut quiet || true; fi
    local choice rc
    while true; do
        show_menu
        read -r -p '请输入数字 [1-19，00 退出]：' choice || { say; return 0; }
        case "$choice" in 00|q|Q) return 0 ;; [1-9]|1[0-9]) ;; *) warn '请输入菜单中的数字。'; sleep 1; continue ;; esac
        say
        set +e
        ( set -e; menu_action "$choice" )
        rc=$?
        set -e
        [[ "$choice" == 2 && ! -f "$MANAGER" ]] && return 0
        (( rc == 0 )) || say
        say
        read -r -p '* 按回车返回主菜单 *' || return 0
    done
}

main() {
    case "${1:-}" in
        '') interactive_menu ;;
        help|-h|--help) print_help ;;
        install) shift; install_node "$@" ;;
        show) show_node ;;
        status) status_node ;;
        port) shift; change_port "$@" ;;
        sni) shift; change_sni "$@" ;;
        sni-best) show_fastest_sni ;;
        checker) shift; checker_command "$@" ;;
        tfo) shift; tfo_node "$@" ;;
        __tfo-apply) shift; tfo_apply "$@" ;;
        vlessenc) shift; vlessenc_node "$@" ;;
        __vlessenc-apply) shift; vlessenc_apply "$@" ;;
        uuid) change_uuid ;;
        rotate-keys) rotate_keys ;;
        rename) shift; rename_node "$@" ;;
        refresh-ip) refresh_ip ;;
        start) start_node ;;
        stop) stop_node ;;
        restart) restart_node ;;
        log|logs) shift; log_node "$@" ;;
        update) update_xray ;;
        uninstall) uninstall_node ;;
        [1-9]|1[0-9]) need_root; menu_action "$1" ;;
        *) print_help; exit 2 ;;
    esac
}

main "$@"
