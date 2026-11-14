#!/usr/bin/env bash
# VLESS + REALITY + Vision 节点管理脚本：Debian/Ubuntu + Xray-core。
# 请先下载为普通文件后运行，不支持 curl | bash（安装过程需要读取终端输入）。
# shellcheck disable=SC2030,SC2031 # 自有域名操作用子 shell 隔离状态，持久化通过安装记录重新读取。
# shellcheck disable=SC2016 # 下方单引号内的 $name 是 jq 变量，不由 Bash 展开。
set -Eeuo pipefail
umask 077

SCRIPT_VERSION='2.0.0'
SCRIPT_PATH="${BASH_SOURCE[0]}"
XRAY_API='https://api.github.com/repos/XTLS/Xray-core/releases'
XRAY_BIN='/usr/local/bin/xray'
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
NODE_MODE='external'
SELF_DIR='/etc/vless-reality-self'
SELF_SITE='/etc/nginx/conf.d/vless-reality-self.conf'
SELF_WEB='/var/www/vless-reality-self'
SELF_RENEW_SERVICE='/etc/systemd/system/vless-reality-cert.service'
SELF_RENEW_TIMER='/etc/systemd/system/vless-reality-cert.timer'
SELF_METHOD=''
SELF_EMAIL=''
SELF_CREDENTIALS=''
SELF_STARTED=0
SELF_OPERATION_LOCKED=0
SELF_POLICY='/usr/sbin/policy-rc.d'
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

# 仅保留旧版本 RealityChecker 的归属检查和卸载清理。
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
        if [[ "$1" =~ ^mlkem768x25519plus[.]${mode}[.]600s[.][A-Za-z0-9_-]+$ \
            && "$2" =~ ^mlkem768x25519plus[.]${mode}[.]0rtt[.][A-Za-z0-9_-]+$ ]]; then
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
    if printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
        "$PORT" "$SNI" "$NODE_NAME" "$SERVER_IP" "$PUBLIC_KEY" "$SHORT_ID" "$CLIENT_ENCRYPTION" "$NODE_MODE" > "$tmp" \
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
    NODE_MODE="${lines[7]:-external}"
    case "$NODE_MODE" in external|self) ;; *) fail '安装模式记录无效。' ;; esac
    [[ "$NODE_MODE" != self || "$PORT" == 443 ]] || fail '自有域名安装记录的端口必须为 443。'
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
    for dir in /tmp/vless-reality-install.?????? /tmp/vless-reality-update.?????? /tmp/vless-reality-sni.?????? /tmp/vless-reality-client.??????; do
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
        if [[ "$dir" == /tmp/vless-reality-client.?????? ]]; then stop_client_residue "$dir" || return 1; fi
        for file in release.json xray.zip xray xray.old client.json client.log test.log client.pid; do
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
            if ! purge_node_files; then cleanup_ok=0; fi
        fi
        if (( SELF_STARTED )); then
            if ! self_cleanup; then cleanup_ok=0; fi
        fi
        if (( cleanup_ok )); then
            if (( MANAGER_COPIED )); then rm -f -- "$MANAGER" || true; fi
        else
            warn '自动回滚未完成；已保留管理脚本和可用的归属记录，请检查服务并重试卸载。' >&2
        fi
    fi
    [[ -z "$TEMP_DIR" ]] || rm -rf -- "$TEMP_DIR"
    return "$result"
}

write_config() {
    local uuid="$1" private_key="$2" target="${SNI}:443"
    [[ "$NODE_MODE" != self ]] || target=127.0.0.1:8443
    jq -n \
        --arg uuid "$uuid" --arg privateKey "$private_key" --arg shortId "$SHORT_ID" \
        --arg target "$target" --arg sni "$SNI" --arg decryption "$VLESS_DECRYPTION" --argjson port "$PORT" --argjson tfo "$TFO_ENABLED" '
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
                target: $target,
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
    local interactive=0 raw_port="${1:-}" answer default_name auto_sni=0 tfo_choice="${4:-off}" enc_choice="${5:-off}" enc_mode="${6:-native}"
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

    if (( interactive )); then
        say
        step '—————————— 确认安装信息 ——————————'
        say "  协议：VLESS + REALITY + Vision"
        say "  端口：TCP $PORT"
        if (( auto_sni )); then say "  SNI： $SNI:443（自动优选）"; else say "  SNI： $SNI:443"; fi
        say "  名称：$NODE_NAME"
        if (( TFO_ENABLED )); then say '  TFO： 开启'; else say '  TFO： 关闭'; fi
        if [[ "$enc_choice" == on ]]; then say "  VLESS Encryption：开启（$enc_mode）"; else say '  VLESS Encryption：关闭'; fi
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
    if [[ "$NODE_MODE" == self ]]; then
        self_preflight
    else
        target_tls_ok "$SNI" || fail "$SNI:443 未通过 TLS 1.3 与证书校验，请更换可从本机访问的伪装域名。"
        ok "伪装站点可用：$SNI:443（TLS 1.3）"
    fi

    trap finish_install EXIT
    save_manager
    TEMP_DIR="$(mktemp -d /tmp/vless-reality-install.XXXXXX)"
    printf 'vless-reality-setup\n' > "$TEMP_DIR/.vless-reality-owned"
    INSTALL_STARTED=1
    if [[ "$NODE_MODE" == self ]]; then self_prepare; fi
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
    if [[ "$NODE_MODE" == self ]]; then
        check_self || fail '自有域名最终检查失败；安装将回滚。'
    fi
    show_node
    ensure_shortcut || true
    INSTALL_COMMITTED=1
    trap - EXIT
    rm -rf -- "$TEMP_DIR"
    TEMP_DIR=''
    ok "安装完成：Xray ${RELEASE_VERSION} 正在监听 TCP ${PORT}。"
    warn "请确认云安全组已放行 TCP ${PORT}。导入链接包含 UUID，请勿公开分享。"
}

show_node() {
    need_root
    load_metadata
    local uuid label link tmp address="$SERVER_IP" enc_param tfo_param=''
    uuid="$(config_uuid)" || fail '无法从配置读取 UUID。'
    label="$(jq -rn --arg v "$NODE_NAME" '$v | @uri')" || return 1
    enc_param="$(jq -rn --arg v "$CLIENT_ENCRYPTION" '$v | @uri')" || return 1
    # tfo 是部分客户端识别的扩展参数；服务端开关仍以 Xray 配置为准。
    if config_tfo_enabled; then tfo_param='&tfo=1'; fi
    [[ "$NODE_MODE" != self ]] || address="$SNI"
    link="vless://${uuid}@${address}:${PORT}?encryption=${enc_param}&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none${tfo_param}#${label}"
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
    say "安装模式：$NODE_MODE"
    say "监听地址：${SERVER_IP}:${PORT}/TCP"
    [[ "$NODE_MODE" != self ]] || say "节点地址：${SNI}:443"
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
    if [[ "$NODE_MODE" == self && -n "$current_ip" && "$current_ip" != "$SERVER_IP" ]]; then
        warn "公网 IPv4 已变化为 $current_ip；请核对域名 A 记录，Address 保持 $SNI。"
    elif [[ -n "$current_ip" && "$current_ip" != "$SERVER_IP" ]]; then
        warn "公网 IPv4 已变化：当前 $current_ip，链接中仍为 $SERVER_IP；请运行 $(cmd_name) refresh-ip。"
    fi
    if [[ "$NODE_MODE" == self ]]; then
        if self_tls_check "$SNI" 127.0.0.1:8443; then ok '本地网站：TLS 1.3 / X25519 / H2 正常'; else warn '本地网站验证失败'; fi
        cert_status
    elif target_tls_ok "$SNI"; then ok '伪装站点：TLS 1.3 正常'; else warn '伪装站点：当前验证失败'; fi
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
    self_operation_lock
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
        && { (( was_active == 0 )) || { systemctl restart xray && wait_service 10; }; } \
        && (show_node >/dev/null); then
        rm -rf -- "$backup"
        if [[ "$action" == on ]]; then
            ok "TCP Fast Open 已开启（内核值 $(kernel_tfo_value)）。"
        else
            ok 'TCP Fast Open 已关闭；本脚本修改的内核设置已恢复。'
        fi
        say '新导入链接已附带 tfo=1（开启时）；请检查客户端是否识别该参数。'
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
        show_node
    else
        fail "TFO 后台任务失败；请查看 journalctl -u $unit。"
    fi
}

vlessenc_apply() {
    need_root
    self_operation_lock
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
    self_operation_lock
    [[ $# -le 1 ]] || fail "用法：$(cmd_name) port [新端口]"
    load_metadata
    [[ "$NODE_MODE" != self ]] || fail '自有域名模式固定使用 TCP 443；端口修改只适用于普通模式。'
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
    if [[ "$NODE_MODE" == self ]]; then change_self_domain "$@"; return; fi
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
    self_operation_lock
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
    self_operation_lock
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
    self_operation_lock
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
    self_operation_lock
    load_metadata
    if [[ "$NODE_MODE" == self ]]; then
        self_dns_check "$SNI" || fail 'DNS 未指向当前 VPS；请手动更新 DNS。节点地址仍使用域名。'
        ok '自有域名 DNS 检查通过；节点 Address 保持域名。'
        return 0
    fi
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
    self_operation_lock
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
    need_root; self_operation_lock; load_metadata
    if systemctl is-active --quiet xray; then ok '服务已在运行。'; return 0; fi
    systemctl start xray || fail '启动失败，请查看日志。'
    wait_service 10 || fail '服务已启动但端口未正常监听，请查看日志。'
    ok '服务已启动。'
}
stop_node() {
    need_root; self_operation_lock; load_metadata
    if ! systemctl is-active --quiet xray; then ok '服务已经停止。'; return 0; fi
    if [[ -t 0 ]] && ! confirm '停止后节点将无法连接，确定停止？[y/N]：'; then say '已取消。'; return 0; fi
    systemctl stop xray
    ok '服务已停止。'
}
restart_node() {
    need_root; self_operation_lock; load_metadata
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
    self_operation_lock
    if [[ -e "$SELF_DIR" ]]; then self_cleanup_preflight || fail '自有域名资源已改变或被共享，卸载已停止以保护数据。'; fi
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
            && ! tfo_sysctl_is_ours && ! checker_marker_is_ours && [[ ! -e "$SELF_DIR" ]]; then
            fail '没有发现本脚本的残留文件。'
        fi
        confirm '节点记录已不存在，清理本脚本的残留入口、网站/证书和 TFO 设置？[y/N]：' \
            || { say '已取消清理。'; return 0; }
        checker_cleanup_preflight || fail 'RealityChecker 程序已改变，未继续清理。'
        self_cleanup || fail '清理自有域名资源失败。'
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
    self_cleanup || fail '自有域名资源未清理；保留节点安装记录以便重试。'
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

# 自有域名模式：全部逻辑内嵌，保持单文件下载部署。
self_exists() { [[ -f "$SELF_DIR/.owned" && ! -L "$SELF_DIR/.owned" && ! -L "$SELF_DIR" && "$(stat -c %u "$SELF_DIR")" == 0 && "$(stat -c %a "$SELF_DIR")" == 700 && "$(< "$SELF_DIR/.owned")" == vless-reality-self-v1 ]]; }
self_operation_lock() {
    if self_exists && (( SELF_OPERATION_LOCKED == 0 )); then
        exec 9> "$SELF_DIR/operation.lock" || fail '无法锁定自有域名操作。'
        flock -x 9 || fail '无法取得自有域名操作锁。'
        SELF_OPERATION_LOCKED=1
    fi
}
self_track() {
    local path="$1" source="${2:-$1}" tmp digest
    [[ -f "$source" && ! -L "$source" ]] || return 1
    tmp="$(mktemp "$SELF_DIR/.receipt.XXXXXX")" || return 1
    if [[ -f "$SELF_DIR/files.sha256" ]]; then
        awk -v path="$path" 'substr($0,67) != path' "$SELF_DIR/files.sha256" > "$tmp" || { rm -f "$tmp"; return 1; }
    fi
    digest="$(sha256sum -- "$source" | awk '{print $1}')" || { rm -f "$tmp"; return 1; }
    printf '%s  %s\n' "$digest" "$path" >> "$tmp" && mv -f -- "$tmp" "$SELF_DIR/files.sha256"
}
self_publish() {
    local source="$1" destination="$2" mode="$3"
    chmod "$mode" "$source" && self_track "$destination" "$source" && mv -f -- "$source" "$destination"
}
self_file_owned() {
    local path="$1" expected
    [[ ! -e "$path" && ! -L "$path" ]] && return 0
    [[ -f "$path" && ! -L "$path" ]] || return 1
    expected="$(awk -v path="$path" 'substr($0,67) == path {print substr($0,1,64)}' "$SELF_DIR/files.sha256")"
    [[ -n "$expected" && "$(sha256sum -- "$path" | awk '{print $1}')" == "$expected" ]]
}
self_state() { jq -r --arg key "$1" 'if has($key) then .[$key] else error("missing state field") end' "$SELF_DIR/state.json"; }
self_dns_query() { dig "@$1" "$2" "$3" +time=4 +tries=1 +noall +answer +comments; }
self_dns_check() {
    local domain="$1" ip resolver output records aaaa cname
    valid_host "$domain" || { warn '失败：域名格式无效。' >&2; return 1; }
    ip="$(public_ipv4)" || { warn '失败：无法确认本机公网 IPv4。' >&2; return 1; }
    for resolver in 1.1.1.1 8.8.8.8; do
        output="$(self_dns_query "$resolver" "$domain" A)" || return 1
        [[ "$output" == *'status: NOERROR'* ]] || { warn "失败：$resolver 返回 DNS 错误。" >&2; return 1; }
        cname="$(awk '$4 == "CNAME" {print $5}' <<< "$output")"
        [[ -z "$cname" ]] || { warn '失败：自有域名模式不接受 CNAME，请使用直接指向 VPS 的 A 记录。' >&2; return 1; }
        records="$(awk '$4 == "A" {print $5}' <<< "$output" | sort -u)"
        [[ "$records" == "$ip" ]] || { warn '失败：A 记录不是唯一的当前 VPS IPv4；请关闭 CDN/Cloudflare 橙云并等待 DNS 生效。' >&2; return 1; }
        output="$(self_dns_query "$resolver" "$domain" AAAA)" || return 1
        [[ "$output" == *'status: NOERROR'* ]] || return 1
        aaaa="$(awk '$4 == "AAAA" {print $5}' <<< "$output")"
        [[ -z "$aaaa" ]] || { warn '失败：此模式只配置 IPv4 入口，请先移除 AAAA 记录，避免 IPv6 连接绕过本机配置。' >&2; return 1; }
    done
}
self_cloudflare_zone() {
    local zone="$1" ns
    while [[ "$zone" == *.* ]]; do
        ns="$(dig @1.1.1.1 "$zone" NS +short +time=4 +tries=1)" || return 1
        if [[ -n "$ns" ]]; then
            while IFS= read -r ns; do [[ "$ns" == *.ns.cloudflare.com. ]] || return 1; done <<< "$ns"
            return 0
        fi
        zone="${zone#*.}"
    done
    return 1
}
self_extra_dependencies() {
    local packages=() command_name
    command -v dig >/dev/null || packages+=(dnsutils)
    command -v nginx >/dev/null || packages+=(nginx)
    command -v certbot >/dev/null || packages+=(certbot)
    if [[ "$SELF_METHOD" == cloudflare ]] && ! dpkg-query -W -f='${Status}' python3-certbot-dns-cloudflare 2>/dev/null | grep -q 'install ok installed'; then
        packages+=(python3-certbot-dns-cloudflare)
    fi
    if (( ${#packages[@]} )); then
        # 防止新安装的 Nginx 在写入安全配置前自动暴露默认 80 站点。
        (
            local policy="$SELF_POLICY" created=0
            if ! command -v nginx >/dev/null; then
                [[ ! -e "$policy" && ! -L "$policy" ]] || fail '已有 policy-rc.d；请先通过系统包管理器安装 nginx，再运行自有域名安装。'
                printf '#!/bin/sh\n# vless-reality-self package guard\nexit 101\n' > "$policy"
                chmod 755 "$policy"
                self_track "$policy" || exit 1
                # shellcheck disable=SC2034 # 由 EXIT trap 读取。
                created=1
            fi
            trap 'if (( created )); then if self_file_owned "$policy"; then rm -f -- "$policy"; else warn "安装保护文件已被修改，保留：$policy" >&2; fi; fi' EXIT
            apt-get update && apt-get install -y "${packages[@]}"
        ) || return 1
    fi
    for command_name in dig nginx certbot flock; do need_command "$command_name"; done
}
self_preflight() {
    local path
    [[ "$PORT" == 443 ]] || fail '自有域名模式必须使用 TCP 443。'
    port_free 443 || fail 'TCP 443 已被占用。'
    port_free 8443 || fail 'TCP 8443 已被占用；不会覆盖已有网站。'
    for path in "$SELF_DIR" "$SELF_SITE" "$SELF_WEB" "$SELF_RENEW_SERVICE" "$SELF_RENEW_TIMER" "${SELF_RENEW_SERVICE%.service}-alert.service"; do
        [[ ! -e "$path" && ! -L "$path" ]] || fail "已有资源 $path；为保护现有文件，已停止。"
    done
    for path in vless-reality-cert.service vless-reality-cert.timer vless-reality-cert-alert.service; do
        if systemctl cat "$path" >/dev/null 2>&1; then fail "已存在 $path，未覆盖其他服务。"; fi
    done
    [[ "$SELF_METHOD" == cloudflare || "$SELF_METHOD" == http ]] || fail '证书方式只能为 cloudflare 或 http。'
    [[ "$SELF_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$ ]] || fail '请输入有效的 LE 通知邮箱。'
    if [[ "$SELF_METHOD" == http ]]; then
        port_free 80 || fail 'HTTP-01 需要独占 TCP 80；当前已被占用，请改用 DNS-01。'
    fi
}
self_nginx_write() {
    local domain="$1" tls="${2:-yes}" http_domain="${3:-$1}" version h2listen='http2' h2directive='' tmp
    version="$(nginx -v 2>&1 | sed -n 's|.*nginx/\([0-9.]*\).*|\1|p')"
    dpkg --compare-versions "$version" ge 1.19.4 || return 1
    if dpkg --compare-versions "$version" ge 1.25.1; then h2listen=''; h2directive='http2 on;'; fi
    tmp="$(mktemp "$SELF_DIR/work/nginx.XXXXXX")" || return 1
    {
        printf '# vless-reality-self managed site\n'
        if [[ "$SELF_METHOD" == http ]]; then
            cat <<EOF
server {
    listen 80 default_server;
    server_name _;
    return 444;
}
server {
    listen 80;
    server_name $http_domain;
    location ^~ /.well-known/acme-challenge/ { root $SELF_WEB; default_type text/plain; }
    location / { return 404; }
}
EOF
        fi
        if [[ "$tls" == yes ]]; then
            cat <<EOF
server {
    listen 127.0.0.1:8443 ssl $h2listen default_server;
    $h2directive
    server_name _;
    ssl_protocols TLSv1.3;
    ssl_ecdh_curve X25519:prime256v1;
    ssl_reject_handshake on;
}
server {
    listen 127.0.0.1:8443 ssl $h2listen;
    $h2directive
    server_name $domain;
    ssl_protocols TLSv1.3;
    ssl_ecdh_curve X25519:prime256v1;
    ssl_certificate $SELF_DIR/acme/live/$domain/fullchain.pem;
    ssl_certificate_key $SELF_DIR/acme/live/$domain/privkey.pem;
    server_tokens off;
    root $SELF_WEB;
    index index.html;
    client_max_body_size 16k;
    client_header_timeout 10s;
    client_body_timeout 10s;
    keepalive_timeout 15s;
    access_log off;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy no-referrer always;
    add_header Content-Security-Policy "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'" always;
    if (\$ssl_server_name != "$domain") { return 444; }
    location / { limit_except GET HEAD { deny all; } try_files \$uri \$uri/ =404; }
    location ~ /\. { deny all; }
}
EOF
        fi
    } > "$tmp"
    self_publish "$tmp" "$SELF_SITE" 644
}
self_nginx_apply() { nginx -t && { if systemctl is-active --quiet nginx; then systemctl reload nginx; else systemctl start nginx; fi; }; }
self_site_write() {
    install -d -m 755 "$SELF_WEB"
    cat > "$SELF_WEB/index.html" <<'HTML'
<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>小径 · 留白</title><style>*{box-sizing:border-box}body{margin:0;background:#f3f0e9;color:#23382e;font:18px/1.8 system-ui,sans-serif}main{max-width:1050px;margin:auto;padding:12vh 7vw}small{letter-spacing:.2em}h1{font-size:clamp(48px,8vw,100px);line-height:1.15;font-weight:500;letter-spacing:-.06em}p{max-width:550px;color:#55665b}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:28px;margin-top:70px;border-top:1px solid #ccd2c8;padding-top:30px}article{font-size:15px}footer{margin-top:90px;font-size:13px;color:#778577}</style><main><small>FIELD NOTES / 日常观察</small><h1>走慢一点，<br>看见更多。</h1><p>这里记录微小而值得留意的事：清晨的光、窗边的植物，以及一段安静的阅读时间。</p><section class="grid"><article><b>01 / 自然</b><p>在四季之间，收集新的颜色。</p></article><article><b>02 / 阅读</b><p>给好奇心留下一页空白。</p></article><article><b>03 / 生活</b><p>把日常过成喜欢的样子。</p></article></section><footer>小径 · 留白 — 一个关于观察与生活的静态空间</footer></main></html>
HTML
    chmod 644 "$SELF_WEB/index.html"
    self_track "$SELF_WEB/index.html"
}
self_scrub_logs() {
    [[ -f "$SELF_DIR/cloudflare.ini" ]] || return 0
    python3 - "$SELF_DIR" <<'PY_SCRUB'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
m = re.search(r"^dns_cloudflare_api_token\s*=\s*(\S+)", (root / "cloudflare.ini").read_text(), re.M)
if m:
    token = m.group(1).encode()
    for p in (root / "logs").rglob("*"):
        if p.is_file() and not p.is_symlink():
            data = p.read_bytes()
            if token in data:
                p.write_bytes(data.replace(token, b"[REDACTED]"))
PY_SCRUB
}
self_http_challenge_check() {
    local domain="$1" ip="$2" path result=0
    path="$(openssl rand -hex 16)" || return 1
    install -d -m 755 "$SELF_WEB/.well-known/acme-challenge" || return 1
    printf '%s' "$path" > "$SELF_WEB/.well-known/acme-challenge/$path" || return 1
    chmod 644 "$SELF_WEB/.well-known/acme-challenge/$path" || return 1
    [[ "$(curl --noproxy '*' -fsS --max-time 10 --resolve "$domain:80:$ip" "http://$domain/.well-known/acme-challenge/$path")" == "$path" ]] || result=1
    rm -f "$SELF_WEB/.well-known/acme-challenge/$path" || return 1
    return "$result"
}
self_managed_paths_ok() {
    self_exists || return 1
    local path
    for path in "$SELF_DIR/acme" "$SELF_DIR/work" "$SELF_DIR/logs"; do
        [[ -d "$path" && ! -L "$path" && "$(stat -c %u "$path")" == 0 ]] || return 1
    done
    [[ -f "$SELF_DIR/state.json" ]] && self_file_owned "$SELF_DIR/state.json" || return 1
    if [[ -e "$SELF_DIR/cloudflare.ini" || -L "$SELF_DIR/cloudflare.ini" ]]; then
        self_file_owned "$SELF_DIR/cloudflare.ini" && [[ "$(stat -c %a "$SELF_DIR/cloudflare.ini")" == 600 ]] || return 1
    fi
}
self_certbot() {
    self_managed_paths_ok || { warn '证书目录或凭据归属异常，已停止 Certbot 操作。' >&2; return 1; }
    local result=0
    certbot "$@" --config "$SELF_DIR/cli.ini" --config-dir "$SELF_DIR/acme" --work-dir "$SELF_DIR/work" --logs-dir "$SELF_DIR/logs" || result=$?
    self_scrub_logs || return 1
    return "$result"
}
self_issue_cert() {
    local domain="$1" args=()
    if [[ "$SELF_METHOD" == cloudflare ]]; then
        self_cloudflare_zone "$domain" || { warn '域名的权威 DNS 不是 Cloudflare；请改用 HTTP-01 或独立 DNS 插件。' >&2; return 1; }
        args=(--dns-cloudflare --dns-cloudflare-credentials "$SELF_DIR/cloudflare.ini" --dns-cloudflare-propagation-seconds 60)
    else
        args=(--webroot --webroot-path "$SELF_WEB")
    fi
    self_certbot certonly --non-interactive --agree-tos --email "$SELF_EMAIL" \
        --server https://acme-v02.api.letsencrypt.org/directory --cert-name "$domain" -d "$domain" \
        --key-type ecdsa "${args[@]}" > "$SELF_DIR/logs/issue.log" 2>&1
}
self_tls_check() {
    local domain="$1" address="$2" output
    output="$(timeout 15 openssl s_client -connect "$address" -servername "$domain" -tls1_3 -groups X25519 \
        -alpn h2 -verify_hostname "$domain" -verify_return_error -CApath /etc/ssl/certs </dev/null 2>&1)" || return 1
    [[ "$output" == *'Verify return code: 0 (ok)'* && "$output" == *'TLSv1.3'* \
        && "$output" == *'X25519'* && "$output" == *'ALPN protocol: h2'* ]]
}
self_loaded_cert_matches() {
    local domain="$1" loaded disk
    loaded="$(timeout 15 openssl s_client -connect 127.0.0.1:8443 -servername "$domain" -tls1_3 </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256)" || return 1
    disk="$(openssl x509 -in "$SELF_DIR/acme/live/$domain/cert.pem" -noout -fingerprint -sha256)" || return 1
    [[ "$loaded" == "$disk" ]]
}
self_http_check() {
    local domain="$1" address="$2" port="$3" result
    result="$(curl --noproxy '*' --http2 --tlsv1.3 --tls-max 1.3 -fsS --connect-timeout 5 --max-time 15 \
        --resolve "$domain:$port:$address" -o /dev/null -w '%{http_version} %{http_code}' "https://$domain:$port/")" || return 1
    [[ "$result" == '2 200' ]]
}
self_wait_tls() {
    local attempt
    for attempt in {1..10}; do
        if self_tls_check "$1" 127.0.0.1:8443 && self_loaded_cert_matches "$1" && self_http_check "$1" 127.0.0.1 8443; then return 0; fi
        sleep 1
    done
    return 1
}
self_listener_check() {
    local lines
    lines="$(ss -H -ltn 'sport = :8443')" || return 1
    [[ -n "$lines" ]] || return 1
    awk '$4 != "127.0.0.1:8443" {bad=1} END {exit bad}' <<< "$lines"
}
self_reload_hook_write() {
    install -d -m 700 "$SELF_DIR/acme/renewal-hooks/deploy"
    cat > "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx" <<'HOOK'
#!/bin/sh
# vless-reality-self deploy hook
set -eu
nginx -t
systemctl reload nginx
HOOK
    chmod 700 "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx"
    self_track "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx"
}
self_timer_write() {
    cat > "$SELF_DIR/work/cert.service" <<EOF
# vless-reality-self managed unit
[Unit]
Description=Renew isolated VLESS REALITY website certificate
After=network-online.target nginx.service
Wants=network-online.target
OnFailure=vless-reality-cert-alert.service
[Service]
Type=oneshot
UMask=0077
TimeoutStartSec=20min
ExecStart=/bin/bash $MANAGER __cert-renew
EOF
    self_publish "$SELF_DIR/work/cert.service" "$SELF_RENEW_SERVICE" 644 || return 1
    cat > "$SELF_DIR/work/cert.timer" <<'EOF'
# vless-reality-self managed unit
[Unit]
Description=VLESS REALITY isolated certificate renewal
[Timer]
OnCalendar=*-*-* 03,15:00:00
RandomizedDelaySec=3600
Persistent=true
[Install]
WantedBy=timers.target
EOF
    self_publish "$SELF_DIR/work/cert.timer" "$SELF_RENEW_TIMER" 644 || return 1
    cat > "$SELF_DIR/work/cert-alert.service" <<EOF
# vless-reality-self managed unit
[Unit]
Description=VLESS REALITY certificate alert
[Service]
Type=oneshot
ExecStart=/bin/bash $MANAGER __cert-alert
EOF
    self_publish "$SELF_DIR/work/cert-alert.service" "${SELF_RENEW_SERVICE%.service}-alert.service" 644 || return 1
    systemctl daemon-reload && systemctl enable --now vless-reality-cert.timer
}
self_cert_alert() {
    need_root
    self_exists || return 1
    local domain hook=/etc/vless-reality-cert-alert
    domain="$(self_state domain)" || return 1
    logger -p daemon.err -t vless-reality-cert -- "证书到期预警或续期失败：$domain；请检查 journalctl -u vless-reality-cert。"
    if [[ -x "$hook" && -f "$hook" && ! -L "$hook" && "$(stat -c %u "$hook")" == 0 \
        && "$(stat -c %a "$hook")" =~ ^[57]00$ ]]; then "$hook" "$domain"; fi
}
self_cert_renew() (
    need_root
    self_exists || return 1
    exec 8> "$SELF_DIR/operation.lock"; flock -x 8 || return 1
    local domain rc=0
    domain="$(self_state domain)" || return 1
    self_certbot renew --non-interactive --quiet --cert-name "$domain" > "$SELF_DIR/logs/renew.log" 2>&1 || rc=1
    if ! self_wait_tls "$domain"; then rc=1; fi
    if ! openssl x509 -in "$SELF_DIR/acme/live/$domain/cert.pem" -checkend 1209600 -noout; then
        self_cert_alert
        rc=1
    fi
    local result=passed tmp
    (( rc == 0 )) || result=failed
    tmp="$(mktemp "$SELF_DIR/.renew.XXXXXX")" || return 1
    jq -n --arg domain "$domain" --arg result "$result" --arg time "$(date -u +%FT%TZ)" \
        '{domain:$domain,result:$result,time:$time}' > "$tmp" && mv "$tmp" "$SELF_DIR/renew-status.json"
    if (( rc )); then logger -p daemon.err -t vless-reality-cert -- "证书续期失败：$domain；请以 root 检查项目私有日志。"; fi
    return "$rc"
)
self_renew_test() {
    local domain="$1" result=failed tmp
    [[ -x "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx" ]] && self_file_owned "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx" && self_certbot renew --dry-run --non-interactive --cert-name "$domain" > "$SELF_DIR/logs/renew-test.log" 2>&1 \
        && "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx" >> "$SELF_DIR/logs/renew-test.log" 2>&1 \
        && self_wait_tls "$domain" && result=passed
    tmp="$(mktemp "$SELF_DIR/.renew.XXXXXX")" || return 1
    jq -n --arg domain "$domain" --arg result "$result" --arg date "$(date -u +%FT%TZ)" \
        '{domain:$domain,result:$result,time:$date}' > "$tmp" && mv -f "$tmp" "$SELF_DIR/renew-test.json"
    [[ "$result" == passed ]]
}
cert_status() {
    self_exists || { warn '未发现本脚本的自有域名证书。'; return 1; }
    local domain
    domain="$(self_state domain)" || return 1
    say "证书域名：$domain"
    openssl x509 -in "$SELF_DIR/acme/live/$domain/cert.pem" -noout -issuer -enddate -checkhost "$domain" || return 1
    if systemctl is-enabled --quiet vless-reality-cert.timer && systemctl is-active --quiet vless-reality-cert.timer; then
        ok '续期任务：已启用且运行中（每日两次，带随机延迟）'
    else warn '失败：证书续期 timer 未启用或未运行。'; fi
    if [[ ! -x "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx" ]] || ! self_file_owned "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx"; then warn '失败：证书 reload hook 缺失或已被修改。'; fi
    if [[ -f "$SELF_DIR/renew-status.json" ]]; then jq -r '"最近自动续期：\(.result) / \(.time)"' "$SELF_DIR/renew-status.json"; fi
    if [[ -f "$SELF_DIR/renew-test.json" ]]; then jq -r '"最近续期测试：\(.result) / \(.time) / \(.domain)"' "$SELF_DIR/renew-test.json"; else warn '未验证：尚无续期测试记录。'; fi
    if self_tls_check "$domain" 127.0.0.1:8443 && self_loaded_cert_matches "$domain"; then ok 'Nginx 证书加载：有效且匹配域名'; else warn '失败：Nginx TLS/证书检查未通过'; fi
    if ! openssl x509 -in "$SELF_DIR/acme/live/$domain/cert.pem" -checkend 1209600 -noout >/dev/null; then warn '警告：证书不足 14 天有效期。'; fi
}
cert_command() {
    need_root
    [[ $# -le 1 ]] || fail '用法：cert [status|renew-test]'
    self_exists || fail '仅自有域名模式有本脚本管理的证书。'
    case "${1:-status}" in
        status) cert_status ;;
        renew-test) if ( exec 8> "$SELF_DIR/operation.lock"; flock -x 8; self_renew_test "$(self_state domain)" ); then ok '证书续期 dry-run 和 Nginx reload hook 均通过。';
            else fail "续期验证失败；详见 $SELF_DIR/logs/renew-test.log（root 专用）。"; fi ;;
        *) fail '用法：cert [status|renew-test]' ;;
    esac
}
website_status() {
    need_root; load_metadata
    [[ "$NODE_MODE" == self ]] || fail '此命令仅用于自有域名模式。'
    local SELF_CHECK_FAILURES=0
    say "网站：https://$SNI（本机 127.0.0.1:8443）"
    self_report 'Nginx 服务运行' systemctl is-active --quiet nginx
    self_report '8443 仅回环监听' self_listener_check
    self_report 'TLS 1.3 / X25519 / H2 与证书' self_tls_check "$SNI" 127.0.0.1:8443
    self_report '首页 HTTP/2 200，无跳转' self_http_check "$SNI" 127.0.0.1 8443
    (( SELF_CHECK_FAILURES == 0 ))
}
self_prepare() {
    local active=false enabled=false had_nginx=false token=''
    systemctl is-active --quiet nginx && active=true
    systemctl is-enabled --quiet nginx && enabled=true
    command -v nginx >/dev/null && had_nginx=true
    if [[ "$had_nginx" == true && "$active" == false ]] && self_nginx_shared; then
        fail 'Nginx 已有启用站点但服务未运行；请先处理已有站点，避免启动未审查的公网入口。'
    fi
    SELF_STARTED=1
    install -d -m 700 "$SELF_DIR" "$SELF_DIR/logs" "$SELF_DIR/work" "$SELF_DIR/acme"
    printf 'vless-reality-self-v1\n' > "$SELF_DIR/.owned"
    : > "$SELF_DIR/files.sha256"
    : > "$SELF_DIR/cli.ini"
    self_track "$SELF_DIR/cli.ini"
    jq -n --arg domain "$SNI" --arg method "$SELF_METHOD" --arg email "$SELF_EMAIL" \
        --argjson active "$active" --argjson enabled "$enabled" --argjson had "$had_nginx" \
        '{domain:$domain,method:$method,email:$email,nginx_active:$active,nginx_enabled:$enabled,had_nginx:$had}' > "$SELF_DIR/state.json"
    self_track "$SELF_DIR/state.json"
    if [[ "$SELF_METHOD" == cloudflare ]]; then
        if [[ -n "$SELF_CREDENTIALS" ]]; then
            [[ -f "$SELF_CREDENTIALS" && ! -L "$SELF_CREDENTIALS" && "$(stat -c %u "$SELF_CREDENTIALS")" == 0 \
                && "$(stat -c %a "$SELF_CREDENTIALS")" == 600 ]] || fail 'Cloudflare 凭据文件必须为 root 所有的 600 普通文件。'
            token="$(sed -n 's/^dns_cloudflare_api_token *= *\([A-Za-z0-9_-]*\) *$/\1/p' "$SELF_CREDENTIALS")"
        else
            [[ -t 0 ]] || fail '非交互 DNS-01 需要设置 VLESS_CF_CREDENTIALS 为 root:600 凭据文件路径。'
            read -r -s -p 'Cloudflare API Token（仅此 Zone 的 DNS Edit + Zone Read，不回显）：' token || fail '已取消。'
            say
        fi
        [[ "$token" =~ ^[A-Za-z0-9_-]{20,200}$ ]] || fail 'Cloudflare Token 格式无效。'
        printf 'dns_cloudflare_api_token = %s\n' "$token" > "$SELF_DIR/cloudflare.ini"
        chmod 600 "$SELF_DIR/cloudflare.ini"
        unset token
        self_track "$SELF_DIR/cloudflare.ini"
    fi
    self_extra_dependencies || fail '自有域名依赖安装失败。'
    self_dns_check "$SNI" || fail 'DNS 检查未通过。'
    curl --version | grep -q HTTP2 || fail '系统 curl 必须支持 HTTP/2。'
    # 只处理本次新安装软件包创建的默认入口，预存站点不动。
    if [[ "$had_nginx" == false && -L /etc/nginx/sites-enabled/default ]]; then
        readlink /etc/nginx/sites-enabled/default > "$SELF_DIR/default-target"
        self_track "$SELF_DIR/default-target"
        rm -- /etc/nginx/sites-enabled/default
    fi
    nginx -T 2>&1 | grep -F 'include /etc/nginx/conf.d/*.conf;' >/dev/null || fail 'Nginx 主配置未包含 conf.d/*.conf，未修改已有主配置。'
    self_site_write
    if [[ "$SELF_METHOD" == http ]]; then
        if ! { self_nginx_write "$SNI" no && self_nginx_apply; }; then fail 'HTTP-01 验证入口启动失败。'; fi
        self_http_challenge_check "$SNI" "$SERVER_IP" || fail 'HTTP-01 的公网地址回访失败；请检查 TCP 80 安全组、防火墙和路由。'
    fi
    self_issue_cert "$SNI" || fail "LE 证书申请失败；详见 $SELF_DIR/logs/issue.log。"
    if ! { self_nginx_write "$SNI" && self_nginx_apply; }; then fail 'Nginx HTTPS 配置或启动失败。'; fi
    systemctl enable nginx || fail '无法启用 Nginx 开机启动。'
    if ! { self_wait_tls "$SNI" && self_listener_check; }; then fail '本地 TLS 1.3 / X25519 / H2 / 证书 / HTTP 200 检查失败。'; fi
    self_reload_hook_write || fail '自动续期 hook 配置失败。'
    self_renew_test "$SNI" || fail '证书续期 dry-run 或 reload hook 失败。'
    self_timer_write || fail '自动续期任务配置失败。'
    if ! { systemctl is-enabled --quiet vless-reality-cert.timer && systemctl is-active --quiet vless-reality-cert.timer; }; then fail '续期 timer 未实际生效。'; fi
    ok '证书自动续期配置成功（dry-run 与 reload hook 已验证）。'
}
install_self() (
    need_root
    [[ $- != *x* ]] || fail '包含 DNS 凭据的安装禁止使用 bash -x。'
    [[ $# -le 7 ]] || fail '用法：install-self [域名] [cloudflare|http] [邮箱] [名称] [TFO:on|off] [加密:on|off] [模式]'
    [[ $# -lt 7 || "${6:-off}" == on ]] || fail '指定加密模式时须同时开启 VLESS Encryption。'
    NODE_MODE=self
    local domain="${1:-}" method="${2:-}" email="${3:-}" name="${4:-Reality-Self}" tfo="${5:-off}" enc="${6:-off}" mode="${7:-native}" answer args=()
    if [[ -z "$domain" ]]; then
        [[ -t 0 ]] || fail '请指定自有域名。'
        read -r -p '自有域名（A 直连 VPS，无 AAAA / CNAME / CDN）：' domain || fail '已取消。'
        read -r -p '证书验证 [cloudflare DNS-01 / http HTTP-01]（回车 cloudflare）：' method || fail '已取消。'
        method="${method:-cloudflare}"
        read -r -p 'LE 通知邮箱：' email || fail '已取消。'
        read -r -p '节点名称（回车 Reality-Self）：' answer || fail '已取消。'
        name="${answer:-Reality-Self}"
        if confirm '是否开启 TCP Fast Open？默认关闭 [y/N]：'; then tfo=on; fi
        if confirm '是否开启 VLESS Encryption？默认关闭 [y/N]：'; then
            enc=on; show_vlessenc_modes
            read -r -p '选择模式（回车 native）：' mode || fail '已取消。'
            mode="${mode:-native}"
        fi
        say "自有域名 $domain；公网 443 → 本机 8443；证书方式 $method。"
        confirm '同意 LE 服务条款并开始安装？[y/N]：' || return 0
    fi
    SELF_METHOD="$method"; SELF_EMAIL="$email"; SELF_CREDENTIALS="${VLESS_CF_CREDENTIALS:-}"
    domain="${domain,,}"
    args=(443 "$domain" "$name" "$tfo" "$enc")
    [[ "$enc" != on ]] || args+=("$mode")
    install_node "${args[@]}"
)

self_cleanup_preflight() {
    [[ -e "$SELF_DIR" || -L "$SELF_DIR" ]] || return 0
    self_exists || { warn '自有域名目录无有效归属记录，未删除。' >&2; return 1; }
    [[ -f "$SELF_DIR/files.sha256" && ! -L "$SELF_DIR/files.sha256" ]] || return 1
    local _sum path reference entry
    for path in "$SELF_WEB" "$SELF_DIR/acme" "$SELF_DIR/logs" "$SELF_DIR/work"; do
        [[ ! -L "$path" ]] || { warn "管理目录已变成符号链接，保留：$path" >&2; return 1; }
    done
    while read -r _sum path; do
        case "$path" in
            "$SELF_POLICY"|"$SELF_SITE"|"$SELF_WEB/index.html"|"$SELF_DIR/cli.ini"|"$SELF_DIR/state.json"|"$SELF_DIR/default-target"|"$SELF_DIR/cloudflare.ini"|"$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx"|"$SELF_RENEW_SERVICE"|"$SELF_RENEW_TIMER"|"${SELF_RENEW_SERVICE%.service}-alert.service") ;;
            *) warn '归属清单中出现未知路径，未继续清理。' >&2; return 1 ;;
        esac
        self_file_owned "$path" || { warn "文件已被修改或不是普通文件，保留：$path" >&2; return 1; }
    done < "$SELF_DIR/files.sha256"
    for path in "$SELF_SITE" "$SELF_RENEW_SERVICE" "$SELF_RENEW_TIMER" "${SELF_RENEW_SERVICE%.service}-alert.service"; do
        self_file_owned "$path" || return 1
    done
    for entry in "$SELF_DIR"/* "$SELF_DIR"/.[!.]*; do
        [[ -e "$entry" || -L "$entry" ]] || continue
        case "${entry##*/}" in
            .owned|.receipt.??????|.renew.??????|files.sha256|cli.ini|state.json|cloudflare.ini|default-target|renew-test.json|renew-status.json|operation.lock|acme|logs|work) ;;
            *) warn "自有域名目录含有未知文件，已保留：$entry" >&2; return 1 ;;
        esac
    done
    if [[ -d "$SELF_WEB" ]]; then
        while IFS= read -r path; do
            case "$path" in "$SELF_WEB/index.html"|"$SELF_WEB/.well-known"|"$SELF_WEB/.well-known/acme-challenge"|"$SELF_WEB/.well-known/acme-challenge/"*) ;;
                *) warn "网站目录有其他数据，已保留：$path" >&2; return 1 ;; esac
        done < <(find "$SELF_WEB" -mindepth 1 -print)
    fi
    # 检测常见 Web 服务是否引用了本项目网站或证书，防止删除共享资源。
    for entry in /etc/nginx /etc/apache2 /etc/caddy /etc/haproxy; do
        [[ -d "$entry" ]] || continue
        while IFS= read -r reference; do
            [[ "$reference" == "$SELF_SITE" ]] || { warn "其他配置引用自有域名资源，已保留：$reference" >&2; return 1; }
        done < <(grep -rlF -e "$SELF_DIR/acme" -e "$SELF_WEB" "$entry" 2>/dev/null || true)
    done
}
self_nginx_shared() {
    local entry
    for entry in /etc/nginx/conf.d/*.conf /etc/nginx/sites-enabled/*; do
        [[ -e "$entry" || -L "$entry" ]] || continue
        [[ "$entry" == "$SELF_SITE" ]] || return 0
    done
    return 1
}
self_cleanup() (
    [[ -e "$SELF_DIR" || -L "$SELF_DIR" ]] || return 0
    self_cleanup_preflight || return 1
    if (( SELF_OPERATION_LOCKED == 0 )); then
        exec 8> "$SELF_DIR/operation.lock"
        flock -x 8 || return 1
    fi
    self_cleanup_preflight || return 1
    local unit active=false enabled=false
    active="$(self_state nginx_active)" || return 1
    enabled="$(self_state nginx_enabled)" || return 1
    # 先停专用续期任务，绝不操作共享的 certbot.timer。
    for unit in vless-reality-cert.timer vless-reality-cert.service vless-reality-cert-alert.service; do
        if systemctl is-active --quiet "$unit"; then systemctl stop "$unit" || return 1; fi
    done
    if systemctl is-enabled --quiet vless-reality-cert.timer; then systemctl disable vless-reality-cert.timer || return 1; fi
    if [[ -f "$SELF_SITE" ]]; then
        cp -a "$SELF_SITE" "$SELF_DIR/work/site-before-cleanup"
        rm -- "$SELF_SITE" || return 1
    fi
    if [[ "$active" == false ]] && ! self_nginx_shared; then
        if systemctl is-active --quiet nginx; then systemctl stop nginx || return 1; fi
        if [[ "$enabled" == false ]] && systemctl is-enabled --quiet nginx; then systemctl disable nginx || return 1; fi
    elif systemctl is-active --quiet nginx; then
        [[ "$active" != false ]] || warn 'Nginx 现由其他站点共享，保留它的运行及开机状态。' >&2
        if ! nginx -t || ! systemctl reload nginx; then
            if [[ -f "$SELF_DIR/work/site-before-cleanup" ]]; then cp -a "$SELF_DIR/work/site-before-cleanup" "$SELF_SITE"; fi
            warn 'Nginx 移除站点后重载失败，已恢复站点；保留全部证书供修复。' >&2
            return 1
        fi
    fi
    if [[ -f "$SELF_DIR/default-target" && ! -e /etc/nginx/sites-enabled/default && ! -L /etc/nginx/sites-enabled/default ]]; then
        ln -s "$(< "$SELF_DIR/default-target")" /etc/nginx/sites-enabled/default || return 1
    fi
    rm -f -- "$SELF_RENEW_SERVICE" "$SELF_RENEW_TIMER" "${SELF_RENEW_SERVICE%.service}-alert.service" || return 1
    systemctl daemon-reload || return 1
    # 专用目录在创建时必须不存在，且上面已验证归属、额外数据和共享引用。
    if awk -v path="$SELF_POLICY" 'substr($0,67)==path {found=1} END {exit !found}' "$SELF_DIR/files.sha256"; then
        self_file_owned "$SELF_POLICY" && rm -f -- "$SELF_POLICY" || return 1
    fi
    rm -rf -- "$SELF_WEB" "$SELF_DIR" || return 1
    [[ ! -e "$SELF_SITE" && ! -e "$SELF_WEB" && ! -e "$SELF_DIR" ]]
)
stop_client_residue() {
    local dir="$1" pid start actual state attempt
    [[ -f "$dir/client.pid" && ! -L "$dir/client.pid" ]] || return 0
    read -r pid start < "$dir/client.pid" || return 1
    [[ "$pid" =~ ^[0-9]+$ && "$start" =~ ^[0-9]+$ ]] && (( pid > 1 )) || return 1
    [[ -r "/proc/$pid/stat" ]] || return 0
    state="$(awk '{print $3}' "/proc/$pid/stat")" || return 1
    [[ "$state" != Z ]] || return 0
    actual="$(awk '{print $22}' "/proc/$pid/stat")" || return 1
    [[ "$actual" == "$start" ]] || return 0
    local args=()
    mapfile -d '' -t args < "/proc/$pid/cmdline" || return 1
    [[ "${args[1]:-}" == run && "${args[2]:-}" == -config && "${args[3]:-}" == "$dir/client.json" \
        && "$(stat -c %u "/proc/$pid")" == "$EUID" ]] || return 1
    kill "$pid" 2>/dev/null || return 1
    for attempt in {1..10}; do
        [[ -r "/proc/$pid/stat" ]] || return 0
        state="$(awk '{print $3}' "/proc/$pid/stat" 2>/dev/null)" || return 0
        [[ "$state" != Z ]] || return 0
        sleep 0.2
    done
    return 1
}
self_client_probe() (
    local domain="$1" address="$2" server_port="${3:-443}" test_dir pid='' socks_port uuid
    test_dir="$(mktemp -d /tmp/vless-reality-client.XXXXXX)" || return 1
    trap 'rc=$?; trap - EXIT
        if [[ -n "$pid" ]]; then
            if stop_client_residue "$test_dir"; then wait "$pid" 2>/dev/null || true;
            else warn "检查客户端未能安全停止；保留归属目录供卸载重试：$test_dir" >&2; exit 1; fi
        fi
        rm -rf -- "$test_dir"; exit "$rc"' EXIT
    printf 'vless-reality-setup\n' > "$test_dir/.vless-reality-owned"
    socks_port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')" || return 1
    uuid="$(config_uuid)" || return 1
    jq -n --arg id "$uuid" --arg host "$address" --argjson port "$server_port" --argjson socks "$socks_port" \
        --arg sni "$domain" --arg pub "$PUBLIC_KEY" --arg sid "$SHORT_ID" --arg enc "$CLIENT_ENCRYPTION" '{
        log:{loglevel:"warning"}, inbounds:[{listen:"127.0.0.1",port:$socks,protocol:"socks",settings:{auth:"noauth"}}],
        outbounds:[{protocol:"vless",settings:{vnext:[{address:$host,port:$port,users:[{id:$id,flow:"xtls-rprx-vision",encryption:$enc}]}]},
          streamSettings:{network:"tcp",security:"reality",realitySettings:{serverName:$sni,fingerprint:"chrome",publicKey:$pub,shortId:$sid}}}]
        }' > "$test_dir/client.json" || return 1
    "$XRAY_BIN" run -test -config "$test_dir/client.json" > "$test_dir/test.log" 2>&1 || return 1
    "$XRAY_BIN" run -config "$test_dir/client.json" > "$test_dir/client.log" 2>&1 &
    pid=$!
    printf '%s %s\n' "$pid" "$(awk '{print $22}' "/proc/$pid/stat")" > "$test_dir/client.pid"
    local attempt
    for attempt in 1 2 3 4 5; do
        if curl --noproxy '' --proxy "socks5h://127.0.0.1:$socks_port" -fsS --connect-timeout 5 --max-time 20 \
            'https://www.debian.org/' -o /dev/null 2>/dev/null; then
            kill -0 "$pid" 2>/dev/null && return 0
            return 1
        fi
        kill -0 "$pid" 2>/dev/null || return 1
        sleep 1
    done
    return 1
)
self_reject_check() {
    local domain="$1" output
    output="$(timeout 10 openssl s_client -connect 127.0.0.1:8443 -servername invalid.example -tls1_3 </dev/null 2>&1 || true)"
    [[ "$output" == *'no peer certificate available'* ]] || return 1
    output="$(timeout 10 openssl s_client -connect 127.0.0.1:8443 -noservername -tls1_3 </dev/null 2>&1 || true)"
    [[ "$output" == *'no peer certificate available'* && "$domain" != invalid.example ]]
}
self_report() {
    local label="$1"; shift
    if "$@"; then ok "通过：$label"; else warn "失败：$label"; SELF_CHECK_FAILURES=$((SELF_CHECK_FAILURES + 1)); fi
}
self_config_check() {
    jq -e --arg sni "$SNI" '
      [.inbounds[] | select(.protocol=="vless" and .listen=="0.0.0.0" and .port==443) |
        select(.streamSettings.network=="tcp" and .streamSettings.security=="reality") |
        select(.streamSettings.realitySettings.target=="127.0.0.1:8443") |
        select(.streamSettings.realitySettings.serverNames==[$sni]) |
        select(any(.settings.clients[]; .flow=="xtls-rprx-vision"))] | length==1' "$CONFIG" >/dev/null && config_ok
}
self_renew_ready() {
    if systemctl is-failed --quiet vless-reality-cert.service; then return 1; fi
    if [[ -f "$SELF_DIR/renew-status.json" ]] && jq -e --arg domain "$SNI" '.domain==$domain and .result=="failed"' "$SELF_DIR/renew-status.json" >/dev/null; then return 1; fi
    systemctl is-enabled --quiet vless-reality-cert.timer && systemctl is-active --quiet vless-reality-cert.timer \
        && jq -e --arg domain "$SNI" '.result=="passed" and .domain==$domain' "$SELF_DIR/renew-test.json" >/dev/null \
        && [[ -x "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx" ]] && self_file_owned "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx"
}
check_self() {
    need_root; load_metadata
    [[ "$NODE_MODE" == self ]] || fail 'check-self 只用于自有域名模式。'
    local SELF_CHECK_FAILURES=0 ip external="${VLESS_EXTERNAL_CHECK:-}"
    ip="$(public_ipv4)" || fail '无法确认当前公网 IPv4。'
    self_report 'DNS A 直连当前 VPS、无 CNAME/CDN、无 AAAA（两个解析器）' self_dns_check "$SNI"
    self_report 'Xray TCP 443 服务和监听' service_ok
    self_report 'Nginx 8443 仅 IPv4 回环监听' self_listener_check
    self_report 'REALITY 本机 target、域名和 Vision 配置' self_config_check
    self_report 'Nginx TLS 1.3 / X25519 / ALPN h2 / 证书链与域名' self_tls_check "$SNI" 127.0.0.1:8443
    self_report 'Nginx 已加载磁盘上的当前证书' self_loaded_cert_matches "$SNI"
    self_report '本机网站 HTTP/2 200，无跳转' self_http_check "$SNI" 127.0.0.1 8443
    self_report '拒绝未知 SNI 和无 SNI' self_reject_check "$SNI"
    self_report '公网地址 443 HTTPS 回落（检测源为本机）' self_http_check "$SNI" "$ip" 443
    self_report '证书 timer、最近续期 dry-run 与 deploy hook 记录' self_renew_ready
    self_report '实际 Xray 客户端 REALITY + Vision 握手和 HTTPS 代理请求（本机源）' self_client_probe "$SNI" 127.0.0.1
    if [[ -n "$external" ]]; then
        if [[ -x "$external" && -f "$external" && ! -L "$external" && "$(stat -c %u "$external")" == 0 \
            && "$(stat -c %a "$external")" =~ ^[57]00$ ]]; then
            self_report '用户配置的外部网络验证程序' timeout 120 "$external" "$SNI" "$ip"
        else warn '失败：外部验证程序需为 root:700 的普通可执行文件。'; SELF_CHECK_FAILURES=$((SELF_CHECK_FAILURES + 1)); fi
    else
        warn '未验证：真正外部网络的 HTTPS/VLESS 连接。请从其他网络访问并导入测试；可用 VLESS_EXTERNAL_CHECK 配置外部验证程序。'
    fi
    (( SELF_CHECK_FAILURES == 0 ))
}
change_self_domain() {
    local domain="${1:-}" script_path
    if [[ -z "$domain" ]]; then
        [[ -t 0 ]] || fail '请指定新自有域名；不支持 auto。'
        read -r -p '新自有域名（将同步证书、网站与 Xray）：' domain || fail '已取消。'
    fi
    domain="${domain,,}"
    valid_host "$domain" || fail '新自有域名格式无效；自有域名模式不允许 auto。'
    [[ "$domain" != "$SNI" ]] || { ok '域名未改变。'; return 0; }
    script_path="$(readlink -f "$SCRIPT_PATH")" || fail '找不到当前脚本。'
    warn '即将申请新证书并重启 Xray；请使用 VPS 直连 SSH。成功后须重新导入链接。'
    systemd-run --quiet --wait --collect --unit=vless-reality-self-change \
        /bin/bash "$script_path" __self-domain "$domain" || fail '域名修改失败；查看 journalctl -u vless-reality-self-change。'
    show_node
}
self_domain_apply() (
    need_root; load_metadata
    [[ "$NODE_MODE" == self && $# == 1 ]] || fail '仅自有域名模式支持同步域名修改。'
    self_cleanup_preflight || fail '管理文件已改变，无法安全修改。'
    exec 8> "$SELF_DIR/operation.lock"; flock -x 8 || exit 1
    local domain="${1,,}" old_sni="$SNI" backup committed=0 active=0 timer_active=0
    valid_host "$domain" || fail '域名无效。'
    self_dns_check "$domain" || fail '新域名 DNS 检查失败。'
    SELF_METHOD="$(self_state method)"; SELF_EMAIL="$(self_state email)"
    backup="$(mktemp -d "$SELF_DIR/work/domain-backup.XXXXXX")"
    backup_state "$backup" || fail '无法备份节点。'
    cp -a "$SELF_SITE" "$backup/nginx-site.conf"
    cp -a "$SELF_DIR/state.json" "$SELF_DIR/files.sha256" "$backup/"
    [[ ! -f "$SELF_DIR/renew-test.json" ]] || cp -a "$SELF_DIR/renew-test.json" "$backup/"
    [[ ! -f "$LINK_FILE" ]] || cp -a "$LINK_FILE" "$backup/link.txt"
    systemctl is-active --quiet xray && active=1
    systemctl is-active --quiet vless-reality-cert.timer && timer_active=1
    # trap 的恢复不能依赖 SSH 会话；本函数由独立 systemd 任务运行。
    trap 'rc=$?; trap - EXIT; if (( ! committed )); then
        cp -a "$backup/nginx-site.conf" "$SELF_SITE" || rc=1
        cp -a "$backup/state.json" "$backup/files.sha256" "$SELF_DIR/" || rc=1
        if [[ -f "$backup/renew-test.json" ]]; then cp -a "$backup/renew-test.json" "$SELF_DIR/"; else rm -f "$SELF_DIR/renew-test.json"; fi
        SNI="$old_sni"
        if ! nginx -t || ! systemctl reload nginx || ! restore_state "$backup" "$active"; then
            warn "域名修改回滚未完成，备份保留：$backup" >&2; exit 1
        fi
        [[ ! -f "$backup/link.txt" ]] || cp -a "$backup/link.txt" "$LINK_FILE"
    fi
    if (( timer_active )); then systemctl start vless-reality-cert.timer || rc=1; fi
    rm -rf -- "$backup"; exit "$rc"' EXIT
    if (( timer_active )); then systemctl stop vless-reality-cert.timer; fi
    if systemctl is-active --quiet vless-reality-cert.service; then systemctl stop vless-reality-cert.service; fi
    if [[ "$SELF_METHOD" == http ]]; then
        if ! { self_nginx_write "$old_sni" yes "$domain" && self_nginx_apply; }; then fail '新域名 HTTP 验证入口失败。'; fi
    fi
    self_issue_cert "$domain" || fail '新域名证书申请失败。'
    if ! { self_nginx_write "$domain" && self_nginx_apply; }; then fail '新域名 Nginx 配置失败。'; fi
    if ! { self_wait_tls "$domain"; }; then fail '新域名网站验证失败。'; fi
    SNI="$domain"
    edit_config --arg sni "$SNI" '(.inbounds[] | select(.protocol=="vless") | .streamSettings.realitySettings.serverNames)=[$sni] |
        (.inbounds[] | select(.protocol=="vless") | .streamSettings.realitySettings.target)="127.0.0.1:8443"' || fail '新域名 Xray 修改失败。'
    if ! { write_marker && config_ok; }; then fail '新域名 Xray 配置校验失败。'; fi
    if (( active )); then
        if ! systemctl restart xray || ! wait_service 10; then fail '新域名节点启动失败。'; fi
    fi
    self_renew_test "$domain" || fail '新域名证书续期验证失败。'
    jq --arg domain "$domain" '.domain=$domain' "$SELF_DIR/state.json" > "$backup/new-state.json"
    mv "$backup/new-state.json" "$SELF_DIR/state.json"
    self_track "$SELF_DIR/state.json"
    (show_node >/dev/null) || fail '新域名链接保存失败。'
    if (( active )); then self_client_probe "$domain" 127.0.0.1 || fail '新域名节点实际握手失败。'; fi
    # shellcheck disable=SC2034 # 由 EXIT trap 读取。
    committed=1
    ok '自有域名的证书、Nginx、Xray 和客户端链接已同步修改。'
)

print_help() {
    local cmd
    cmd="$(cmd_name)"
    cat <<EOF
VLESS + REALITY + Vision 节点管理脚本 v${SCRIPT_VERSION}
用法：${cmd} [命令]
  install [端口] [SNI] [名称] [TFO:on|off] [VLESS加密:on|off] [模式]  安装节点
  install-self [域名] [cloudflare|http] [邮箱] [名称] [TFO] [加密] [模式]
                               安装自有域名 REALITY（固定 443）
  check-self                   检查自有域名完整部署
  cert [status|renew-test]      证书和自动续期状态
  website                      查看本地网站状态
  show                         显示 vless:// 导入链接
  status                       查看服务、配置、端口和伪装站点状态
  port [新端口]                修改端口
  sni [新域名|auto]            修改或自动优选 REALITY 伪装域名
  sni-best                     查看当前测速延迟最低的域名，不修改节点
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
    if [[ -t 1 ]]; then clear 2>/dev/null || true; fi
    say '=================================='
    say " VLESS + REALITY + Vision ${RED}[v${SCRIPT_VERSION}]${RESET}"
    say '=================================='
    say '  1. 安装普通 REALITY（第三方 SNI）'
    say ' 20. 安装自有域名 REALITY（偷自己）'
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
    say ' 19. 开关 VLESS Encryption / 修改模式'
    say ' 21. 查看自有域名网站状态'
    say ' 22. 查看 SSL 证书'
    say ' 23. 测试证书自动续期'
    say ' 24. 一键检查自有域名配置'
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
        17) tfo_node ;; 19) vlessenc_node ;;
        20) install_self ;; 21) website_status ;; 22) cert_command status ;;
        23) cert_command renew-test ;; 24) check_self ;; *) return 2 ;;
    esac
}
interactive_menu() {
    if [[ ! -t 0 ]]; then print_help; return 0; fi
    need_root
    if [[ -f "$MARKER" ]]; then ensure_shortcut quiet || true; fi
    local choice rc
    while true; do
        show_menu
        read -r -p '请输入数字 [1-17、19-24，00 退出]：' choice || { say; return 0; }
        case "$choice" in 00|q|Q) return 0 ;; [1-9]|1[0-7]|19|2[0-4]) ;; *) warn '请输入菜单中的数字。'; sleep 1; continue ;; esac
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
        install-self) shift; install_self "$@" ;;
        check-self) check_self ;;
        website) website_status ;;
        cert) shift; cert_command "$@" ;;
        __self-domain) shift; self_domain_apply "$@" ;;
        __cert-renew) self_cert_renew ;;
        __cert-alert) self_cert_alert ;;
        show) show_node ;;
        status) status_node ;;
        port) shift; change_port "$@" ;;
        sni) shift; change_sni "$@" ;;
        sni-best) show_fastest_sni ;;
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
        [1-9]|1[0-7]|19|2[0-4]) need_root; menu_action "$1" ;;
        *) print_help; exit 2 ;;
    esac
}

main "$@"
