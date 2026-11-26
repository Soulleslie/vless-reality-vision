#!/usr/bin/env bash
# VLESS + REALITY + Vision 节点管理脚本：Debian/Ubuntu + Xray-core。
# 请先下载为普通文件后运行，不支持 curl | bash（安装过程需要读取终端输入）。
# shellcheck disable=SC2030,SC2031 # 自有域名操作用子 shell 隔离状态，持久化通过安装记录重新读取。
# shellcheck disable=SC2016 # 下方单引号内的 $name 是 jq 变量，不由 Bash 展开。
set -Eeuo pipefail
umask 077

SCRIPT_VERSION='2.6.0'
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
ADDR_MODE='auto'
ADDR_DOMAIN=''
XHTTP_PATH=''
SELF_DIR='/etc/vless-reality-self'
SELF_SITE='/etc/nginx/conf.d/vless-reality-self.conf'
SELF_WEB='/var/www/vless-reality-self'
SELF_RENEW_SERVICE='/etc/systemd/system/vless-reality-cert.service'
SELF_RENEW_TIMER='/etc/systemd/system/vless-reality-cert.timer'
SELF_METHOD=''
SELF_EMAIL=''
SELF_CREDENTIALS=''
SELF_INPUT_DOMAIN=''
SELF_STARTED=0
SELF_OPERATION_LOCKED=0
SELF_POLICY='/usr/sbin/policy-rc.d'
VLESS_APT_INDEX_READY=0
VLESS_APT_INDEX_AT=0
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
valid_ipv4() {
    local part parts=()
    [[ "$1" =~ ^(0|[1-9][0-9]{0,2})([.](0|[1-9][0-9]{0,2})){3}$ ]] || return 1
    IFS=. read -r -a parts <<< "$1"
    for part in "${parts[@]}"; do (( 10#$part <= 255 )) || return 1; done
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
        if valid_ipv4 "$ip"; then
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

apt_update_once() {
    # 仅复用当前执行链 5 分钟内成功刷新的索引；长时间等待用户输入后重新刷新。
    if (( VLESS_APT_INDEX_READY == 0 || SECONDS < VLESS_APT_INDEX_AT || SECONDS - VLESS_APT_INDEX_AT >= 300 )); then
        VLESS_APT_INDEX_READY=0
        apt-get update || return 1
        VLESS_APT_INDEX_AT="$SECONDS"
        VLESS_APT_INDEX_READY=1
    fi
    return 0
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
        apt_update_once || fail '更新软件包索引失败。'
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
# 补满 16 个探测名额，完成一个即可补下一个；不再让每批快任务等待同批最慢任务。
sni_wait_any_supported() {
    (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1) ))
}
sni_wait_slot() {
    local -n pool="$1"
    local active pid remaining=()
    if (( ${#pool[@]} < 16 )); then return 0; fi
    # 旧 Bash 沿用批次等待，避免旧版 wait -n 不支持限定 PID 列表时误等其他子进程。
    if ! sni_wait_any_supported; then
        for pid in "${pool[@]}"; do wait "$pid" || true; done
        pool=()
        return 0
    fi
    while (( ${#pool[@]} >= 16 )); do
        wait -n "${pool[@]}" 2>/dev/null || true
        active=" $(jobs -pr) "
        active="${active//$'\n'/ }"
        remaining=()
        for pid in "${pool[@]}"; do
            if [[ "$active" == *" $pid "* ]]; then remaining+=("$pid");
            else wait "$pid" 2>/dev/null || true; fi
        done
        pool=("${remaining[@]}")
    done
}
sni_probe_round() {
    local dir="$1" prefix="$2" label="$3" index pid submitted=0 completed reported=0
    shift 3
    local total=$# pids=()
    for index in "$@"; do
        sni_wait_slot pids
        completed=$((submitted - ${#pids[@]}))
        while (( reported + 16 <= completed )); do
            (( reported += 16 ))
            say "  已${label} $reported/$total 个域名"
        done
        ( exec 7>&- 8>&- 9>&-; probe_target_latency "${SNI_CANDIDATES[index]}" > "$dir/$prefix.$index" ) &
        pids+=("$!")
        (( submitted += 1 ))
    done
    for pid in "${pids[@]}"; do wait "$pid" || true; done
    if (( reported < total )); then say "  已${label} $total/$total 个域名"; fi
    return 0
}
select_fastest_sni() {
    local first second score index line probe_dir
    local -a all_indices=() valid_indices=() ranked=() finalists=()
    say "正在从 VPS 并发初筛 ${#SNI_CANDIDATES[@]} 个域名（TLS 1.3 与证书校验）…"
    probe_dir="$(mktemp -d /tmp/vless-reality-sni.XXXXXX)" || return 1
    if ! printf '%s\n' vless-reality-setup > "$probe_dir/.vless-reality-owned"; then
        rm -rf -- "$probe_dir"
        return 1
    fi
    for ((index = 0; index < ${#SNI_CANDIDATES[@]}; index++)); do
        all_indices+=("$index")
    done
    sni_probe_round "$probe_dir" result 初筛 "${all_indices[@]}"
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
    sni_probe_round "$probe_dir" result2 复测 "${valid_indices[@]}"
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
    local tmp destination="${1:-$MARKER}" fields
    fields=("$PORT" "$SNI" "$NODE_NAME" "$SERVER_IP" "$PUBLIC_KEY" "$SHORT_ID" "$CLIENT_ENCRYPTION" "$NODE_MODE" "$ADDR_MODE" "$ADDR_DOMAIN")
    # 第 11 行保存 XHTTP Path，旧节点没有该行仍可管理。
    if [[ -n "$XHTTP_PATH" ]]; then fields+=("$XHTTP_PATH"); fi
    tmp="$(mktemp "$CONFIG_DIR/.marker.XXXXXX")" || return 1
    if printf '%s\n' "${fields[@]}" > "$tmp" \
        && chown root:xray "$tmp" && chmod 640 "$tmp" && mv -fT -- "$tmp" "$destination"; then
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
    ADDR_MODE="${lines[8]:-auto}"
    ADDR_DOMAIN="${lines[9]:-}"
    XHTTP_PATH="${lines[10]:-}"
    [[ -z "$XHTTP_PATH" || "$XHTTP_PATH" =~ ^/[0-9a-f]{24}$ ]] || fail '保存的 XHTTP Path 无效。'
    case "$NODE_MODE" in external|self) ;; *) fail '安装模式记录无效。' ;; esac
    [[ "$NODE_MODE" != self || "$PORT" == 443 ]] || fail '自有域名安装记录的端口必须为 443。'
    valid_port "$PORT" || fail '安装记录中的端口无效。'
    valid_host "$SNI" || fail '安装记录中的 SNI 无效。'
    valid_ipv4 "$SERVER_IP" || fail '安装记录中的 IPv4 地址无效。'
    case "$ADDR_MODE" in auto|ip|domain) ;; *) fail '安装记录中的客户端地址模式无效。' ;; esac
    [[ -z "$ADDR_DOMAIN" ]] || valid_host "$ADDR_DOMAIN" || fail '安装记录中的连接域名无效。'
    [[ "$NODE_MODE" != self || -z "$ADDR_DOMAIN" ]] || fail '自有域名模式的连接域名应沿用当前 SNI，请使用 sni 同步管理域名。'
    [[ "$NODE_MODE" != external || "$ADDR_MODE" != domain || -n "$ADDR_DOMAIN" ]] || fail '普通模式缺少自有连接域名。'
    [[ -n "$NODE_NAME" && -n "$SERVER_IP" && -n "$PUBLIC_KEY" && -n "$SHORT_ID" ]] \
        || fail '安装记录不完整。'
    [[ "$CLIENT_ENCRYPTION" == none || "$CLIENT_ENCRYPTION" =~ ^mlkem768x25519plus[.](native|xorpub|random)[.]0rtt[.][A-Za-z0-9_-]+$ ]] \
        || fail '安装记录中的 VLESS Encryption 参数无效。'
}

client_address_mode() {
    if [[ "$ADDR_MODE" != auto ]]; then printf '%s' "$ADDR_MODE";
    elif [[ "$NODE_MODE" == self ]]; then printf domain;
    else printf ip; fi
}
client_address() {
    if [[ "$(client_address_mode)" == ip ]]; then printf '%s' "$SERVER_IP";
    elif [[ "$NODE_MODE" == self ]]; then printf '%s' "$SNI";
    else printf '%s' "$ADDR_DOMAIN"; fi
}
client_address_status() {
    local kind='IP'
    [[ "$(client_address_mode)" != domain ]] || kind='域名'
    say "客户端连接地址：$kind $(client_address):$PORT"
}

TRANSPORT_JQ='
    def xhttp_settings:
        .path as $path | ($path|type=="string" and length==25 and test("^/[0-9a-f]{24}$"))
        and .=={path:$path,mode:"auto"};
    def managed_transport:
        .streamSettings as $stream |
        $stream.security=="reality" and (.settings.clients|length)>0 and
        (if $stream.network=="tcp" then
            ($stream|has("xhttpSettings") or has("splithttpSettings")|not) and
            all(.settings.clients[]; .flow=="xtls-rprx-vision")
         elif $stream.network=="xhttp" then
            ($stream.xhttpSettings|xhttp_settings) and ($stream|has("splithttpSettings")|not) and
            all(.settings.clients[]; (.flow // "")=="")
         else false end);
'

config_transport() {
    jq -er '[.inbounds[] | select(.protocol=="vless") | (.streamSettings.network // "tcp")][0] |
        select(.=="tcp" or .=="xhttp")' "$CONFIG"
}

config_xhttp_path() {
    jq -er "$TRANSPORT_JQ"' [.inbounds[] | select(.protocol=="vless") | .streamSettings.xhttpSettings][0] |
        select(xhttp_settings) | .path' "$CONFIG"
}

config_decryption() {
    jq -r '[.inbounds[] | select(.protocol == "vless") | .settings.decryption][0] // "none"' "$CONFIG"
}

config_uuid() {
    jq -er '[.inbounds[] | select(.protocol=="vless") |
        (if .streamSettings.network=="xhttp" then "" else "xtls-rprx-vision" end) as $flow |
        .settings.clients[] | select((.flow // "")==$flow) | .id][0]' "$CONFIG"
}

# 不把 UUID、REALITY 私钥或 VLESS 解密密钥放进外部进程的命令行。
# 临时文件与配置位于同一受保护目录；被 SIGKILL 中断时由卸载清理。
private_values_file() (
    local file
    file="$(mktemp "$CONFIG_DIR/.private.XXXXXX")" || return 1
    if ! printf '%s\n' "$@" > "$file"; then rm -f -- "$file"; return 1; fi
    printf '%s' "$file"
)
edit_config_private() (
    local filter="$1" file
    shift
    file="$(private_values_file "$@")" || return 1
    trap 'rm -f -- "$file"' EXIT
    edit_config --rawfile credentials "$file" "$filter"
)

edit_config() {
    local tmp
    tmp="$(mktemp "$CONFIG_DIR/.config.json.XXXXXX")" || return 1
    if jq "$@" "$CONFIG" > "$tmp" \
        && { [[ "$NODE_MODE" != self ]] || self_config_policy "$tmp" "$SNI"; } && chown root:xray "$tmp" && chmod 640 "$tmp" \
        && mv -f -- "$tmp" "$CONFIG"; then
        return 0
    fi
    rm -f -- "$tmp"
    return 1
}

config_ok() {
    local file="${1:-$CONFIG}"
    if [[ "$NODE_MODE" == self ]]; then
        self_config_policy "$file" "$SNI" || return 1
        if jq -e '.. | objects | select(has("limitFallbackUpload") or has("limitFallbackDownload"))' "$file" >/dev/null; then
            fallback_capability "$file" "$XRAY_BIN" || return 1
        fi
    fi
    "$XRAY_BIN" run -test -config "$file" >/dev/null 2>&1
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
    if systemctl is-failed --quiet xray; then systemctl reset-failed xray || return 1; fi
    if systemctl is-enabled --quiet xray 2>/dev/null; then
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
    if transport_pending; then
        transport_snapshot_owned "$CONFIG_DIR/.transport-pending" || return 1
        transport_discard_snapshot || return 1
    fi
    for backup in "$CONFIG_DIR"/.change-backup.??????; do
        [[ -d "$backup" && ! -L "$backup" ]] || continue
        unknown=0
        for entry in "$backup"/*; do
            case "${entry##*/}" in
                config.json|transport.json|transport-state.json|marker.next|.vless-reality-owned|tfo.sysctl|link.txt|link-output.txt) ;;
                *) unknown=1 ;;
            esac
        done
        rm -f -- "$backup/"{config.json,transport.json,transport-state.json,marker.next,.vless-reality-owned,tfo.sysctl,link.txt,link-output.txt} || return 1
        if (( unknown )); then
            warn "保留含有其他文件的备份目录：$backup" >&2
        else
            rmdir -- "$backup" || return 1
        fi
    done
    for entry in "$CONFIG_DIR"/.config.json.?????? "$CONFIG_DIR"/.private.??????; do
        [[ -f "$entry" && ! -L "$entry" ]] || continue
        [[ "$(stat -c %u -- "$entry")" == "$EUID" ]] || { warn "临时配置不属于当前用户，已保留：$entry" >&2; continue; }
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
        for file in release.json xray.zip xray xray.old client.json client.log test.log client.pid credentials; do
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
    local uuid="$1" private_key="$2" target="${SNI}:443" credentials
    [[ "$NODE_MODE" != self ]] || target=127.0.0.1:8443
    credentials="$(private_values_file "$uuid" "$private_key" "$SHORT_ID" "$VLESS_DECRYPTION")" || return 1
    if ! jq -n --rawfile credentials "$credentials" \
        --arg target "$target" --arg sni "$SNI" --argjson port "$PORT" --argjson tfo "$TFO_ENABLED" '
        ($credentials | split("\n")) as $secret |
        {
          log: {loglevel: "warning"},
          inbounds: [{
            listen: "0.0.0.0",
            port: $port,
            protocol: "vless",
            settings: {
              clients: [{id: $secret[0], flow: "xtls-rprx-vision", email: "default"}],
              decryption: $secret[3]
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
                privateKey: $secret[1],
                shortIds: [$secret[2]]
              }
            },
            sniffing: {enabled: true, destOverride: ["http", "tls", "quic"], routeOnly: true}
          }],
          outbounds: [{protocol: "freedom", tag: "direct"}, {protocol: "blackhole", tag: "blocked"}]
        }' > "$CONFIG"; then rm -f -- "$credentials"; return 1; fi
    rm -f -- "$credentials" || return 1
    chown root:xray "$CONFIG"
    chmod 640 "$CONFIG"
}

# 新安装使用的 systemd 服务。ProtectSystem 保持 full，以兼容管理员在 /var 下另行配置的日志文件；
# 其余限制只收紧 Xray 不需要的内核、设备和系统调用接口。卸载凭固定的 ExecStart 行确认归属，勿改其内容。
write_xray_service() {
    local destination="$1"
    cat > "$destination" <<'EOF' || return 1
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
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
SystemCallArchitectures=native
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 "$destination"
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
        # 在安装 Nginx/Certbot、读取 DNS Token、创建项目文件及安装回滚事务之前拦截错误域名。
        self_dns_precheck "$SNI" || fail '自有域名预检未通过；未开始部署，请修正域名或 DNS 后重试。'
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

    write_xray_service "$SERVICE" || fail '写入 Xray systemd 服务失败。'

    step '[5/5] 启动服务并检查监听端口…'
    systemctl daemon-reload
    systemctl enable --now xray
    wait_service 10 || fail "Xray 未正常监听 TCP $PORT；请查看 journalctl -u xray。"
    local self_check_rc=0
    if [[ "$NODE_MODE" == self ]]; then
        check_self || self_check_rc=$?
        case "$self_check_rc" in
            0|3) ;;
            *) fail '自有域名最终检查失败；安装将回滚。' ;;
        esac
    fi
    show_node
    ensure_shortcut || true
    INSTALL_COMMITTED=1
    trap - EXIT
    rm -rf -- "$TEMP_DIR"
    TEMP_DIR=''
    if (( self_check_rc == 3 )); then
        warn '本地部署已保留：公网 HTTPS / VLESS 连通性仍未验证（NAT 公网地址回访未通过）。'
        warn '请从其他网络访问域名并导入节点测试，检查服务商的 TCP 443 映射/安全组。不要再次安装或重复申请证书。'
        warn '可配置 VLESS_EXTERNAL_CHECK 后重新运行 check-self；当前命令退出码为 3，表示待验证，并非完整安装验证成功。'
        return 3
    fi
    ok "安装完成：Xray ${RELEASE_VERSION} 正在监听 TCP ${PORT}。"
    warn "请确认云安全组已放行 TCP ${PORT}。导入链接包含 UUID，请勿公开分享。"
}

show_node() (
    need_root
    self_operation_lock
    load_metadata
    local uuid label link tmp address enc_param transport path transport_params flow_param='' tfo_param=''
    address="$(client_address)" || return 1
    uuid="$(config_uuid)" || fail '无法从配置读取 UUID。'
    if [[ "$NODE_MODE" == self ]]; then
        [[ "$PUBLIC_KEY" =~ ^[A-Za-z0-9_-]{43}$ && "$SHORT_ID" =~ ^[0-9a-f]{16}$ ]] || fail '自有域名安装记录中的公钥或 Short ID 无效。'
        [[ "$PUBLIC_KEY" != "$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG")" ]] || fail '公钥记录错误：拒绝把 REALITY 私钥写入链接。'
    fi
    label="$(jq -rn --arg v "$NODE_NAME" '$v | @uri')" || return 1
    enc_param="$(jq -rn --arg v "$CLIENT_ENCRYPTION" '$v | @uri')" || return 1
    transport="$(config_transport)" || fail '无法识别节点传输。'
    if [[ "$transport" == xhttp ]]; then
        path="$(config_xhttp_path)" || fail '无法读取 XHTTP 路径。'
        path="$(jq -rn --arg v "$path" '$v | @uri')" || return 1
        transport_params="&type=xhttp&path=$path&mode=auto"
    else
        transport_params='&type=tcp&headerType=none'
        flow_param='&flow=xtls-rprx-vision'
    fi
    # tfo 是部分客户端识别的扩展参数；服务端开关仍以 Xray 配置为准。
    if config_tfo_enabled; then tfo_param='&tfo=1'; fi
    link="vless://${uuid}@${address}:${PORT}?encryption=${enc_param}${flow_param}&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}${transport_params}${tfo_param}#${label}"
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
)

status_node() {
    need_root
    if transport_pending; then transport_pending_message; return 3; fi
    load_metadata
    local state current_ip version flow server_enc enc_mode transport
    state="$(systemctl is-active xray 2>/dev/null || true)"
    version="$(installed_version)"
    say "服务状态：$state"
    say "Xray 版本：${version:-未知}"
    say "安装模式：$NODE_MODE"
    say "记录公网入口：${SERVER_IP}:${PORT}/TCP"
    client_address_status
    say "REALITY SNI：${SNI}:443"
    flow="$(jq -r '[.inbounds[] | select(.protocol == "vless") | .settings.clients[0].flow][0] // empty' "$CONFIG" 2>/dev/null || true)"
    transport="$(config_transport || true)"
    if [[ "$transport" == xhttp ]]; then
        say '节点传输：XHTTP + REALITY（mode=auto）'
        if [[ -n "$flow" ]]; then warn "XHTTP flow 配置异常：$flow"; fi
    elif [[ "$transport" == tcp && "$flow" == xtls-rprx-vision ]]; then
        say '节点传输：TCP + REALITY + Vision'
        ok 'Vision flow：xtls-rprx-vision'
    else
        warn "Vision flow：${flow:-未配置}"
    fi
    server_enc="$(config_decryption 2>/dev/null || true)"
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
        if [[ "$(client_address_mode)" == ip ]]; then
            warn "公网 IPv4 已变化：当前 $current_ip，链接中仍为 $SERVER_IP；请运行 $(cmd_name) refresh-ip 并重新导入链接。"
        else
            warn "公网 IPv4 已变化为 $current_ip；请核对连接域名的 A 记录，再运行 $(cmd_name) refresh-ip 更新缓存，连接地址仍保留域名。"
        fi
    fi
    if [[ "$NODE_MODE" == self ]]; then
        if self_tls_check "$SNI" 127.0.0.1:8443; then ok '本地网站：TLS 1.3 / X25519 / H2 正常'; else warn '本地网站验证失败'; fi
        self_network_status
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
# 统一的节点修改事务：先备份配置和安装记录，再执行写入命令（其余参数）。
# 写入失败立即恢复并删除备份；写入成功后由 commit_change 校验、按原状态重启并保存链接，失败同样回滚。
node_change() {
    local old_port="$1" description="$2" backup was_active=0
    shift 2
    if systemctl is-active --quiet xray; then was_active=1; fi
    backup="$(mktemp -d "$CONFIG_DIR/.change-backup.XXXXXX")" || fail '无法创建配置备份，未修改。'
    if ! backup_state "$backup"; then
        rm -rf -- "$backup"
        fail '备份节点配置失败，未修改。'
    fi
    if ! "$@"; then
        PORT="$old_port"
        restore_state "$backup" "$was_active" || fail "恢复旧配置或服务失败，备份保留在 $backup。"
        rm -rf -- "$backup"
        fail '写入修改失败，已恢复原配置。'
    fi
    commit_change "$backup" "$old_port" "$description" "$was_active"
}

transport_pending() { [[ -e "$CONFIG_DIR/.transport-pending" || -L "$CONFIG_DIR/.transport-pending" ]]; }

transport_pending_message() {
    warn "传输切换正在执行或上次未完成；待任务结束后可运行 $(cmd_name) transport recover 恢复。" >&2
}

transport_snapshot_owned() (
    local dir="$1" file
    [[ -d "$dir" && ! -L "$dir" && "$(stat -c '%u:%a' -- "$dir")" == "$EUID:700" ]] || return 1
    shopt -s nullglob dotglob
    for file in "$dir"/*; do
        case "${file##*/}" in config.json|.vless-reality-owned|link.txt|transport.json|marker.next|transport-state.json) ;; *) return 1 ;; esac
        [[ -f "$file" && ! -L "$file" && "$(stat -c %u -- "$file")" == "$EUID" ]] || return 1
    done
    [[ -f "$dir/config.json" && -f "$dir/.vless-reality-owned" && -f "$dir/transport-state.json" ]] || return 1
    jq -e '.schema=="vless-reality-transport-1"' "$dir/transport-state.json" >/dev/null 2>&1
)

transport_digest() {
    local sum
    [[ -f "$1" && ! -L "$1" ]] || return 1
    sum="$(sha256sum -- "$1")" || return 1
    printf '%s' "${sum%% *}"
}

transport_record() {
    local dir="$1" active="$2" next_marker="$3" old_cfg new_cfg old_marker new_marker
    old_cfg="$(transport_digest "$dir/config.json")" && new_cfg="$(transport_digest "$dir/transport.json")" \
        && old_marker="$(transport_digest "$dir/.vless-reality-owned")" && new_marker="$(transport_digest "$next_marker")" || return 1
    jq -n --arg old_cfg "$old_cfg" --arg new_cfg "$new_cfg" --arg old_marker "$old_marker" --arg new_marker "$new_marker" --argjson active "$active" \
        '{schema:"vless-reality-transport-1",old_cfg:$old_cfg,new_cfg:$new_cfg,old_marker:$old_marker,new_marker:$new_marker,active:$active}' \
        > "$dir/transport-state.json"
}

transport_link_safe() {
    if [[ -e "$LINK_FILE" || -L "$LINK_FILE" ]]; then
        [[ -f "$LINK_FILE" && ! -L "$LINK_FILE" && "$(stat -c '%u:%a' "$LINK_FILE")" == "$EUID:600" ]] || return 1
    fi
}

transport_restore_file() (
    local source="$1" destination="$2" prefix="$3" tmp
    if cmp -s -- "$source" "$destination"; then return 0; fi
    tmp="$(mktemp "$prefix.XXXXXX")" || return 1
    trap 'rm -f -- "$tmp"' EXIT
    cp -aT -- "$source" "$tmp" && mv -fT -- "$tmp" "$destination"
)

transport_discard_snapshot() {
    local pending="$CONFIG_DIR/.transport-pending" retired
    retired="$(mktemp -d "$CONFIG_DIR/.change-backup.XXXXXX")" || return 1
    if ! mv -fT -- "$pending" "$retired"; then rmdir -- "$retired"; return 1; fi
    if ! sync -- "$CONFIG_DIR" || ! rm -rf -- "$retired"; then
        warn "传输记录清理未完成；可检查私有备份 $retired。" >&2
        return 1
    fi
}

transport_retire_snapshot() {
    # 配置、记录和链接可能分属不同文件系统。持久化最终结果后才移走恢复指针。
    sync -- "$CONFIG" "$MARKER" || return 1
    if [[ -f "$LINK_FILE" ]]; then sync -- "$LINK_FILE" || return 1; fi
    sync -- "$CONFIG_DIR" "${LINK_FILE%/*}" || return 1
    transport_discard_snapshot
}

transport_rollback() {
    local dir="$CONFIG_DIR/.transport-pending" record old_cfg new_cfg old_marker new_marker active actual_cfg actual_marker
    transport_snapshot_owned "$dir" && transport_link_safe || return 1
    record="$(jq -er 'def digest: type=="string" and length==64 and test("^[0-9a-f]{64}$");
        select(all([.old_cfg,.new_cfg,.old_marker,.new_marker][]; digest) and (.active==0 or .active==1)) |
        [.old_cfg,.new_cfg,.old_marker,.new_marker,.active] | @tsv' "$dir/transport-state.json")" || return 1
    read -r old_cfg new_cfg old_marker new_marker active <<< "$record"
    actual_cfg="$(transport_digest "$CONFIG")" && actual_marker="$(transport_digest "$MARKER")" || return 1
    if [[ "$actual_cfg" != "$old_cfg" && "$actual_cfg" != "$new_cfg" ]] || [[ "$actual_marker" != "$old_marker" && "$actual_marker" != "$new_marker" ]]; then
        warn '当前配置或安装记录在切换之外被修改，已保留备份供人工检查。' >&2
        return 1
    fi
    [[ "$(transport_digest "$dir/config.json")" == "$old_cfg" && "$(transport_digest "$dir/.vless-reality-owned")" == "$old_marker" ]] || return 1
    transport_restore_file "$dir/config.json" "$CONFIG" "$CONFIG_DIR/.config.json" || return 1
    transport_restore_file "$dir/.vless-reality-owned" "$MARKER" "$CONFIG_DIR/.marker" || return 1
    if [[ -f "$dir/link.txt" ]]; then
        transport_restore_file "$dir/link.txt" "$LINK_FILE" "$LINK_FILE" || return 1
    else
        rm -f -- "$LINK_FILE" || return 1
    fi
    if (( active )) || systemctl is-active --quiet xray; then
        if ! systemctl restart xray || ! wait_service 10; then return 1; fi
    fi
    transport_retire_snapshot
}

transport_recover() (
    need_root; self_operation_lock allow-transport-pending
    if ! transport_pending; then say '没有待恢复的传输切换。'; return 0; fi
    load_metadata
    transport_rollback || fail '未能完成恢复。请查看后台任务日志并保留尚未清理的备份。'
    ok '已恢复切换前的传输、配置和链接。'
)

transport_apply() (
    need_root; self_operation_lock; load_metadata
    [[ $# == 1 ]] || fail '用法：transport [status|tcp|xhttp]'
    local target="$1" current path previous_path="$XHTTP_PATH" backup='' candidate marker_next pending="$CONFIG_DIR/.transport-pending"
    local was_active=0 armed=0 rc probe_rc=0
    case "$target" in tcp|xhttp) ;; *) fail '传输只能选择 tcp 或 xhttp。' ;; esac
    jq -e "$TRANSPORT_JQ"' (.inbounds|length)==1 and (.inbounds[0] |
        .protocol=="vless" and managed_transport)' "$CONFIG" >/dev/null || fail '当前配置不是本脚本支持的 TCP + Vision 或 XHTTP 节点。'
    current="$(config_transport)" || fail '无法识别当前传输。'
    if [[ "$target" == "$current" ]]; then ok "当前传输已是 $current。"; return 0; fi
    transport_link_safe || fail '节点链接文件的归属或权限异常。'
    if systemctl is-active --quiet xray; then was_active=1; fi
    path="$XHTTP_PATH"
    if [[ "$current" == xhttp ]]; then
        path="$(config_xhttp_path)" || fail '无法保留当前 XHTTP Path。'
    elif [[ -z "$path" ]]; then
        path="$(openssl rand -hex 12)" || fail '无法生成 XHTTP 路径。'
        [[ "$path" =~ ^[0-9a-f]{24}$ ]] || fail '随机路径生成失败。'
        path="/$path"
    fi

    trap 'rc=$?; trap - EXIT; trap "" HUP INT TERM
        if (( armed )) && transport_pending; then
            if ! transport_rollback; then
                warn "自动恢复未完成，请运行 $(cmd_name) transport recover 检查。" >&2; exit 1
            fi
            warn "已恢复原传输、配置和链接。" >&2
        fi
        if [[ -n "$backup" ]] && ! rm -rf -- "$backup"; then
            warn "无法清理传输切换备份：$backup。请用 transport status 确认当前传输。" >&2; exit 1
        fi
        exit "$rc"' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    backup="$(mktemp -d "$CONFIG_DIR/.change-backup.XXXXXX")" || fail '无法备份节点配置。'
    if [[ -L "$CONFIG" ]] || ! backup_state "$backup"; then fail '无法备份节点配置。'; fi
    if [[ -f "$LINK_FILE" ]]; then cp -a -- "$LINK_FILE" "$backup/link.txt" || fail '无法备份节点链接。'; fi
    # Xray 根据后缀识别配置类型，暂存文件也必须使用 .json。
    candidate="$backup/transport.json"
    if ! jq --arg network "$target" --arg path "$path" '.inbounds[0] |= (
        .streamSettings.network=$network |
        if $network=="xhttp" then
            .streamSettings.xhttpSettings={path:$path,mode:"auto"} | del(.settings.clients[].flow)
        else
            del(.streamSettings.xhttpSettings) | .settings.clients[].flow="xtls-rprx-vision"
        end)' "$CONFIG" > "$candidate" \
        || ! config_ok "$candidate" || ! chown root:xray "$candidate" || ! chmod 640 "$candidate"; then
        fail '当前 Xray 未接受目标传输配置。请检查核心版本和配置权限。'
    fi
    marker_next="$backup/.vless-reality-owned"
    if [[ "$path" != "$previous_path" ]]; then
        XHTTP_PATH="$path"
        marker_next="$backup/marker.next"
        write_marker "$marker_next" || fail '无法暂存 XHTTP Path。'
    fi
    transport_record "$backup" "$was_active" "$marker_next" || fail '无法记录传输切换进度。'
    sync -- "$backup"/* "$backup/.vless-reality-owned" "$backup" || fail '无法持久化恢复备份。'
    # shellcheck disable=SC2034 # EXIT trap 检查是否已发布恢复记录。
    armed=1
    if ! mv -T -- "$backup" "$pending" || ! sync -- "$CONFIG_DIR"; then fail '无法发布恢复记录。'; fi
    mv -fT -- "$pending/transport.json" "$CONFIG" || fail '无法发布节点配置。'
    if [[ -f "$pending/marker.next" ]]; then
        mv -fT -- "$pending/marker.next" "$MARKER" || fail '无法保存 XHTTP Path。'
    fi
    if (( was_active )); then
        systemctl restart xray || fail '切换后 Xray 启动失败。'
        wait_service 10 || fail '切换后 Xray 未正常监听。'
        if [[ "$NODE_MODE" == self ]]; then
            self_http_check "$SNI" 127.0.0.1 "$PORT" || fail '切换后 HTTPS 回落未通过。'
        fi
        self_client_probe "$SNI" 127.0.0.1 "$PORT" switch || probe_rc=$?
        case "$probe_rc" in
            0) ;;
            2) fail '切换后临时验证客户端未能正常启动或退出异常。' ;;
            3) fail '代理与本机直连都无法访问测试站点，无法验证新传输。' ;;
            *) fail '测试站点本机直连可达，但经新传输的实际代理请求未通过。' ;;
        esac
    fi
    show_node >/dev/null || fail '无法更新导入链接。'
    if [[ "$NODE_MODE" == self ]] && self_exists; then
        rm -f -- "$SELF_DIR/network-check.json" || fail '无法清除旧传输的网络检查记录。'
    fi
    transport_retire_snapshot || fail '无法完成传输切换记录的收尾。'
    ok "已切换为 $target，导入链接已更新。"
    if (( ! was_active )); then warn 'Xray 原为停止状态。配置已验证，实际连接需在启动后检查。'; fi
)

NODE_JOB_NOTE='此操作将重启 Xray；如果 SSH 经过此节点，连接可能中断。后台任务会继续执行，并在失败时自动回滚。建议使用 VPS 直连 SSH 或服务商控制台。'
# 会重启 Xray 的修改都放进临时 systemd 任务：前台只负责输入、预检和结束后的结果核对；
# 即使 SSH 经过本节点并在重启时断开，后台任务仍会完成验证、提交或回滚。
run_node_job() {
    local unit="$1" note="$2" script_path
    shift 2
    # 传输切换的恢复任务本身用于处理未完成记录，其余任务须等待恢复完成。
    if transport_pending && [[ "$1" != __transport-recover ]]; then transport_pending_message; return 3; fi
    need_command systemd-run
    script_path="$(readlink -f -- "$SCRIPT_PATH")" || fail '无法找到当前管理脚本。'
    [[ -f "$script_path" && -r "$script_path" ]] || fail '当前管理脚本不是可读取的普通文件。'
    warn "$note"
    say "后台任务：$unit；连接中断后重连，可运行 $(cmd_name) status 查看结果，或用 journalctl -u $unit 查看任务日志。"
    systemd-run --quiet --wait --collect --unit="$unit" --property="SyslogIdentifier=$unit" \
        /bin/bash "$script_path" "$@"
}
# 用法：run_node_job ... || node_job_failed 任务名 "$?"。状态 3 表示传输切换未完成，提示已显示，原样返回。
node_job_failed() {
    [[ "${2:-1}" != 3 ]] || exit 3
    fail "后台任务未成功完成；任务会在失败时自动恢复原状态，请查看 journalctl -u $1 确认结果。"
}

transport_command() {
    need_root
    [[ $# -le 1 ]] || fail '用法：transport [status|tcp|xhttp|recover]'
    local action="${1:-}" current='' unit=vless-reality-transport job=()
    if transport_pending && [[ "$action" != recover ]]; then
        transport_pending_message
        if [[ -n "$action" || ! -t 0 ]]; then return 3; fi
        read -r -p '请输入 recover 恢复切换前的配置，或回车返回：' action || return 0
        [[ "$action" == recover ]] || return 0
    fi
    if [[ -z "$action" || "$action" == status ]]; then
        load_metadata
        current="$(config_transport)" || fail '无法识别当前传输。'
        if [[ "$current" == tcp ]]; then say '当前传输：TCP + REALITY + Vision';
        else
            local path
            path="$(config_xhttp_path)" || fail '无法读取 XHTTP 路径。'
            say "当前传输：XHTTP + REALITY（auto，路径 $path）"
        fi
        if [[ "$action" == status || ! -t 0 ]]; then return 0; fi
        read -r -p '切换传输 [tcp / xhttp / 回车取消]：' action || return 0
        [[ -n "$action" ]] || return 0
    fi
    case "$action" in
        tcp|xhttp) job=(__transport-apply "$action") ;;
        recover) job=(__transport-recover) ;;
        *) fail '用法：transport [status|tcp|xhttp|recover]' ;;
    esac
    run_node_job "$unit" '切换或恢复运行中的节点可能重启 Xray；如果 SSH 经过此节点，连接可能中断。后台任务会继续执行，并在失败时自动恢复。' \
        "${job[@]}" || fail "传输任务失败，请查看 journalctl -u $unit。"
    if [[ "$action" == recover ]]; then ok '传输恢复任务已结束。'; return 0; fi
    [[ "$(config_transport)" == "$action" ]] || fail '任务已结束，但当前传输已改变，请查看状态。'
    show_node
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
    local action="${1:-}" unit=vless-reality-tfo
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
    if run_node_job "$unit" "$NODE_JOB_NOTE" __tfo-apply "$action"; then
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
    server_enc="$(config_decryption)" \
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
    if ! edit_config_private \
        '($credentials | split("\n")) as $secret | (.inbounds[] | select(.protocol == "vless") | .settings.decryption) = $secret[0]' "$VLESS_DECRYPTION" \
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
    local action="${1:-}" mode="${2:-}" current_mode='' answer server_enc unit='vless-reality-enc'
    server_enc="$(config_decryption)" \
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
    run_node_job "$unit" "切换 VLESS Encryption 后旧客户端链接会失效。$NODE_JOB_NOTE" __vlessenc-apply "$action" "$mode" \
        || fail "VLESS Encryption 后台任务失败；请查看 journalctl -u $unit。"
    load_metadata
    server_enc="$(config_decryption)"
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
    local raw="${1:-}" old_port="$PORT"
    if [[ -z "$raw" ]]; then
        [[ -t 0 ]] || fail '非交互运行时请指定新端口。'
        read -r -p "当前端口 $PORT，请输入新端口：" raw || fail '已取消输入。'
    fi
    valid_port "$raw" || fail '端口必须是 1–65535 的数字。'
    PORT="$((10#$raw))"
    (( PORT != old_port )) || fail '新端口与当前端口相同。'
    port_free "$PORT" || fail "本机 TCP $PORT 已被占用。"
    node_change "$old_port" "端口已改为 TCP $PORT；请放行新端口，确认可用后再关闭旧端口 $old_port。" edit_port_config
}
edit_port_config() {
    edit_config --argjson port "$PORT" '(.inbounds[] | select(.protocol == "vless") | .port) = $port' && write_marker
}

change_sni() {
    need_root
    [[ $# -le 1 ]] || fail "用法：$(cmd_name) sni [新域名]"
    load_metadata
    if [[ "$NODE_MODE" == self ]]; then change_self_domain "$@"; return; fi
    self_operation_lock
    load_metadata
    local new="${1:-}" old_port="$PORT" old_sni="$SNI" auto_sni=0
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
    SNI="$new"
    node_change "$old_port" "REALITY 伪装域名已改为 $SNI。" edit_sni_config
}
edit_sni_config() {
    edit_config --arg sni "$SNI" \
        '(.inbounds[] | select(.protocol == "vless") | .streamSettings.realitySettings.target) = ($sni + ":443") |
         (.inbounds[] | select(.protocol == "vless") | .streamSettings.realitySettings.serverNames) = [$sni]' \
        && write_marker
}

change_uuid() {
    need_root
    self_operation_lock
    load_metadata
    local new old
    old="$(config_uuid)" || fail '无法从配置读取旧 UUID。'
    new="$($XRAY_BIN uuid)" || fail '无法生成新 UUID。'
    [[ "$new" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ && "$new" != "$old" ]] || fail '生成的 UUID 无效。'
    node_change "$PORT" 'UUID 已重新生成，旧链接立即失效。' edit_config_private \
        '($credentials | split("\n")) as $secret | (.inbounds[] | select(.protocol == "vless") | .settings.clients[] | select(.id == $secret[1]) | .id) = $secret[0]' "$new" "$old"
}

rotate_keys() {
    need_root
    self_operation_lock
    load_metadata
    local key_lines
    mapfile -t key_lines < <(generate_reality_keys)
    (( ${#key_lines[@]} == 2 )) || fail 'REALITY 密钥生成失败。'
    PUBLIC_KEY="${key_lines[1]}"
    SHORT_ID="$(openssl rand -hex 8)"
    node_change "$PORT" 'REALITY 密钥和 Short ID 已轮换，旧链接立即失效。' edit_keys_config "${key_lines[0]}"
}
edit_keys_config() {
    edit_config_private \
        '($credentials | split("\n")) as $secret | (.inbounds[] | select(.protocol == "vless") | .streamSettings.realitySettings.privateKey) = $secret[0] |
         (.inbounds[] | select(.protocol == "vless") | .streamSettings.realitySettings.shortIds) = [$secret[1]]' "$1" "$SHORT_ID" \
        && write_marker
}

# 以下前台命令：在当前终端完成输入与预检，再由 run_node_job 在后台提交（含重启和回滚），
# 结束后按实际配置核对结果。__*-apply 内部命令直接调用上面的事务函数。
port_node() {
    need_root
    [[ $# -le 1 ]] || fail "用法：$(cmd_name) port [新端口]"
    load_metadata
    [[ "$NODE_MODE" != self ]] || fail '自有域名模式固定使用 TCP 443；端口修改只适用于普通模式。'
    local raw="${1:-}" port old_port="$PORT" unit=vless-reality-port
    if [[ -z "$raw" ]]; then
        [[ -t 0 ]] || fail '非交互运行时请指定新端口。'
        read -r -p "当前端口 $PORT，请输入新端口：" raw || fail '已取消输入。'
    fi
    valid_port "$raw" || fail '端口必须是 1–65535 的数字。'
    port="$((10#$raw))"
    (( port != old_port )) || fail '新端口与当前端口相同。'
    port_free "$port" || fail "本机 TCP $port 已被占用。"
    run_node_job "$unit" "$NODE_JOB_NOTE" __port-apply "$port" || node_job_failed "$unit" "$?"
    load_metadata
    [[ "$PORT" == "$port" ]] || fail "后台任务已结束，但端口不是 TCP $port；请查看 journalctl -u $unit。"
    show_node
    ok "端口已改为 TCP $port；请放行新端口，确认可用后再关闭旧端口 $old_port。"
}
sni_node() {
    need_root
    [[ $# -le 1 ]] || fail "用法：$(cmd_name) sni [新域名|auto]"
    load_metadata
    if [[ "$NODE_MODE" == self ]]; then change_self_domain "$@"; return; fi
    local new="${1:-}" old_sni="$SNI" unit=vless-reality-sni
    if [[ -z "$new" ]]; then
        [[ -t 0 ]] || fail '非交互运行时请指定新伪装域名。'
        read -r -p "当前 SNI $SNI，请输入新域名（回车自动优选）：" new || fail '已取消输入。'
        new="${new:-auto}"
    fi
    new="${new,,}"
    # 自动优选在前台测速并显示结果，后台任务只提交已选定的域名。
    if [[ "$new" == auto ]]; then
        select_fastest_sni || fail '候选域名均不可用，请手动指定伪装域名。'
        new="$SNI"
        SNI="$old_sni"
        if [[ "$new" == "$SNI" ]]; then ok "当前域名 $SNI 已是本次测试的最优选项，无需修改。"; return 0; fi
    else
        valid_host "$new" || fail '伪装域名格式不正确。'
        [[ "$new" != "$SNI" ]] || fail '新域名与当前域名相同。'
        target_tls_ok "$new" || fail "$new:443 未通过 TLS 1.3 与证书校验。"
    fi
    run_node_job "$unit" "$NODE_JOB_NOTE" __sni-apply "$new" || node_job_failed "$unit" "$?"
    load_metadata
    [[ "$SNI" == "$new" ]] || fail "后台任务已结束，但伪装域名不是 $new；请查看 journalctl -u $unit。"
    show_node
    ok "REALITY 伪装域名已改为 $SNI。"
}
uuid_node() {
    need_root
    load_metadata
    local old unit=vless-reality-uuid
    old="$(config_uuid)" || fail '无法从配置读取当前 UUID。'
    run_node_job "$unit" "$NODE_JOB_NOTE" __uuid-apply || node_job_failed "$unit" "$?"
    [[ "$(config_uuid)" != "$old" ]] || fail "后台任务已结束，但 UUID 未改变；请查看 journalctl -u $unit。"
    show_node
    ok 'UUID 已重新生成，旧链接立即失效。'
}
rotate_keys_node() {
    need_root
    load_metadata
    local old="$PUBLIC_KEY" unit=vless-reality-keys
    run_node_job "$unit" "$NODE_JOB_NOTE" __keys-apply || node_job_failed "$unit" "$?"
    load_metadata
    [[ "$PUBLIC_KEY" != "$old" ]] || fail "后台任务已结束，但 REALITY 密钥未改变；请查看 journalctl -u $unit。"
    show_node
    ok 'REALITY 密钥和 Short ID 已轮换，旧链接立即失效。'
}
update_node() {
    need_root
    load_metadata
    local before after unit=vless-reality-update
    before="$(installed_version)"
    run_node_job "$unit" '升级会替换 Xray 程序并重启服务；如果 SSH 经过此节点，连接可能中断。后台任务会继续执行，失败时自动恢复旧版本。' \
        __update-apply || node_job_failed "$unit" "$?"
    after="$(installed_version)"
    if [[ "$after" != "$before" ]]; then
        ok "Xray 已从 ${before:-未知版本} 升级到 ${after:-未知版本}。"
    else
        ok "Xray 版本未变化：${after:-未知}（已是官方最新稳定版，或高于官方稳定版而未降级）。"
    fi
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

# 地址切换只提交安装记录和客户端链接，不修改 Xray/Nginx 或重启服务。
commit_address_change() (
    local mode="$1" domain="$2" ip="$3" backup committed=0 had_link=0 rc
    [[ -f "$MARKER" && ! -L "$MARKER" && ! -L "$LINK_FILE" ]] || fail '安装记录或链接文件归属异常，未修改。'
    [[ ! -e "$LINK_FILE" || -f "$LINK_FILE" ]] || fail '节点链接不是普通文件，未修改。'
    backup="$(mktemp -d "$CONFIG_DIR/.change-backup.XXXXXX")" || fail '无法备份地址设置。'
    if ! cp -a -- "$MARKER" "$backup/.vless-reality-owned"; then rm -rf -- "$backup"; fail '备份安装记录失败。'; fi
    if [[ -f "$LINK_FILE" ]]; then
        if ! cp -a -- "$LINK_FILE" "$backup/link.txt"; then rm -rf -- "$backup"; fail '备份节点链接失败。'; fi
        # shellcheck disable=SC2034 # EXIT trap 决定是否恢复旧链接。
        had_link=1
    fi
    trap 'rc=$?; trap - EXIT
        if (( ! committed )); then
            if ! mv -f -- "$backup/.vless-reality-owned" "$MARKER"; then warn "地址设置回滚失败，保留备份：$backup" >&2; exit 1; fi
            if (( had_link )); then
                if ! mv -f -- "$backup/link.txt" "$LINK_FILE"; then warn "链接回滚失败，保留备份：$backup" >&2; exit 1; fi
            elif ! rm -f -- "$LINK_FILE"; then warn "链接清理失败，保留备份：$backup" >&2; exit 1; fi
        fi
        rm -rf -- "$backup"; exit "$rc"' EXIT
    ADDR_MODE="$mode"; ADDR_DOMAIN="$domain"; SERVER_IP="$ip"
    if ! write_marker || ! show_node > "$backup/link-output.txt"; then fail '地址设置或链接保存失败，正在恢复原设置。'; fi
    # shellcheck disable=SC2034 # EXIT trap 保持/清理事务。
    committed=1
    ok '客户端连接地址已更新，服务无需重启；请重新导入下面的新链接。'
    cat "$backup/link-output.txt"
)
address_node() (
    need_root
    [[ $# -le 2 ]] || fail "用法：$(cmd_name) addr [ip|domain [连接域名]]"
    load_metadata
    local action="${1:-}" domain="${2:-}" answer ip
    if [[ -z "$action" ]]; then
        client_address_status
        say "REALITY SNI：$SNI（切换连接地址不会修改它）"
        [[ -t 0 ]] || return 0
        say '  1. 连接地址改用公网 IP'
        say '  2. 连接地址改用域名'
        say '  3. 刷新公网 IP（保持当前地址模式）'
        say ' 00. 返回'
        while true; do
            read -r -p '请选择 [1-3，回车返回]：' answer || return 0
            case "$answer" in
                1) action=ip; break ;; 2) action=domain; break ;;
                3) refresh_ip; return ;; ''|00|0|q|Q) return 0 ;;
                *) warn '请选择 1、2、3 或回车返回。' ;;
            esac
        done
    fi
    action="${action,,}"
    case "$action" in ip|domain) ;; *) fail "用法：$(cmd_name) addr [ip|domain [连接域名]]" ;; esac
    [[ "$action" != ip || -z "$domain" ]] || fail 'IP 模式会自动获取本机公网 IPv4，无需另填地址。'
    if [[ "$action" == domain && "$NODE_MODE" == external && -z "$domain" ]]; then
        domain="$ADDR_DOMAIN"
        if [[ -t 0 ]]; then
            read -r -p "自己的连接域名（A 直连 VPS；回车沿用 ${domain:-未设置}；不要填第三方 SNI）：" answer || fail '已取消。'
            domain="${answer:-$domain}"
        fi
        [[ -n "$domain" ]] || fail '普通模式请提供自己的连接域名，例如 addr domain node.example.com。'
    fi
    self_operation_lock
    load_metadata
    ip="$(public_ipv4)" || fail '无法查询本机公网 IPv4，未修改。'
    valid_ipv4 "$ip" || fail '公网 IPv4 格式无效，未修改。'
    if [[ "$action" == domain ]]; then
        domain="${domain,,}"
        if [[ "$NODE_MODE" == self ]]; then
            [[ -z "$domain" || "$domain" == "$SNI" ]] || fail '自有域名模式沿用当前 SNI；更换站点域名请使用 sni 命令。'
            domain="$SNI"
        fi
        valid_host "$domain" || fail '连接域名格式不正确，未修改。'
        ensure_dns_tool
        self_dns_check "$domain" || fail '连接域名未直连当前 VPS，未修改地址设置。'
        [[ "$NODE_MODE" != self ]] || domain=''
    else
        domain="$ADDR_DOMAIN"
        if [[ "$NODE_MODE" == self ]] && ! self_dns_check "$SNI" >/dev/null 2>&1; then
            warn '警告：自有域名 DNS 检查未通过；切换 IP 不会修正 DNS，网站与证书监测仍需维护正确解析。'
        fi
        warn '使用 IP 后，VPS 公网 IP 变化时需要刷新 IP 并重新导入链接；REALITY SNI 保持不变。'
    fi
    commit_address_change "$action" "$domain" "$ip"
)
refresh_ip() (
    need_root; self_operation_lock; load_metadata
    local ip
    ip="$(public_ipv4)" || fail '无法查询当前公网 IPv4。'
    valid_ipv4 "$ip" || fail '公网 IPv4 格式无效，未修改。'
    if [[ "$(client_address_mode)" == domain ]]; then
        ensure_dns_tool
        self_dns_check "$(client_address)" || fail '连接域名 DNS 检查未通过；请手动更新解析，原地址设置保持。'
    elif [[ "$NODE_MODE" == self ]] && ! self_dns_check "$SNI" >/dev/null 2>&1; then
        warn '警告：自有域名解析未通过检查，刷新 IP 不会自动修改 DNS。'
    fi
    if [[ "$ip" == "$SERVER_IP" ]]; then ok "公网 IPv4 未变化：$ip"; show_node; return 0; fi
    commit_address_change "$ADDR_MODE" "$ADDR_DOMAIN" "$ip"
)

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
    if [[ "$NODE_MODE" == self ]]; then
        self_config_policy "$CONFIG" "$SNI" || fail '自有域名配置违反安全约束，未执行升级。'
        if jq -e '.. | objects | select(has("limitFallbackUpload") or has("limitFallbackDownload"))' "$CONFIG" >/dev/null; then
            fallback_capability "$CONFIG" "$candidate" || fail '新版核心无法确认支持当前回落限速，未升级。'
        fi
    fi
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
    self_operation_lock allow-transport-pending
    if transport_pending; then
        transport_snapshot_owned "$CONFIG_DIR/.transport-pending" || fail '传输恢复目录归属异常，未继续卸载。'
    fi
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
    if systemctl is-failed --quiet xray; then systemctl reset-failed xray || fail '清理 Xray 失败状态未完成；保留文件以便重试。'; fi
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
    local locked=0 directory
    if (( SELF_OPERATION_LOCKED == 0 )); then
        # 对目录本身加锁，不留下普通模式的额外锁文件；与其他节点修改串行，避免覆盖最新密钥/地址记录。
        if [[ -d "$CONFIG_DIR" && -f "$MARKER" && -f "$CONFIG" ]]; then
            [[ ! -L "$CONFIG_DIR" && ! -L "$MARKER" ]] || fail '节点目录或安装记录异常，未修改。'
            exec 9< "$CONFIG_DIR" || fail '无法打开节点操作锁。'
            flock -x 9 || fail '无法取得节点操作锁。'
            directory="$(stat -Lc '%d:%i' /proc/self/fd/9)" || fail '无法核对节点目录。'
            [[ "$directory" == "$(stat -c '%d:%i' "$CONFIG_DIR" 2>/dev/null)" ]] || fail '等待期间节点目录已变化，请重新运行命令。'
            locked=1
        fi
        if self_exists; then
            exec 7> "$SELF_DIR/operation.lock" || fail '无法锁定自有域名操作。'
            flock -x 7 || fail '无法取得自有域名操作锁。'
            locked=1
        fi
        if transport_pending && [[ "${1:-}" != allow-transport-pending ]]; then
            transport_pending_message
            exit 3
        fi
        SELF_OPERATION_LOCKED="$locked"
    fi
    return 0
}
self_track() {
    local path="$1" source="${2:-$1}" tmp digest
    [[ -f "$source" && ! -L "$source" ]] || return 1
    tmp="$(mktemp "$SELF_DIR/.receipt.XXXXXX")" || return 1
    if [[ -f "$SELF_DIR/files.sha256" ]]; then
        awk -v path="$path" 'substr($0,67) != path' "$SELF_DIR/files.sha256" > "$tmp" || { rm -f "$tmp"; return 1; }
    fi
    digest="$(sha256sum -- "$source" | awk '{print $1}')" || { rm -f "$tmp"; return 1; }
    if ! printf '%s  %s\n' "$digest" "$path" >> "$tmp" || ! mv -f -- "$tmp" "$SELF_DIR/files.sha256"; then
        rm -f -- "$tmp"; return 1
    fi
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
ensure_dns_tool() {
    if ! command -v dig >/dev/null 2>&1; then
        need_command apt-get
        say '安装域名校验工具 dnsutils…'
        if ! apt_update_once || ! apt-get install -y dnsutils; then fail 'DNS 校验工具安装失败，未修改地址设置。'; fi
    fi
    need_command dig
}
self_dns_query() { dig "@$1" "$2" "$3" +time=4 +tries=1 +noall +answer +comments; }
self_dns_checked_query() {
    local resolver="$1" domain="$2" type="$3" output status=UNKNOWN reason
    if ! output="$(self_dns_query "$resolver" "$domain" "$type" 2>&1)"; then
        warn "失败：$resolver 查询 $domain 的 $type 记录未完成；请检查 VPS 的 DNS 网络连通性或稍后重试。" >&2
        return 1
    fi
    if [[ "$output" =~ status:[[:space:]]*([A-Z]+) ]]; then status="${BASH_REMATCH[1]}"; fi
    case "$status" in
        NOERROR) printf '%s\n' "$output"; return 0 ;;
        NXDOMAIN) reason='域名或子域名不存在，请检查拼写及 DNS 记录是否已创建/生效' ;;
        SERVFAIL) reason='解析失败，请检查权威 NS、DNSSEC 或 DNS 服务状态' ;;
        REFUSED) reason='解析器拒绝查询，请检查 DNS 服务与网络访问限制' ;;
        *) reason='未获得正常 DNS 响应，请检查 DNS 配置或稍后重试' ;;
    esac
    warn "失败：$resolver 查询 $domain 的 $type 记录返回 $status；$reason。" >&2
    return 1
}
self_dns_resolver_check() {
    local domain="$1" ip="$2" resolver="$3" output records aaaa cname
    output="$(self_dns_checked_query "$resolver" "$domain" A)" || return 1
    cname="$(awk '$4 == "CNAME" {print $5}' <<< "$output")" || return 1
    [[ -z "$cname" ]] || { warn '失败：连接域名不接受 CNAME，请使用直接指向 VPS 的 A 记录。' >&2; return 1; }
    records="$(awk '$4 == "A" {print $5}' <<< "$output" | sort -u)" || return 1
    [[ "$records" == "$ip" ]] || { warn "失败：$resolver 查询 $domain 的 A 记录为 ${records//$'\n'/, }（空白表示无记录），期望唯一 IPv4 $ip；请核对域名、关闭 CDN/Cloudflare 橙云并等待 DNS 生效。" >&2; return 1; }
    output="$(self_dns_checked_query "$resolver" "$domain" AAAA)" || return 1
    aaaa="$(awk '$4 == "AAAA" {print $5}' <<< "$output")" || return 1
    [[ -z "$aaaa" ]] || { warn '失败：此模式只配置 IPv4 入口，请先移除 AAAA 记录，避免 IPv6 连接绕过本机配置。' >&2; return 1; }
}
self_dns_check() (
    local domain="$1" ip first_fd second_fd pid output rc result=0 diagnostic=''
    # shellcheck disable=SC2034 # EXIT trap 中作为动态文件描述符使用。
    local fd
    local fds=() pids=() index resolvers=(1.1.1.1 8.8.8.8)
    # 管道只携带本次查询结果，无磁盘缓存或新增残留；结束前关闭管道并回收全部检查进程。
    trap 'rc=$?; trap - EXIT
        for fd in "${fds[@]}"; do exec {fd}<&-; done
        for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
        exit "$rc"' EXIT
    trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
    valid_host "$domain" || { warn '失败：域名格式无效。' >&2; return 1; }
    ip="$(public_ipv4)" || { warn '失败：无法确认本机公网 IPv4。' >&2; return 1; }
    exec {first_fd}< <(exec 7>&- 8>&- 9>&-; if self_dns_resolver_check "$domain" "$ip" 1.1.1.1 2>&1; then printf 'vless-dns-verified\n'; else exit 1; fi) || return 1
    pids+=("$!"); fds+=("$first_fd")
    exec {second_fd}< <(exec 7>&- 8>&- 9>&-; if self_dns_resolver_check "$domain" "$ip" 8.8.8.8 2>&1; then printf 'vless-dns-verified\n'; else exit 1; fi) || return 1
    pids+=("$!"); fds+=("$second_fd")
    for index in 0 1; do
        output=''
        IFS= read -r -d '' output <&"${fds[index]}" || true
        if wait "${pids[index]}" && [[ "$output" == $'vless-dns-verified\n' ]]; then :;
        elif (( result == 0 )); then
            result=1
            if [[ -n "$output" ]]; then diagnostic="$output";
            else printf -v diagnostic '失败：%s 的 DNS 检查未完整执行，请重试。\n' "${resolvers[index]}"; fi
        fi
    done
    if (( result )); then printf '%s' "$diagnostic" >&2; fi
    return "$result"
)
self_dns_precheck() {
    valid_host "$1" || { warn '失败：只填完整域名，不要带 https://、端口、路径或空格。' >&2; return 1; }
    ensure_dns_tool || return 1
    self_dns_check "$1"
}
# 仅交互安装/更换自有域名使用；CLI 显式参数保持无人值守语义，仍须通过部署前预检。
self_prompt_domain() {
    local domain confirmation tools_ready=0
    SELF_INPUT_DOMAIN=''
    while true; do
        IFS= read -r -p '自有域名（A 直连 VPS，无 AAAA / CNAME / CDN；输入 0 返回）：' domain || return 1
        case "$domain" in 0|00|q|Q) return 1 ;; esac
        domain="${domain,,}"
        if ! valid_host "$domain"; then warn '域名格式不正确：只填完整域名，不要带 https://、端口、路径或空格。'; continue; fi
        if (( ! tools_ready )); then
            ensure_dependencies || fail '域名预检所需的基础工具不可用，未开始部署。'
            ensure_dns_tool || fail '域名预检所需的 DNS 工具不可用，未开始部署。'
            tools_ready=1
        fi
        say "正在检查自有域名：$domain"
        if ! self_dns_check "$domain"; then warn '域名预检未通过，请修正后重新输入；尚未开始部署。'; continue; fi
        ok 'DNS 预检通过：两个解析器均确认 A 直连当前 VPS，无 AAAA / CNAME。'
        say "准备使用的完整域名：$domain"
        IFS= read -r -p '请再次输入完整域名确认（输入 0 返回）：' confirmation || return 1
        case "$confirmation" in 0|00|q|Q) return 1 ;; esac
        if [[ "${confirmation,,}" != "$domain" ]]; then warn '两次域名不一致，请重新输入并核对。'; continue; fi
        SELF_INPUT_DOMAIN="$domain"
        return 0
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
    # 兼容现有 Certbot 来自 snap/独立虚拟环境的系统，确保系统 Python 可安全校验密钥配对。
    python3 -c 'from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey' >/dev/null 2>&1 || packages+=(python3-cryptography)
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
            apt_update_once && apt-get install -y "${packages[@]}"
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
    local domain="$1" tls="${2:-yes}" http_domain="${3:-$1}" escaped="${1//./\\.}" version h2listen='http2' h2directive='' tmp
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
# xver=0: all fallback peers are loopback. Never trust a client X-Forwarded-For.
map \$ssl_server_name \$vless_self_sni_ok { default 0; ~*^${escaped}\$ 1; }
map \$http_host \$vless_self_host_ok { default 0; ~*^${escaped}(:443|:8443)?\$ 1; }
server {
    listen 127.0.0.1:8443 ssl $h2listen default_server;
    $h2directive
    server_name _;
    ssl_protocols TLSv1.3;
    ssl_ecdh_curve X25519:prime256v1;
    ssl_reject_handshake on;
    return 421;
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
    send_timeout 15s;
    keepalive_requests 1000;
    access_log off;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy no-referrer always;
    add_header Content-Security-Policy "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'" always;
    if (\$vless_self_sni_ok = 0) { return 421; }
    if (\$vless_self_host_ok = 0) { return 421; }
    if (\$host != "$domain") { return 421; }
    location / { limit_except GET HEAD { deny all; } try_files \$uri \$uri/ =404; }
    location ~ /\. { deny all; }
}
EOF
        fi
    } > "$tmp"
    self_publish "$tmp" "$SELF_SITE" 644
}
self_nginx_apply() { nginx -t && { if systemctl is-active --quiet nginx; then systemctl reload nginx; else systemctl start nginx; fi; }; }
self_site_render() {
    # 仅安装或用户明确更换时生成；无网络请求、额外素材或模板元数据。
    python3 - "$@" <<'PY_SITE'
import html
import pathlib
import re
import secrets
import sys
from random import SystemRandom

themes = [
    dict(kind="profile", titles=["山间手记", "平日档案", "片刻札记", "慢声记录"], label="PERSONAL NOTES",
         headline=["把平常的日子，认真收藏。", "在日常里，留一点空白。", "慢一点，也有新的发现。"],
         intro="留意生活里的细节，整理想法，也记录那些值得停下来看的瞬间。这里是一处安静的个人空间。",
         about="不急着给每件事下结论，让观察、阅读和实践慢慢留下自己的形状。",
         entries=[("清晨的光", "窗边的光线每天都有细微的变化。给一杯热茶的时间，也给今天一个从容的开始。"),
                  ("手边的植物", "新叶舒展的速度很慢，却总能提醒人保持耐心。照顾小事，也是照顾生活。"),
                  ("散步的路线", "偶尔走一条不同的路，看看街角的树、旧店招，以及傍晚还没散去的颜色。"),
                  ("一页随想", "把还没有成形的念头写下来，过些时候再读，也许会找到新的联系。")]),
    dict(kind="journal", titles=["纸上实验室", "简明笔记", "格物小记", "思考草稿"], label="IDEAS & PRACTICE",
         headline=["让问题，带来下一次探索。", "从一个小问题开始。", "想清楚，再做一点。"],
         intro="整理学习与实践中的片段：一个清晰的问题、一份可重复的方法，以及一次认真复盘。",
         about="笔记的价值不在于一次写得完整，而在于能被重新理解、验证和改进。",
         entries=[("记录的方法", "先写观察，再写推测。把前提、过程和结论分开，后来的人也能沿着同一条线索继续思考。"),
                  ("从简开始", "让最小的想法先运行起来，再决定哪些细节值得增加。清楚的边界往往比复杂的结构更有帮助。"),
                  ("整理工作台", "给资料一个明确的位置，为重要的内容留下索引。减少寻找，也就多出了一点专注的时间。"),
                  ("回看与修正", "记录做过的选择和当时的理由。复盘不必急着评判，先理解变化发生在哪里。")]),
    dict(kind="studio", titles=["原点工作室", "微光造物", "小型实践", "折线计划"], label="SMALL PROJECTS",
         headline=["让想法，慢慢成为作品。", "从草图走向日常。", "为简单的事，做细致的设计。"],
         intro="关注小而具体的创作：从需求到草图，从尝试到打磨，把注意力放在有用、清晰与长久。",
         about="好的作品来自持续的小步调整。保留过程，也为下一次尝试留下空间。",
         entries=[("纸面与结构", "从线条和比例开始，探索信息怎样排列才更容易被理解。让结构先回答问题，再加入装饰。"),
                  ("一件日常物", "观察一件常用物品的边缘、手感与使用方式，寻找不引人注意却让体验更顺畅的细节。"),
                  ("小工具的想法", "把重复的步骤整理成清楚的流程，为一个具体的小问题寻找轻巧的解法。"),
                  ("迭代中的片段", "收集草稿和试验留下的痕迹。没有采用的方向，也可能成为另一件作品的起点。")]),
    dict(kind="gallery", titles=["形色之间", "视觉散记", "构成练习", "一隅画室"], label="VISUAL STUDIES",
         headline=["在形与色之间，看见秩序。", "用简单的形状，记录感受。", "给视线，一点新的方向。"],
         intro="关于线条、色块、材质与留白的视觉练习。减少不必要的元素，让每一次观看都更轻松。",
         about="观察是创作的起点。把熟悉的事物重新排列，也会产生新的节奏。",
         entries=[("线的节奏", "平行、交错与轻微的偏移，可以为同一个平面带来不同的方向感。"),
                  ("留白的比例", "画面不必被填满。安静的区域也参与表达，给重要的信息留出呼吸的空间。"),
                  ("柔和的边界", "尝试让色彩靠近自然光下的变化，在对比与协调之间寻找平衡。"),
                  ("重复与变化", "在稳定的结构中加入一点差异，让相近的形状保持联系，也保留各自的个性。")]),
    dict(kind="library", titles=["页间时光", "案头阅读", "书页旁边", "阅读余白"], label="READING JOURNAL",
         headline=["读一段文字，也读一会儿自己。", "在书页之间，遇见新的问题。", "把阅读，留在日常里。"],
         intro="记录阅读带来的思考、联想与问题。不追求数量，愿意把一段值得回味的文字读得更慢。",
         about="每次重读都会带来不同的理解。让笔记保持开放，也让自己的观点有机会改变。",
         entries=[("阅读的节奏", "有时连续读上几页，有时只停留在一个段落。找到适合当下的速度，比赶往结尾更重要。"),
                  ("页边的问题", "把不确定的地方留下来，不急着寻找唯一答案。一个好问题常常会带来另一段阅读。"),
                  ("文字之外", "试着把书中的观察放回日常，看看它怎样与眼前的事情发生联系。"),
                  ("重新翻开", "隔一段时间回到旧笔记，看看哪些想法仍然清晰，哪些已经有了新的解释。")]),
    dict(kind="trail", titles=["沿路拾光", "远近之间", "漫步地图", "行走随笔"], label="WALK & WONDER",
         headline=["不必走远，也能遇见风景。", "让脚步，跟着好奇心。", "沿着小路，看看这个世界。"],
         intro="留意沿途的光线、建筑与季节。用短短的文字，收集那些容易从记忆里溜走的片刻。",
         about="保持开放的目光。熟悉的地方也会变化，一次普通的散步同样值得记录。",
         entries=[("雨后的街道", "路面映出另一层天空，树叶的颜色也更清晰。换一种天气，熟悉的街道就有了新的表情。"),
                  ("城市的边缘", "从热闹走向安静，观察建筑与空地之间的过渡，也感受一座城市不同的呼吸。"),
                  ("傍晚的方向", "跟着逐渐变长的影子慢慢走，留意一天结束之前，街边的声音和颜色。"),
                  ("季节的片段", "风的温度、树梢的新芽和渐晚的日落，常常比日历更早提醒季节正在变化。")]),
]
if len(sys.argv) > 1:
    previous = re.search(r'<body class="([a-z]+)"', pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    if previous:
        themes = [theme for theme in themes if theme["kind"] != previous[1]]
theme = themes[secrets.randbelow(len(themes))]
paper, panel, ink, muted, accent, line = secrets.choice([
    ("#f4f1e9", "#fffcf6", "#253a31", "#5d7063", "#397b61", "#cdd5c9"),
    ("#f2f4f7", "#ffffff", "#24394b", "#5d7183", "#336f9e", "#ced8e1"),
    ("#faf0e8", "#fffaf5", "#49352d", "#80675a", "#a14e35", "#e0cfc2"),
    ("#f4f0f7", "#fffaff", "#393047", "#74657f", "#815399", "#d9cde1"),
    ("#f6f3e4", "#fffdf2", "#424125", "#77734e", "#7c7835", "#ded9b9"),
    ("#192323", "#22302f", "#f0f0e5", "#b3c3b8", "#a3d8b1", "#3d514a"),
    ("#20232d", "#2a2e3c", "#f2ecdf", "#bcc2d0", "#dbb282", "#465066"),
    ("#faf5f0", "#ffffff", "#3c3936", "#77716a", "#9a6044", "#ddd3c9"),
])
font = secrets.choice(["system-ui,sans-serif", "Georgia,'Noto Serif CJK SC',serif", "'Trebuchet MS',system-ui,sans-serif"])
width = secrets.choice([960, 1040, 1120, 1200])
radius = secrets.choice([4, 12, 22])
title = secrets.choice(theme["titles"])
headline = secrets.choice(theme["headline"])
entries = SystemRandom().sample(theme["entries"], 3)
marks = [
    '<path d="M25 95C18 48 45 24 96 22c1 48-20 79-71 73Zm1-1 46-48"/>',
    '<circle cx="60" cy="60" r="38"/><path d="M22 60h76M60 22v76"/>',
    '<path d="m20 88 28-53 20 30 14-22 20 45Z"/><circle cx="83" cy="25" r="7"/>',
    '<rect x="24" y="24" width="30" height="30"/><rect x="66" y="24" width="30" height="30"/><rect x="24" y="66" width="30" height="30"/><circle cx="81" cy="81" r="15"/>',
    '<path d="M23 29c16-7 26-4 37 4 11-8 21-11 37-4v65c-16-7-26-4-37 4-11-8-21-11-37-4Zm37 4v65"/>',
    '<path d="M17 87c21-52 38 29 58-23s25-21 28-37M18 106h85"/>',
]
mark = secrets.choice(marks)
svg = '<svg viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">' + mark + '</svg>'
e = lambda value: html.escape(str(value), quote=True)
nav = '<nav aria-label="页面导航"><a href="#collection">浏览记录</a><a href="#about">关于这里</a></nav>'
brand = '<a class="brand" href="#top">' + svg + '<span>' + e(title) + '</span></a>'
lead = '<p class="eyebrow">' + e(theme["label"]) + '</p><h1>' + e(headline) + '</h1><p class="lead">' + e(theme["intro"]) + '</p>'
about = '<section class="about" id="about"><h2>关于这里</h2><p>' + e(theme["about"]) + '</p></section>'
cards = ''.join('<article><span class="number">0' + str(i + 1) + '</span><h2>' + e(name) + '</h2><p>' + e(text) + '</p></article>' for i, (name, text) in enumerate(entries))
kind = theme["kind"]
if kind == "profile":
    content = '<header>' + brand + nav + '</header><main><section class="hero split"><div>' + lead + '</div><div class="emblem">' + svg + '</div></section><section class="cards" id="collection">' + cards + '</section>' + about + '</main>'
    extra = '.split{display:grid;grid-template-columns:1.6fr 1fr;gap:7%;align-items:center}.emblem{border:1px solid var(--line);border-radius:50%;padding:18%;color:var(--accent)}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:32px}.cards article{border-top:2px solid var(--accent);padding-top:22px}'
elif kind == "journal":
    content = '<header class="masthead">' + brand + nav + '</header><main><section class="hero">' + lead + '</section><section class="entries" id="collection">' + cards + '</section>' + about + '</main>'
    extra = '.masthead{border-bottom:3px double var(--line)}.hero{max-width:820px}.entries article{display:grid;grid-template-columns:60px 1fr;gap:0 24px;padding:30px 0;border-top:1px solid var(--line)}.entries .number{grid-row:span 2}.entries h2{margin:0}.entries p{grid-column:2;margin-bottom:0}'
elif kind == "studio":
    content = '<header>' + brand + nav + '</header><main><section class="hero statement">' + lead + '</section><section class="projects" id="collection">' + cards + '</section>' + about + '</main>'
    extra = '.statement{padding:6%;background:var(--panel);border-left:6px solid var(--accent);border-radius:var(--radius)}.projects{display:grid;grid-template-columns:repeat(3,1fr);gap:24px}.projects article{padding:28px;border:1px solid var(--line);border-radius:var(--radius)}.projects h2{margin-top:36px}'
elif kind == "gallery":
    tiles = ''.join('<article><div class="study" style="transform:rotate(' + str(i - 1) + 'deg)">' + svg + '</div><h2>' + e(name) + '</h2><p>' + e(text) + '</p></article>' for i, (name, text) in enumerate(entries))
    content = '<header>' + brand + nav + '</header><main><section class="hero">' + lead + '</section><section class="gallery-grid" id="collection">' + tiles + '</section>' + about + '</main>'
    extra = '.hero{text-align:center;max-width:850px;margin-inline:auto}.gallery-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:30px}.study{aspect-ratio:4/3;background:var(--panel);border:1px solid var(--line);border-radius:var(--radius);padding:18%;color:var(--accent)}.gallery-grid h2{font-size:1.2rem}'
elif kind == "library":
    content = '<header>' + brand + nav + '</header><main><section class="hero reading">' + lead + '</section><section class="shelf" id="collection">' + cards + '</section>' + about + '</main>'
    extra = '.reading{padding-bottom:34px;border-bottom:1px solid var(--line)}.shelf{display:grid;grid-template-columns:repeat(3,1fr);gap:26px}.shelf article{background:var(--panel);padding:32px 26px;border-left:9px solid var(--accent);box-shadow:4px 5px 0 var(--line)}.shelf h2{margin-top:44px}.shelf p{font-size:.95rem}'
else:
    content = '<header>' + brand + nav + '</header><main><section class="hero horizon"><div>' + lead + '</div><div class="landmark">' + svg + '</div></section><section class="trail-list" id="collection">' + cards + '</section>' + about + '</main>'
    extra = '.horizon{display:grid;grid-template-columns:1.7fr 1fr;gap:8%;align-items:center}.landmark{color:var(--accent);padding:10%}.trail-list{padding-left:30px;border-left:1px solid var(--line)}.trail-list article{position:relative;margin-bottom:38px}.trail-list article:before{content:"";position:absolute;left:-36px;top:8px;width:11px;height:11px;border-radius:50%;background:var(--accent)}.trail-list .number{font-size:.8rem}'
variables = ':root{' + f'--paper:{paper};--panel:{panel};--ink:{ink};--muted:{muted};--accent:{accent};--line:{line};--radius:{radius}px;--width:{width}px;--font:{font};' + '}'
base = '*{box-sizing:border-box}html{scroll-behavior:auto}body{margin:0;background:var(--paper);color:var(--ink);font:17px/1.8 var(--font)}a{color:inherit;text-decoration:none}a:focus-visible{outline:2px solid var(--accent);outline-offset:5px}header,main,footer{width:min(var(--width),88%);margin-inline:auto}header{display:flex;justify-content:space-between;align-items:center;gap:24px;padding-block:30px}.brand{display:flex;align-items:center;gap:12px;font-weight:650}.brand svg{width:36px;height:36px;color:var(--accent);flex-shrink:0}nav{display:flex;gap:24px;font-size:.85rem}nav a{border-bottom:1px solid var(--line)}.hero{padding-block:clamp(42px,7vw,100px);margin-bottom:40px}h1{font-size:clamp(2.4rem,6.5vw,5rem);line-height:1.2;font-weight:500;letter-spacing:-.035em;margin:20px 0 26px}h2{font-size:1.25rem;font-weight:600}p{color:var(--muted)}.lead{max-width:680px}.eyebrow,.number{color:var(--accent);font-size:.8rem;letter-spacing:.14em}.about{margin-top:70px;padding-top:30px;border-top:1px solid var(--line);max-width:740px}footer{display:flex;justify-content:space-between;gap:18px;margin-block:60px 28px;font-size:.78rem;color:var(--muted)}svg{display:block;width:100%;height:auto}'
mobile = '@media(max-width:680px){body{font-size:16px}header{align-items:flex-start;flex-direction:column;gap:14px}nav{gap:22px}.split,.horizon,.cards,.projects,.gallery-grid,.shelf{grid-template-columns:1fr}.emblem,.landmark{display:none}.hero{padding-block:36px}.statement{padding:8%}.entries article{grid-template-columns:36px 1fr;gap:0 12px}.study{aspect-ratio:2/1;padding:10% 32%}.about{margin-top:45px}footer{flex-direction:column;margin-top:45px}}'
footer = '<footer><span>' + e(title) + '</span><span>' + e(secrets.choice(['留给日常与好奇心的地方', '从小事开始，保持观察', '记录过程，也享受过程'])) + '</span></footer>'
print('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="description" content="' + e(theme["intro"]) + '"><title>' + e(title) + '</title><style>' + variables + base + extra + mobile + '</style></head><body class="' + kind + '" id="top">' + content + footer + '</body></html>')
PY_SITE
}
self_site_write() (
    local tmp
    [[ -d "$SELF_DIR" && ! -L "$SELF_DIR" && -d "$SELF_DIR/work" && ! -L "$SELF_DIR/work" \
        && -f "$SELF_DIR/files.sha256" && ! -L "$SELF_DIR/files.sha256" ]] || return 1
    [[ ! -L "$SELF_WEB" && ( ! -e "$SELF_WEB" || -d "$SELF_WEB" ) ]] || return 1
    if [[ -e "$SELF_WEB/index.html" || -L "$SELF_WEB/index.html" ]]; then
        self_file_owned "$SELF_WEB/index.html" || { warn '网页已被修改或无法确认归属，未覆盖。' >&2; return 1; }
        return 0
    fi
    tmp="$(mktemp "$SELF_DIR/work/site.XXXXXX")" || return 1
    trap 'rm -f -- "$tmp"' EXIT
    self_site_render > "$tmp" || return 1
    [[ -s "$tmp" ]] || return 1
    install -d -m 755 "$SELF_WEB" || return 1
    self_publish "$tmp" "$SELF_WEB/index.html" 644
)
# 使用原已纳入卸载范围的挑战目录暂存公开 HTML，确保与首页同文件系统原子替换。
# 暂存文件无凭据，初始 600；目录/符号链接检查不依赖旧版宽松的挑战路径白名单。
self_site_stage_dir() {
    local path mode
    for path in "$SELF_WEB" "$SELF_WEB/.well-known" "$SELF_WEB/.well-known/acme-challenge"; do
        [[ ! -L "$path" ]] || return 1
        if [[ ! -e "$path" && "$path" != "$SELF_WEB" ]]; then install -d -m 755 "$path" || return 1; fi
        [[ -d "$path" && "$(stat -c %u "$path")" == 0 ]] || return 1
        mode="$(stat -c %a "$path")" || return 1
        (( (8#$mode & 0022) == 0 )) || return 1
        [[ "$(stat -c %d "$path")" == "$(stat -c %d "$SELF_WEB")" ]] || return 1
    done
    printf '%s' "$SELF_WEB/.well-known/acme-challenge"
}
self_site_atomic_publish() (
    local source="$1" directory tmp
    [[ -f "$source" && ! -L "$source" && -s "$source" ]] || return 1
    directory="$(self_site_stage_dir)" || return 1
    tmp="$(mktemp "$directory/.page.XXXXXX")" || return 1
    trap 'rm -f -- "$tmp"' EXIT
    cp -- "$source" "$tmp" && self_publish "$tmp" "$SELF_WEB/index.html" 644
)
self_site_http_matches() (
    local domain="$1" expected="$2" tmp result
    tmp="$(mktemp "$SELF_DIR/work/site-response.XXXXXX")" || return 1
    trap 'rm -f -- "$tmp"' EXIT
    result="$(curl --noproxy '*' --http2 --tlsv1.3 --tls-max 1.3 -fsS --connect-timeout 5 --max-time 15 \
        --resolve "$domain:8443:127.0.0.1" -o "$tmp" -w '%{http_version} %{http_code}' "https://$domain:8443/")" || return 1
    [[ "$result" == '2 200' ]] && cmp -s -- "$expected" "$tmp"
)
website_random() (
    need_root
    [[ $# == 0 ]] || fail '用法：website-random（仅更换自有域名网页）'
    self_operation_lock; load_metadata
    [[ "$NODE_MODE" == self ]] || fail '随机网页仅适用于自有域名模式。'
    if ! self_managed_paths_ok || ! self_cleanup_preflight || ! self_config_check; then fail '资源归属或节点配置异常，未更换网页。'; fi
    [[ -f "$SELF_WEB/index.html" && ! -L "$SELF_WEB/index.html" ]] || fail '原网页缺失或路径异常，未修改。'
    systemctl is-active --quiet nginx || fail 'Nginx 当前未运行，请先恢复原网站。'
    self_site_http_matches "$SNI" "$SELF_WEB/index.html" || fail '原网站 HTTPS/H2/200 或内容基线未通过，未修改。'
    self_site_stage_dir >/dev/null || fail '网站暂存目录权限、链接或文件系统异常，未修改。'
    local backup committed=0 changed=0 rc
    backup="$(mktemp -d "$SELF_DIR/work/site-backup.XXXXXX")" || exit 1
    if ! cp -a "$SELF_WEB/index.html" "$backup/index.html" || ! cp -a "$SELF_DIR/files.sha256" "$backup/files.sha256"; then
        rm -rf -- "$backup"; fail '网页备份失败，未修改。'
    fi
    trap 'rc=$?; trap - EXIT; trap "" HUP INT TERM
        if (( ! committed && changed )); then
            if ! self_site_atomic_publish "$backup/index.html" || ! cp -a "$backup/files.sha256" "$SELF_DIR/files.sha256"; then
                warn "网页回滚失败，保留备份：$backup" >&2; exit 1
            fi
        fi
        rm -rf -- "$backup" || exit 1
        exit "$rc"' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    self_site_render "$backup/index.html" > "$backup/new.html" || fail '随机网页生成失败，原网页保留。'
    [[ -s "$backup/new.html" ]] || fail '随机网页为空，原网页保留。'
    # shellcheck disable=SC2034 # EXIT trap 读取事务状态。
    changed=1
    self_site_atomic_publish "$backup/new.html" || fail '网页发布失败，正在恢复原网页。'
    self_site_http_matches "$SNI" "$SELF_WEB/index.html" || fail '新网页 HTTPS/H2/200 或内容检查失败，正在恢复原网页。'
    # shellcheck disable=SC2034 # EXIT trap 读取事务状态。
    committed=1
    rm -rf -- "$backup" || fail "网页已更换，但备份清理失败：$backup"
    trap - EXIT HUP INT TERM
    ok '随机网页已更换；节点信息、证书和链接不变，无需重新导入，也未重启服务。'
)
self_scrub_logs() {
    # 轮换时同时脱敏旧/新 Token，按长度排序，避免短 Token 是长 Token 前缀时漏出尾部。
    [[ -f "$SELF_DIR/cloudflare.ini" || $# -gt 0 ]] || return 0
    python3 - "$SELF_DIR/logs" "$SELF_DIR/cloudflare.ini" "$@" <<'PY_SCRUB'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
tokens = set()
for name in sys.argv[2:]:
    source = pathlib.Path(name)
    if source.is_file() and not source.is_symlink():
        tokens.update(re.findall(rb"^dns_cloudflare_api_token\s*=\s*(\S+)", source.read_bytes(), re.M))
if tokens:
    for p in root.rglob("*"):
        if p.is_file() and not p.is_symlink():
            data = p.read_bytes()
            clean = data
            for token in sorted(tokens, key=len, reverse=True):
                clean = clean.replace(token, b"[REDACTED]")
            if clean != data:
                p.write_bytes(clean)
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
        -alpn h2 -verify_hostname "$domain" -verify_return_error -CApath /etc/ssl/certs </dev/null 2>&1 | tr -d '\000')" || return 1
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
    logger -p daemon.err -t vless-reality-cert -- "证书/DNS 监测异常或证书到期预警：$domain；请检查 journalctl -u vless-reality-cert。"
    if [[ -x "$hook" && -f "$hook" && ! -L "$hook" && "$(stat -c %u "$hook")" == 0 \
        && "$(stat -c %a "$hook")" =~ ^[57]00$ ]]; then "$hook" "$domain"; fi
}
self_cert_renew() (
    need_root
    self_exists || return 1
    exec 8> "$SELF_DIR/operation.lock"; flock -x 8 || return 1
    local domain rc=0
    domain="$(self_state domain)" || return 1
    if ! self_dns_check "$domain" > "$SELF_DIR/logs/dns-check.log" 2>&1; then
        logger -p daemon.err -t vless-reality-cert -- "DNS 与当前 VPS 不符或无法验证：$domain；未修改 DNS，需管理员检查。"
        rc=1
    fi
    local dns_result=0
    security_dns_changed "$domain" > "$SELF_DIR/logs/dns-baseline-check.log" 2>&1 || dns_result=$?
    if (( dns_result==2 )); then
        logger -p daemon.err -t vless-reality-cert -- "DNS 记录与已确认基线不同：$domain；未改 DNS、未封禁连接。"
        rc=1
    elif (( dns_result!=0 )); then logger -p daemon.warning -t vless-reality-cert -- "DNS 基线未验证：$domain；请运行 security-check 核对。"; fi
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
        '{domain:$domain,result:$result,time:$time}' > "$tmp" && mv "$tmp" "$SELF_DIR/renew-status.json" || return 1
    if (( rc )); then logger -p daemon.err -t vless-reality-cert -- "证书续期或 DNS 安全监测失败：$domain；请以 root 检查项目私有日志。"; fi
    return "$rc"
)
self_renew_test() {
    local domain="$1" result=failed tmp
    [[ -x "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx" ]] && self_file_owned "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx" && self_certbot renew --dry-run --non-interactive --cert-name "$domain" > "$SELF_DIR/logs/renew-test.log" 2>&1 \
        && "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx" >> "$SELF_DIR/logs/renew-test.log" 2>&1 \
        && self_wait_tls "$domain" && result=passed
    tmp="$(mktemp "$SELF_DIR/.renew.XXXXXX")" || return 1
    if ! jq -n --arg domain "$domain" --arg result "$result" --arg date "$(date -u +%FT%TZ)" \
        '{domain:$domain,result:$result,time:$date}' > "$tmp" || ! mv -f "$tmp" "$SELF_DIR/renew-test.json"; then
        rm -f -- "$tmp"; return 1
    fi
    [[ "$result" == passed ]]
}
self_read_cf_token() {
    local source="${1:-}" token
    export -n token # 不继承调用者同名变量的 export 属性。
    if [[ -n "$source" ]]; then
        if [[ ! -f "$source" || -L "$source" || "$(stat -c %u "$source")" != 0 || "$(stat -c %a "$source")" != 600 ]]; then
            warn '新凭据源文件必须为 root 所有、权限 600 的普通文件。' >&2; return 1
        fi
        token="$(sed -n 's/^dns_cloudflare_api_token *= *\([A-Za-z0-9_-]*\) *$/\1/p' "$source")" || return 1
    else
        [[ -t 0 ]] || { warn '非交互更换请设置 VLESS_CF_CREDENTIALS 为新凭据文件路径；不要将 Token 放入命令参数。' >&2; return 1; }
        read -r -s -p '新的 Cloudflare API Token（对应 Zone 的 DNS Edit + Zone Read，不回显）：' token || { printf '\n' >&2; return 1; }
        printf '\n' >&2
    fi
    [[ "$token" =~ ^[A-Za-z0-9_-]{20,200}$ ]] || { warn '新 Token 格式无效，未修改。' >&2; return 1; }
    printf '%s' "$token"
}
self_cf_renewal_binding() {
    local directory="$SELF_DIR/acme/renewal" path="$SELF_DIR/acme/renewal/$SNI.conf"
    [[ -d "$directory" && ! -L "$directory" && -f "$path" && ! -L "$path" && "$(stat -c %u "$path")" == 0 ]] || return 1
    python3 - "$path" "$SELF_DIR/cloudflare.ini" <<'PY_CF_BINDING'
import configparser, pathlib, sys
try:
    conf = configparser.RawConfigParser()
    conf.read_string("[lineage]\n" + pathlib.Path(sys.argv[1]).read_text())
    params = conf["renewalparams"]
    assert params.get("authenticator") == "dns-cloudflare"
    assert params.get("dns_cloudflare_credentials") == sys.argv[2]
except Exception:
    sys.exit(1)
PY_CF_BINDING
}
self_cf_token_probe() {
    local domain="$1" email="$2" credentials="$3" directory="$4" logs="$5"
    # 全新账户和目录，避免复用旧 ACME 授权而让无权限的新 Token 误通过。
    install -d -m 700 "$directory/acme" "$directory/work" || return 1
    certbot certonly --dry-run --non-interactive --agree-tos --email "$email" \
        --server https://acme-staging-v02.api.letsencrypt.org/directory \
        --dns-cloudflare --dns-cloudflare-credentials "$credentials" --dns-cloudflare-propagation-seconds 60 \
        --preferred-challenges dns-01 --cert-name "$domain" -d "$domain" --key-type ecdsa --no-directory-hooks \
        --config /dev/null --config-dir "$directory/acme" --work-dir "$directory/work" --logs-dir "$logs"
}
self_cf_token_rotate() (
    need_root
    [[ $- != *x* ]] || fail '凭据更换禁止使用 bash -x。'
    [[ $# == 0 ]] || fail '用法：cert token（隐藏输入，或用 VLESS_CF_CREDENTIALS 指定凭据源文件）'
    local token current_token email backup expected_domain expected_self probe_logs='' log_file='' changed=0 committed=0 rc rollback_ok=1
    export -n token current_token
    # 只读预检后收集输入，不让停留在提示符上的会话占用自动续期锁。
    load_metadata
    if [[ "$NODE_MODE" != self ]] || ! self_exists; then fail 'Token 更换仅用于自有域名模式。'; fi
    [[ -f "$SELF_DIR/state.json" && ! -L "$SELF_DIR/state.json" && "$(self_state method)" == cloudflare ]] || fail '此节点不是 Cloudflare DNS-01 模式。'
    expected_domain="$SNI"
    expected_self="$(stat -c '%d:%i' "$SELF_DIR")" || fail '安装目录发生变化，请重新执行。'
    say "当前证书域名：$expected_domain"
    token="$(self_read_cf_token "${VLESS_CF_CREDENTIALS:-}")" || fail '未取得有效的新 Token，未修改。'
    say '新 Token 已读取；如有正在执行的节点或续期任务，将等待它完成。'
    self_operation_lock; load_metadata
    [[ "$NODE_MODE" == self ]] || fail 'Token 更换仅用于自有域名模式。'
    [[ "$SNI" == "$expected_domain" && "$expected_self" == "$(stat -c '%d:%i' "$SELF_DIR" 2>/dev/null)" ]] || fail '等待输入期间域名或安装目录已改变，请重新执行；未修改。'
    if ! self_managed_paths_ok || ! self_cleanup_preflight; then fail '资源或凭据归属异常，未修改。'; fi
    [[ "$(self_state method)" == cloudflare && "$(self_state domain)" == "$SNI" ]] || fail '此节点不是使用 Cloudflare DNS-01 的当前自有域名。'
    [[ -f "$SELF_DIR/cloudflare.ini" && ! -L "$SELF_DIR/cloudflare.ini" && "$(stat -c %u "$SELF_DIR/cloudflare.ini")" == 0 ]] || fail '原凭据缺失或归属异常，未修改。'
    self_cf_renewal_binding || fail '保存的续期配置未指向本项目 Cloudflare 凭据，未修改。'
    [[ "$(stat -c %d "$SELF_DIR/work")" == "$(stat -c %d "$SELF_DIR")" ]] || fail '私有工作目录跨文件系统，无法安全更换凭据。'
    local path target
    for path in "$SELF_DIR/renew-test.json" "$SELF_DIR/logs/renew-test.log"; do
        if [[ -e "$path" || -L "$path" ]]; then
            [[ -f "$path" && ! -L "$path" && "$(stat -c %u "$path")" == 0 ]] || fail '续期记录路径异常，未修改。'
        fi
    done
    if [[ ! -x "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx" ]] || ! self_file_owned "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx"; then fail '续期 reload hook 异常，未修改。'; fi
    if ! systemctl is-enabled --quiet vless-reality-cert.timer || ! systemctl is-active --quiet vless-reality-cert.timer; then fail '自动续期 timer 未就绪，请先恢复续期任务。'; fi
    say '检查当前证书、网站和自动续期配置…'
    self_wait_tls "$SNI" || fail '当前网站或证书基线异常，未更换 Token。'
    email="$(self_state email)" || fail '缺少原证书通知邮箱。'
    current_token="$(self_read_cf_token "$SELF_DIR/cloudflare.ini" 2>/dev/null)" || fail '原凭据格式异常，未修改。'
    if [[ "$token" == "$current_token" ]]; then
        unset token current_token; fail '新 Token 与当前相同，未执行更换；请提供不同的新 Token。'
    fi
    backup="$(mktemp -d "$SELF_DIR/work/token-backup.XXXXXX")" || return 1
    if ! cp -a "$SELF_DIR/cloudflare.ini" "$backup/old.ini" || ! cp -a "$SELF_DIR/files.sha256" "$backup/files.sha256" \
        || ! cp -a "$SELF_DIR/acme/renewal/$SNI.conf" "$backup/renewal.conf"; then
        rm -rf -- "$backup"; fail '凭据备份失败，未修改。'
    fi
    for path in "$SELF_DIR/renew-test.json" "$SELF_DIR/logs/renew-test.log"; do
        if [[ -f "$path" ]] && ! cp -a "$path" "$backup/${path##*/}"; then
            rm -rf -- "$backup"; fail '续期记录备份失败，未修改。'
        fi
    done
    trap 'rc=$?; trap - EXIT; trap "" HUP INT TERM
        if (( ! committed && changed )); then
            if ! cp -a "$backup/old.ini" "$backup/restore.ini" || ! mv -f -- "$backup/restore.ini" "$SELF_DIR/cloudflare.ini" \
                || ! cp -a "$backup/files.sha256" "$SELF_DIR/files.sha256"; then rollback_ok=0; fi
            cp -a "$backup/renewal.conf" "$SELF_DIR/acme/renewal/$SNI.conf" || rollback_ok=0
            for path in renew-test.json renew-test.log; do
                target="$SELF_DIR/$path"; [[ "$path" != renew-test.log ]] || target="$SELF_DIR/logs/$path"
                if [[ -f "$backup/$path" ]]; then cp -a "$backup/$path" "$target" || rollback_ok=0
                else rm -f -- "$target" || rollback_ok=0; fi
            done
        fi
        if ! self_scrub_logs "$backup/old.ini" "$backup/new.ini"; then
            warn "日志脱敏失败，保留 root 专用备份：$backup" >&2; exit 1
        fi
        if (( ! rollback_ok )); then warn "Token 回滚失败，保留备份：$backup" >&2; exit 1; fi
        [[ -z "$probe_logs" ]] || rm -rf -- "$probe_logs" || exit 1
        rm -rf -- "$backup" || exit 1
        exit "$rc"' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    printf 'dns_cloudflare_api_token = %s\n' "$token" > "$backup/new.ini" || fail '新凭据暂存失败，未修改。'
    unset token current_token
    chmod 600 "$backup/new.ini" || fail '新凭据权限设置失败。'
    probe_logs="$(mktemp -d "$SELF_DIR/logs/token-probe.XXXXXX")" || fail '测试日志目录创建失败。'
    log_file="$(mktemp "$SELF_DIR/logs/token-change.XXXXXX")" || fail '测试日志创建失败。'
    say '验证新 Token 的实际 DNS-01 权限（等待 DNS 传播，通常至少 60 秒）…'
    self_cf_token_probe "$SNI" "$email" "$backup/new.ini" "$backup/probe" "$probe_logs" > "$log_file" 2>&1 \
        || fail "新 Token 的 DNS-01 验证失败，原凭据保留；脱敏日志：$log_file"
    cp -a "$backup/new.ini" "$backup/publish.ini" || fail '新凭据发布暂存失败。'
    # shellcheck disable=SC2034 # EXIT trap 读取提交状态。
    changed=1
    self_publish "$backup/publish.ini" "$SELF_DIR/cloudflare.ini" 600 || fail '凭据或归属记录发布失败，正在回滚。'
    say '新 Token 的 DNS-01 已通过，正在验证原自动续期流程（可能再次等待 DNS 传播）…'
    if ! self_renew_test "$SNI"; then
        [[ ! -f "$SELF_DIR/logs/renew-test.log" ]] || cat "$SELF_DIR/logs/renew-test.log" >> "$log_file"
        fail "原续期流程或 Nginx reload hook 验证失败，正在回滚；脱敏日志：$log_file"
    fi
    if ! cmp -s "$backup/renewal.conf" "$SELF_DIR/acme/renewal/$SNI.conf" || ! self_cf_renewal_binding \
        || ! systemctl is-enabled --quiet vless-reality-cert.timer || ! systemctl is-active --quiet vless-reality-cert.timer; then
        fail '续期配置或 timer 复核失败，正在回滚。'
    fi
    self_scrub_logs "$backup/old.ini" "$backup/new.ini" || fail '日志脱敏失败，正在回滚。'
    # shellcheck disable=SC2034 # EXIT trap 读取提交状态。
    committed=1
    if ! rm -rf -- "$probe_logs" "$backup" || ! rm -f -- "$log_file"; then fail '新 Token 已验证并应用，但临时文件清理失败。'; fi
    trap - EXIT HUP INT TERM
    ok 'Cloudflare Token 已更换；新 DNS-01、原续期 dry-run 和 Nginx reload hook 均通过。'
    say '自动续期将使用新 Token；现有证书和节点信息不变，Xray 未重启。确认成功后再到 Cloudflare 撤销旧 Token。'
)
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
    [[ $# -le 1 ]] || fail '用法：cert [status|renew-test|token]；不要把 Token 放入命令参数'
    self_exists || fail '仅自有域名模式有本脚本管理的证书。'
    case "${1:-status}" in
        status) cert_status ;;
        token) shift; self_cf_token_rotate "$@" ;;
        renew-test) if ( exec 8> "$SELF_DIR/operation.lock"; flock -x 8; self_renew_test "$(self_state domain)" ); then ok '证书续期 dry-run 和 Nginx reload hook 均通过。';
            else fail "续期验证失败；详见 $SELF_DIR/logs/renew-test.log（root 专用）。"; fi ;;
        *) fail '用法：cert [status|renew-test|token]' ;;
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
    # 前置预检之后再复核，避免依赖安装期间 DNS 改变仍继续签发。
    self_dns_check "$SNI" || fail '部署期间 DNS 复核未通过，正在回滚；请核对域名解析。'
    curl --version | grep -q HTTP2 || fail '系统 curl 必须支持 HTTP/2。'
    # 只处理本次新安装软件包创建的默认入口，预存站点不动。
    if [[ "$had_nginx" == false && -L /etc/nginx/sites-enabled/default ]]; then
        readlink /etc/nginx/sites-enabled/default > "$SELF_DIR/default-target"
        self_track "$SELF_DIR/default-target"
        rm -- /etc/nginx/sites-enabled/default
    fi
    nginx -T 2>&1 | grep -F 'include /etc/nginx/conf.d/*.conf;' >/dev/null || fail 'Nginx 主配置未包含 conf.d/*.conf，未修改已有主配置。'
    self_site_write || fail '本地静态网页生成失败；安装将回滚。'
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
    security_dns_baseline "$SNI" || warn '警告：无法保存一致的 DNS 安全基线；安装后请运行 security-check 核对。'
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
        self_prompt_domain || { say '已取消安装。'; return 0; }
        domain="$SELF_INPUT_DOMAIN"
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
            .owned|.receipt.??????|.renew.??????|files.sha256|cli.ini|state.json|cloudflare.ini|default-target|renew-test.json|renew-status.json|network-check.json|security-last.json|security-dns.json|operation.lock|acme|logs|work) ;;
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
        if systemctl is-failed --quiet "$unit"; then systemctl reset-failed "$unit" || return 1; fi
    done
    if systemctl is-enabled --quiet vless-reality-cert.timer 2>/dev/null; then systemctl disable vless-reality-cert.timer || return 1; fi
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
transport_probe_https() {
    local socks_port="$1" url curl_status
    local targets=(https://www.debian.org/ https://www.cloudflare.com/cdn-cgi/trace)
    # curl 的连接超时还包含代理链路与目标站的 TLS 握手。允许该阶段用满单次预算。
    # 两个代理请求各 8 秒，均失败再做各 2 秒的直连诊断。
    for url in "${targets[@]}"; do
        if curl --noproxy '' --proxy "socks5h://127.0.0.1:$socks_port" -fsS --connect-timeout 8 --max-time 8 \
            "$url" -o /dev/null 2>/dev/null; then
            return 0
        else
            curl_status=$?
            warn "代理验证 $url 失败（curl 退出码 $curl_status）。" >&2
        fi
    done
    for url in "${targets[@]}"; do
        if curl --noproxy '*' -fsS --connect-timeout 2 --max-time 2 "$url" -o /dev/null 2>/dev/null; then return 1; fi
    done
    return 3
}

self_client_probe() (
    local domain="$1" address="$2" server_port="${3:-443}" kind="${4:-valid}" test_dir pid='' socks_port uuid sid="$SHORT_ID" pub="$PUBLIC_KEY" tries=5 seconds=20 ready=0
    local network path='' flow='xtls-rprx-vision'
    network="$(config_transport)" || return 2
    if [[ "$network" == xhttp ]]; then
        path="$(config_xhttp_path)" || return 2
        flow=''
    fi
    test_dir="$(mktemp -d /tmp/vless-reality-client.XXXXXX)" || return 2
    trap 'rc=$?; trap - EXIT
        if [[ -n "$pid" ]]; then
            if stop_client_residue "$test_dir"; then wait "$pid" 2>/dev/null || true;
            else warn "检查客户端未能安全停止；保留归属目录供卸载重试：$test_dir" >&2; exit 2; fi
        fi
        rm -rf -- "$test_dir"; exit "$rc"' EXIT
    printf 'vless-reality-setup\n' > "$test_dir/.vless-reality-owned"
    if command -v python3 >/dev/null; then
        socks_port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')" || return 2
    else
        # 普通模式没有 Python 依赖；下方仍核对临时监听确由本次客户端创建。
        socks_port="$(shuf -i 32768-60999 -n 1)" || return 2
    fi
    uuid="$(config_uuid)" || return 2
    case "$kind" in
        valid|switch) ;;
        bad-uuid)
            local wrong
            wrong="$("$XRAY_BIN" uuid)" || return 2
            [[ "$wrong" != "$uuid" && "$wrong" =~ ^[0-9a-f-]{36}$ ]] || return 2
            uuid="$wrong"; tries=1; seconds=4 ;;
        bad-reality) sid=0000000000000000; tries=1; seconds=4 ;;
        bad-public-key)
            local pair=()
            mapfile -t pair < <(generate_reality_keys)
            [[ ${#pair[@]} == 2 && "${pair[1]}" != "$PUBLIC_KEY" ]] || return 2
            pub="${pair[1]}"; tries=1; seconds=4 ;;
        *) return 2 ;;
    esac
    printf '%s\n' "$uuid" "$sid" "$CLIENT_ENCRYPTION" > "$test_dir/credentials" || return 2
    jq -n --rawfile credentials "$test_dir/credentials" --arg host "$address" --argjson port "$server_port" --argjson socks "$socks_port" \
        --arg sni "$domain" --arg pub "$pub" --arg network "$network" --arg flow "$flow" --arg path "$path" \
        '($credentials | split("\n")) as $secret | {
        log:{loglevel:"warning"}, inbounds:[{listen:"127.0.0.1",port:$socks,protocol:"socks",settings:{auth:"noauth"}}],
        outbounds:[{protocol:"vless",settings:{vnext:[{address:$host,port:$port,users:[{id:$secret[0],flow:$flow,encryption:$secret[2]}]}]},
          streamSettings:({network:$network,security:"reality",realitySettings:{serverName:$sni,fingerprint:"chrome",publicKey:$pub,shortId:$secret[1]}}
            + if $network=="xhttp" then {xhttpSettings:{path:$path,mode:"auto"}} else {} end)}]
        }' > "$test_dir/client.json" || return 2
    rm -f -- "$test_dir/credentials" || return 2
    "$XRAY_BIN" run -test -config "$test_dir/client.json" > "$test_dir/test.log" 2>&1 || return 2
    # 临时检测客户端不继承管理锁；异常退出后也不能阻塞后续管理/卸载。
    "$XRAY_BIN" run -config "$test_dir/client.json" 7>&- 8>&- 9>&- > "$test_dir/client.log" 2>&1 &
    pid=$!
    printf '%s %s\n' "$pid" "$(awk '{print $22}' "/proc/$pid/stat")" > "$test_dir/client.pid"
    local attempt
    for attempt in {1..20}; do
        kill -0 "$pid" 2>/dev/null || return 2
        if ss -H -ltnp "sport = :$socks_port" | grep -F "pid=$pid," >/dev/null; then ready=1; break; fi
        sleep 0.1
    done
    (( ready )) || return 2
    if [[ "$kind" == switch ]]; then
        local request_rc=0
        transport_probe_https "$socks_port" || request_rc=$?
        kill -0 "$pid" 2>/dev/null || return 2
        return "$request_rc"
    fi
    for (( attempt=1; attempt<=tries; attempt++ )); do
        if curl --noproxy '' --proxy "socks5h://127.0.0.1:$socks_port" -fsS --connect-timeout 3 --max-time "$seconds" \
            'https://www.debian.org/' -o /dev/null 2>/dev/null; then
            kill -0 "$pid" 2>/dev/null && return 0
            return 2
        fi
        kill -0 "$pid" 2>/dev/null || return 2
        (( attempt >= tries )) || sleep 1
    done
    # 只有准备成功且客户端仍运行时，才把请求失败分类为没有获得代理访问。
    return 1
)
self_reject_check() {
    local domain="$1" address="${2:-127.0.0.1:8443}" output
    output="$(timeout 10 openssl s_client -connect "$address" -servername invalid.example -tls1_3 </dev/null 2>&1 || true)"
    [[ "$output" == *'no peer certificate available'* ]] || return 1
    output="$(timeout 10 openssl s_client -connect "$address" -noservername -tls1_3 </dev/null 2>&1 || true)"
    [[ "$output" == *'no peer certificate available'* && "$domain" != invalid.example ]]
}
self_report() {
    local label="$1"; shift
    if "$@"; then ok "通过：$label"; else warn "失败：$label"; SELF_CHECK_FAILURES=$((SELF_CHECK_FAILURES + 1)); fi
}
self_config_policy() {
    local file="$1" domain="$2"
    valid_host "$domain" || return 1
    jq -e --arg sni "$domain" "$TRANSPORT_JQ"'
      def uuid: type=="string" and test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$") and .!="00000000-0000-0000-0000-000000000000";
      def limit: type=="object" and all([.afterBytes,.bytesPerSec,.burstBytesPerSec][]; type=="number" and .>=0 and .<=1073741824 and floor==.);
      (.inbounds|length)==1 and all(.inbounds[];
        .protocol=="vless" and .listen=="0.0.0.0" and .port==443 and
        managed_transport and all(.settings.clients[]; .id|uuid) and
        ([.settings.clients[].id|ascii_downcase]|length)==([.settings.clients[].id|ascii_downcase]|unique|length) and
        (.streamSettings.realitySettings as $r |
          $r.target=="127.0.0.1:8443" and $r.xver==0 and $r.show==false and $r.serverNames==[$sni] and
          ($r.privateKey|type=="string" and test("^[A-Za-z0-9_-]{43}$")) and
          ($r.shortIds|length)==1 and all($r.shortIds[]; type=="string" and test("^[0-9a-f]{16}$") and .!="0000000000000000") and
          (($r.masterKeyLog // "")=="") and
          (if $r|has("limitFallbackUpload") then $r.limitFallbackUpload|limit else true end) and
          (if $r|has("limitFallbackDownload") then $r.limitFallbackDownload|limit else true end)))' "$file" >/dev/null 2>&1
}
self_config_check() { self_config_policy "$CONFIG" "$SNI" && config_ok; }
self_renew_ready() {
    if systemctl is-failed --quiet vless-reality-cert.service; then return 1; fi
    if [[ -f "$SELF_DIR/renew-status.json" ]] && jq -e --arg domain "$SNI" '.domain==$domain and .result=="failed"' "$SELF_DIR/renew-status.json" >/dev/null; then return 1; fi
    systemctl is-enabled --quiet vless-reality-cert.timer && systemctl is-active --quiet vless-reality-cert.timer \
        && jq -e --arg domain "$SNI" '.result=="passed" and .domain==$domain' "$SELF_DIR/renew-test.json" >/dev/null \
        && [[ -x "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx" ]] && self_file_owned "$SELF_DIR/acme/renewal-hooks/deploy/reload-nginx"
}
# 仅凭连接失败不能判定 NAT；还须确认公网地址不在本机、路由经网关，且源地址是已配置的私网地址。
self_public_uses_nat() {
    local address="$1" addresses route
    addresses="$(ip -j -4 address show 2>/dev/null)" || return 1
    route="$(ip -j -4 route get "$address" 2>/dev/null)" || return 1
    python3 - "$address" "$addresses" "$route" <<'PY_NAT'
import ipaddress, json, sys
try:
    public = ipaddress.IPv4Address(sys.argv[1])
    configured = {ipaddress.IPv4Address(a['local']) for interface in json.loads(sys.argv[2])
                  for a in interface.get('addr_info', []) if a.get('family') == 'inet'}
    routes = json.loads(sys.argv[3])
    route = routes[0]
    source = ipaddress.IPv4Address(route.get('prefsrc') or route.get('src'))
    private = tuple(ipaddress.IPv4Network(n) for n in ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '100.64.0.0/10'))
    valid = (public.is_global and public not in configured and len(routes) == 1
             and not public.is_multicast and route.get('gateway') and route.get('dev') != 'lo' and route.get('type') != 'local'
             and source in configured and any(source in net for net in private))
    sys.exit(0 if valid else 1)
except (ValueError, TypeError, KeyError, IndexError, AttributeError):
    sys.exit(1)
PY_NAT
}
self_public_probe() {
    local domain="$1" address="$2" result rc=0 protocol code connected tls_connected
    result="$(curl --noproxy '*' --http2 --tlsv1.3 --tls-max 1.3 -fsS --connect-timeout 5 --max-time 15 \
        --resolve "$domain:443:$address" -o /dev/null -w '%{http_version} %{http_code} %{time_connect} %{time_appconnect}' "https://$domain:443/")" || rc=$?
    read -r protocol code connected tls_connected <<< "$result" || return 1
    if (( rc == 0 )) && [[ "$protocol $code" == '2 200' ]]; then return 0; fi
    # 只把 NAT 上未建立 TCP 的拒绝/超时分类为未验证；证书、TLS、HTTP/H2 等错误仍是失败。
    if [[ "$rc" == 7 || "$rc" == 28 ]] && [[ "$code" == 000 \
        && "$connected" =~ ^0([.]0+)?$ && "$tls_connected" =~ ^0([.]0+)?$ ]] && self_public_uses_nat "$address"; then
        return 3
    fi
    return 1
}
self_network_write() {
    local address="$1" public="$2" external="$3" result="$4" tmp
    tmp="$(mktemp "$SELF_DIR/.renew.XXXXXX")" || return 1
    if jq -n --arg domain "$SNI" --arg ip "$address" --arg public "$public" --arg external "$external" \
        --arg result "$result" --arg time "$(date -u +%FT%TZ)" \
        '{domain:$domain,ip:$ip,time:$time,public_probe:$public,external:$external,result:$result}' > "$tmp" \
        && chmod 600 "$tmp" && mv -f -- "$tmp" "$SELF_DIR/network-check.json"; then return 0; fi
    rm -f -- "$tmp"; return 1
}
self_network_status() {
    local file="$SELF_DIR/network-check.json" brief="${1:-}" result
    [[ -e "$file" || -L "$file" ]] || return 0
    if [[ ! -f "$file" || -L "$file" || "$(stat -c %u "$file")" != 0 || "$(stat -c %a "$file")" != 600 ]]; then
        warn '未验证：网络检查记录归属或权限异常。'; return 0
    fi
    if ! jq -e --arg domain "$SNI" 'def probe: .=="passed" or .=="failed" or .=="unverified";
        .domain==$domain and (.time|type=="string") and (.public_probe|probe) and (.external|probe) and
        (.result=="pending" or .result=="failed" or .result=="local_verified" or .result=="external_verified")' "$file" >/dev/null 2>&1; then
        warn '未验证：网络检查记录无效或对应其他域名，请重新运行 check-self。'; return 0
    fi
    result="$(jq -r .result "$file")" || return 1
    if [[ "$brief" == brief ]]; then
        case "$result" in
            pending) warn ' 公网连接：待外部验证（NAT 公网地址回访未通过；服务已保留）' ;;
            failed) warn ' 最近网络检查：失败，请运行 check-self 查看详情' ;;
        esac
        return 0
    fi
    jq -r 'def zh: if .=="passed" then "通过" elif .=="failed" then "失败" else "未验证" end;
        "最近网络检查：\(.time)\n公网 443 回访（本机源）：\(.public_probe|zh)\n外部程序验证：\(.external|zh)"' "$file"
    [[ "$result" != pending ]] || warn '公网可用性未验证：本地部署已保留，请从其他网络测试 HTTPS 与 VLESS。'
}
check_self() {
    need_root; self_operation_lock; load_metadata
    [[ "$NODE_MODE" == self ]] || fail 'check-self 只用于自有域名模式。'
    local SELF_CHECK_FAILURES=0 ip external="${VLESS_EXTERNAL_CHECK:-}" public_result=failed external_result=unverified rc=0 result
    ip="$(public_ipv4)" || fail '无法确认当前公网 IPv4。'
    self_report 'DNS A 直连当前 VPS、无 CNAME/CDN、无 AAAA（两个解析器）' self_dns_check "$SNI"
    self_report 'Xray TCP 443 服务和监听' service_ok
    self_report 'Nginx 8443 仅 IPv4 回环监听' self_listener_check
    self_report 'REALITY 本机 target、域名和传输配置' self_config_check
    self_report 'Nginx TLS 1.3 / X25519 / ALPN h2 / 证书链与域名' self_tls_check "$SNI" 127.0.0.1:8443
    self_report 'Nginx 已加载磁盘上的当前证书' self_loaded_cert_matches "$SNI"
    self_report '本机网站 HTTP/2 200，无跳转' self_http_check "$SNI" 127.0.0.1 8443
    self_report '拒绝未知 SNI 和无 SNI' self_reject_check "$SNI"
    self_report 'SNI 与 Host/:authority 一致性' self_authority_check "$SNI"
    self_report 'Xray 本机 443 HTTPS 回落，HTTP/2 200' self_http_check "$SNI" 127.0.0.1 443
    if self_public_probe "$SNI" "$ip"; then
        public_result=passed; ok '通过：公网地址 443 HTTPS 回落（检测源为本机）'
    else
        rc=$?
        if (( rc == 3 )); then
            public_result=unverified
            warn '未验证：NAT 公网地址 443 回访未建立 TCP 连接，不能据此判断外部可达性。'
            warn '请检查服务商 TCP 443 映射/安全组并从外部网络验证；此项不会被标记为通过。'
        else
            warn '失败：公网地址 443 HTTPS 回落（检测源为本机）'
            SELF_CHECK_FAILURES=$((SELF_CHECK_FAILURES + 1))
        fi
    fi
    self_report '证书 timer、最近续期 dry-run 与 deploy hook 记录' self_renew_ready
    self_report '实际 Xray 客户端 REALITY 握手和 HTTPS 代理请求（本机源）' self_client_probe "$SNI" 127.0.0.1
    if [[ -n "$external" ]]; then
        if [[ -x "$external" && -f "$external" && ! -L "$external" && "$(stat -c %u "$external")" == 0 \
            && "$(stat -c %a "$external")" =~ ^[57]00$ ]]; then
            if timeout 120 "$external" "$SNI" "$ip"; then
                external_result=passed; ok '通过：用户配置的外部网络验证程序'
            else external_result=failed; warn '失败：用户配置的外部网络验证程序'; SELF_CHECK_FAILURES=$((SELF_CHECK_FAILURES + 1)); fi
        else external_result=failed; warn '失败：外部验证程序需为 root:700 的普通可执行文件。'; SELF_CHECK_FAILURES=$((SELF_CHECK_FAILURES + 1)); fi
    else
        warn '未验证：真正外部网络的 HTTPS/VLESS 连接。请从其他网络访问并导入测试；可用 VLESS_EXTERNAL_CHECK 配置外部验证程序。'
    fi
    if (( SELF_CHECK_FAILURES )); then result=failed;
    elif [[ "$external_result" == passed ]]; then result=external_verified;
    elif [[ "$public_result" == unverified ]]; then result=pending;
    else result=local_verified; fi
    self_network_write "$ip" "$public_result" "$external_result" "$result" || { warn '失败：无法保存网络检查结果。'; return 1; }
    (( SELF_CHECK_FAILURES == 0 )) || return 1
    [[ "$result" != pending ]] || return 3
    return 0
}
change_self_domain() {
    local domain="${1:-}"
    if [[ -z "$domain" ]]; then
        [[ -t 0 ]] || fail '请指定新自有域名；不支持 auto。'
        self_prompt_domain || { say '已取消修改。'; return 0; }
        domain="$SELF_INPUT_DOMAIN"
    fi
    domain="${domain,,}"
    valid_host "$domain" || fail '新自有域名格式无效；自有域名模式不允许 auto。'
    [[ "$domain" != "$SNI" ]] || { ok '域名未改变。'; return 0; }
    self_dns_precheck "$domain" || fail '新域名预检未通过；原节点保持不变。'
    run_node_job vless-reality-self-change "即将申请新证书，成功后须重新导入链接。$NODE_JOB_NOTE" __self-domain "$domain" \
        || fail '域名修改失败；查看 journalctl -u vless-reality-self-change。'
    show_node
}
self_domain_apply() (
    need_root; self_operation_lock; load_metadata
    [[ "$NODE_MODE" == self && $# == 1 ]] || fail '仅自有域名模式支持同步域名修改。'
    self_cleanup_preflight || fail '管理文件已改变，无法安全修改。'
    local domain="${1,,}" old_sni="$SNI" backup committed=0 active=0 timer_active=0 record='' new_ip
    valid_host "$domain" || fail '域名无效。'
    self_dns_check "$domain" || fail '新域名 DNS 检查失败。'
    new_ip="$(public_ipv4)" || fail '无法确认当前公网 IPv4。'
    valid_ipv4 "$new_ip" || fail '公网 IPv4 格式无效。'
    SELF_METHOD="$(self_state method)"; SELF_EMAIL="$(self_state email)"
    backup="$(mktemp -d "$SELF_DIR/work/domain-backup.XXXXXX")"
    backup_state "$backup" || fail '无法备份节点。'
    cp -a "$SELF_SITE" "$backup/nginx-site.conf"
    cp -a "$SELF_DIR/state.json" "$SELF_DIR/files.sha256" "$backup/"
    [[ ! -f "$SELF_DIR/security-dns.json" ]] || cp -a "$SELF_DIR/security-dns.json" "$backup/"
    [[ ! -f "$SELF_DIR/renew-test.json" ]] || cp -a "$SELF_DIR/renew-test.json" "$backup/"
    [[ ! -f "$LINK_FILE" ]] || cp -a "$LINK_FILE" "$backup/link.txt"
    systemctl is-active --quiet xray && active=1
    systemctl is-active --quiet vless-reality-cert.timer && timer_active=1
    # trap 的恢复不能依赖 SSH 会话；本函数由独立 systemd 任务运行。
    trap 'rc=$?; trap - EXIT; if (( ! committed )); then
        if ! cp -a "$backup/nginx-site.conf" "$SELF_SITE" || ! cp -a "$backup/state.json" "$backup/files.sha256" "$SELF_DIR/"; then
            warn "域名文件回滚未完成，保留备份：$backup" >&2; exit 1
        fi
        for record in renew-test.json security-dns.json; do
            if [[ -f "$backup/$record" ]]; then
                if ! cp -a "$backup/$record" "$SELF_DIR/"; then warn "域名记录回滚失败，保留备份：$backup" >&2; exit 1; fi
            elif ! rm -f "$SELF_DIR/$record"; then warn "域名记录回滚失败，保留备份：$backup" >&2; exit 1; fi
        done
        SNI="$old_sni"
        if ! nginx -t || ! systemctl reload nginx || ! restore_state "$backup" "$active"; then
            warn "域名修改回滚未完成，备份保留：$backup" >&2; exit 1
        fi
        if [[ -f "$backup/link.txt" ]] && ! cp -a "$backup/link.txt" "$LINK_FILE"; then warn "链接回滚失败，保留备份：$backup" >&2; exit 1; fi
    fi
    if (( timer_active )) && ! systemctl start vless-reality-cert.timer; then warn "续期任务未恢复，保留备份：$backup" >&2; exit 1; fi
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
    SERVER_IP="$new_ip"
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
    if ! security_dns_baseline "$SNI"; then rm -f "$SELF_DIR/security-dns.json"; warn '新域名 DNS 基线未保存，请独立核对后手动确认。'; fi
    (show_node >/dev/null) || fail '新域名链接保存失败。'
    if (( active )); then self_client_probe "$domain" 127.0.0.1 || fail '新域名节点实际握手失败。'; fi
    # shellcheck disable=SC2034 # 由 EXIT trap 读取。
    committed=1
    ok '自有域名的证书、Nginx、Xray 和客户端链接已同步修改。'
)

# 可选回落限速：用当前二进制的 typed 配置确认字段被识别，不能只依赖 JSON 容忍未知字段。
fallback_capability() (
    local file="$1" binary="${2:-$XRAY_BIN}" output
    output="$(mktemp "$SELF_DIR/work/fallback-capability.XXXXXX")" || return 1
    trap 'rm -f "$output"' EXIT
    "$binary" convert pb -debug "$file" > "$output" 2>/dev/null || return 1
    python3 - "$file" "$output" <<'PY_CAP'
import json, re, sys
try:
    expected = json.load(open(sys.argv[1]))['inbounds'][0]['streamSettings']['realitySettings']
    raw = open(sys.argv[2]).read()
    # 某些版本在 JSON 前输出读取配置的日志；不把包含私钥的调试内容打印到终端。
    match = re.search(r'(?m)^\{', raw)
    if not match:
        raise ValueError()
    tree = json.JSONDecoder().raw_decode(raw[match.start():])[0]
    def objects(value):
        if isinstance(value, dict):
            yield value
            for child in value.values():
                yield from objects(child)
        elif isinstance(value, list):
            for child in value:
                yield from objects(child)
    keys = ('limitFallbackUpload', 'limitFallbackDownload')
    def same(obj):
        for key in keys:
            if key in expected:
                if key not in obj or any(int(obj[key].get(f, 0)) != int(expected[key][f])
                                         for f in ('afterBytes', 'bytesPerSec', 'burstBytesPerSec')):
                    return False
        return True
    if not any(any(k in obj for k in keys) and same(obj) for obj in objects(tree)):
        raise ValueError()
except Exception:
    sys.exit(1)
PY_CAP
)
fallback_limits_json() {
    python3 - <<'PY_LIMIT'
import json, secrets
# 每次显式开启时随机化，两个方向独立；不是全机/全用户总带宽限制。
def limit():
    rate = 524288 + secrets.randbelow(1572865)
    return dict(afterBytes=8388608 + secrets.randbelow(8388609), bytesPerSec=rate,
                burstBytesPerSec=rate + secrets.randbelow(rate + 1))
print(json.dumps(dict(upload=limit(), download=limit())))
PY_LIMIT
}
fallback_status() {
    jq -r '.inbounds[0].streamSettings.realitySettings | if
       ((.limitFallbackUpload.bytesPerSec // 0)>0 or (.limitFallbackDownload.bytesPerSec // 0)>0)
       then "回落限速配置：已开启（仅未认证回落连接，按每连接计）\n上传：\(.limitFallbackUpload)\n下载：\(.limitFallbackDownload)"
       else "回落限速配置：未开启（默认）" end' "$CONFIG"
}
fallback_apply() {
    need_root; self_operation_lock; load_metadata
    [[ "$NODE_MODE" == self && $# == 1 ]] || fail '回落限速仅用于自有域名模式。'
    local action="$1" backup was_active=0 limits probe
    case "$action" in on|off) ;; *) fail '用法：fallback-limit [status|on|off]' ;; esac
    if [[ "$action" == on ]]; then
        self_config_check || fail '当前自有域名配置不符合安全约束，未修改。'
    else
        self_config_policy "$CONFIG" "$SNI" || fail '当前配置违反安全约束，未修改。'
    fi
    if [[ "$action" == on ]] && jq -e '.inbounds[0].streamSettings.realitySettings |
        (.limitFallbackUpload.bytesPerSec // 0)>0 and (.limitFallbackDownload.bytesPerSec // 0)>0' "$CONFIG" >/dev/null; then fallback_status; return 0; fi
    if [[ "$action" == off ]] && ! jq -e '.inbounds[0].streamSettings.realitySettings | has("limitFallbackUpload") or has("limitFallbackDownload")' "$CONFIG" >/dev/null; then fallback_status; return 0; fi
    self_http_check "$SNI" 127.0.0.1 443 || fail '修改前 HTTPS 基线未通过。'
    self_client_probe "$SNI" 127.0.0.1 || fail '修改前合法节点基线未通过。'
    backup="$(mktemp -d "$CONFIG_DIR/.change-backup.XXXXXX")" || fail '无法备份节点。'
    backup_state "$backup" || fail '备份失败。'
    if systemctl is-active --quiet xray; then was_active=1; fi
    if [[ "$action" == on ]]; then
        limits="$(fallback_limits_json)" || fail '无法生成随机限速参数。'
        probe="$SELF_DIR/work/fallback-probe.json"
        if ! jq --argjson v "$limits" '.inbounds[0].streamSettings.realitySettings +=
            {limitFallbackUpload:$v.upload,limitFallbackDownload:$v.download}' "$CONFIG" > "$probe" \
            || ! fallback_capability "$probe"; then
            rm -f "$probe"; rm -rf "$backup"
            fail '当前 Xray 无法确认支持回落限速；未修改配置。'
        fi
        rm -f "$probe"
        if ! edit_config --argjson v "$limits" '.inbounds[0].streamSettings.realitySettings +=
            {limitFallbackUpload:$v.upload,limitFallbackDownload:$v.download}'; then
            rm -rf "$backup"; fail '未写入限速配置。'
        fi
    else
        edit_config 'del(.inbounds[0].streamSettings.realitySettings.limitFallbackUpload,
            .inbounds[0].streamSettings.realitySettings.limitFallbackDownload)' || { rm -rf "$backup"; fail '未关闭限速。'; }
    fi
    if config_ok && { (( was_active==0 )) || { systemctl restart xray && wait_service 10; }; } \
        && self_http_check "$SNI" 127.0.0.1 443 && self_client_probe "$SNI" 127.0.0.1; then
        rm -rf "$backup"; fallback_status; return 0
    fi
    restore_state "$backup" "$was_active" || fail "回滚失败，备份保留在 $backup。"
    rm -rf "$backup"
    fail '限速切换或切换后的 HTTPS/合法节点测试失败，已恢复原配置。'
}
fallback_command() {
    need_root; load_metadata
    [[ "$NODE_MODE" == self ]] || fail '此开关仅适用于自有域名模式。'
    [[ $# -le 1 ]] || fail '用法：fallback-limit [status|on|off]'
    local action="${1:-}"
    if [[ -z "$action" ]]; then
        fallback_status
        [[ -t 0 ]] || return 0
        read -r -p '回落限速 [on 开启 / off 关闭 / 回车不改]：' action || return 0
        [[ -n "$action" ]] || return 0
    fi
    case "$action" in status) fallback_status; return ;; on|off) ;; *) fail '用法：fallback-limit [status|on|off]' ;; esac
    if [[ "$action" == on ]]; then
        warn '回落限速可能产生可识别的流量特征；仅限制每条未认证连接，不能阻止多连接攻击。默认关闭。'
        warn '开启后使用随机阈值和速率；普通 HTTPS 网站也属于回落流量。'
        if [[ -t 0 ]]; then confirm '确认开启？[y/N]：' || return 0; fi
    fi
    run_node_job vless-reality-fallback "$NODE_JOB_NOTE" __fallback-apply "$action" \
        || fail '切换失败；查看 journalctl -u vless-reality-fallback。'
    fallback_status
}
# 将前一开发版本的自有域名站点升级到本版本安全模板，不更换 UUID、密钥或证书。
security_apply() (
    need_root; self_operation_lock; load_metadata
    [[ "$NODE_MODE" == self ]] || fail 'security-apply 仅用于自有域名模式。'
    if ! self_cleanup_preflight || ! self_config_check; then fail '资源归属或 REALITY 安全约束检查失败，未修改。'; fi
    systemctl is-active --quiet nginx || fail 'Nginx 当前未运行，请先恢复原网站再应用安全模板。'
    self_wait_tls "$SNI" || fail '原网站 TLS/证书基线未通过，未修改。'
    local backup committed=0 rc
    backup="$(mktemp -d "$SELF_DIR/work/security-backup.XXXXXX")" || exit 1
    if ! cp -a "$SELF_SITE" "$backup/site.conf" || ! cp -a "$SELF_DIR/files.sha256" "$backup/files.sha256"; then
        rm -rf "$backup"; fail '安全模板备份失败，未修改。'
    fi
    trap 'rc=$?; trap - EXIT
        if (( ! committed )); then
            if ! cp -a "$backup/site.conf" "$SELF_SITE" || ! cp -a "$backup/files.sha256" "$SELF_DIR/files.sha256" || ! self_nginx_apply; then
                warn "安全模板回滚失败，保留备份：$backup" >&2; exit 1
            fi
        fi
        rm -rf "$backup"; exit "$rc"' EXIT
    SELF_METHOD="$(self_state method)"
    if ! self_nginx_write "$SNI" || ! self_nginx_apply; then fail '安全站点配置应用失败。'; fi
    self_wait_security "$SNI" || fail '新安全规则的 HTTPS 检测失败。'
    if systemctl is-active --quiet xray; then self_client_probe "$SNI" 127.0.0.1 || fail '合法节点验证失败。'; fi
    if [[ ! -f "$SELF_DIR/security-dns.json" ]]; then security_dns_baseline "$SNI" || warn 'DNS 基线未验证，请独立核对后运行 security-check --accept-dns。'; fi
    # shellcheck disable=SC2034 # EXIT trap 读取提交状态。
    committed=1
    ok '自有域名 HTTPS 安全模板已更新；节点认证参数保持原值。'
)
self_wait_security() {
    local attempt
    for attempt in {1..10}; do
        if self_wait_tls "$1" && self_reject_check "$1" && self_authority_check "$1"; then return 0; fi
        sleep 0.3
    done
    return 1
}
self_authority_check() {
    local domain="$1" port="${2:-8443}" address="${3:-127.0.0.1}" protocol result
    for protocol in --http1.1 --http2; do
        result="$(curl --noproxy '*' -sS "$protocol" --connect-timeout 5 --max-time 10 \
            --resolve "$domain:$port:$address" -H 'Host: invalid.example' -o /dev/null -w '%{http_version} %{http_code}' "https://$domain:$port/")" || return 1
        if [[ "$protocol" == --http2 ]]; then [[ "$result" == '2 421' ]] || return 1;
        else [[ "$result" == '1.1 421' ]] || return 1; fi
    done
}
self_key_pair_check() {
    python3 - "$CONFIG" "$PUBLIC_KEY" <<'PY_KEY'
import base64, json, sys
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives import serialization
try:
    key = json.load(open(sys.argv[1]))['inbounds'][0]['streamSettings']['realitySettings']['privateKey']
    value = base64.urlsafe_b64decode(key + '=')
    pub = X25519PrivateKey.from_private_bytes(value).public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    if base64.urlsafe_b64encode(pub).decode().rstrip('=') != sys.argv[2]:
        raise ValueError()
except Exception:
    sys.exit(1)
PY_KEY
}
security_permissions() {
    local path mode group
    group="$(id -g xray)" || return 1
    for path in "$CONFIG" "$MARKER"; do
        [[ -f "$path" && ! -L "$path" && "$(stat -c %u "$path")" == 0 && "$(stat -c %g "$path")" == "$group" && "$(stat -c %a "$path")" == 640 ]] || return 1
    done
    [[ -d "$CONFIG_DIR" && ! -L "$CONFIG_DIR" && "$(stat -c %u "$CONFIG_DIR")" == 0 && "$(stat -c %g "$CONFIG_DIR")" == "$group" && "$(stat -c %a "$CONFIG_DIR")" == 750 ]] || return 1
    path="$LINK_FILE"; mode="$(stat -c %a "$path" 2>/dev/null)" || return 1
    [[ -f "$path" && ! -L "$path" && "$mode" == 600 && "$(stat -c %u "$path")" == 0 ]]
}
security_link_check() {
    local private link uuid sid address network path
    address="$(client_address)" || return 1
    private="$(jq -er '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG")" || return 1
    link="$(< "$LINK_FILE")"; uuid="$(config_uuid)" || return 1
    sid="$(jq -er '.inbounds[0].streamSettings.realitySettings.shortIds | if length==1 then .[0] else empty end' "$CONFIG")" || return 1
    [[ "$sid" == "$SHORT_ID" && "$link" != *"$private"* && "$link" == "vless://$uuid@$address:$PORT?"* && "$link" == *"&sni=$SNI&"* \
        && "$link" == *"&pbk=$PUBLIC_KEY&"* && "$link" == *"&sid=$SHORT_ID&"* ]] || return 1
    network="$(config_transport)" || return 1
    if [[ "$network" == xhttp ]]; then
        path="$(config_xhttp_path)" || return 1
        [[ "$link" == *"&type=xhttp&path=%2F${path#/}&mode=auto"* && "$link" != *'&flow='* ]]
    else
        [[ "$link" == *'&type=tcp&headerType=none'* && "$link" == *'&flow=xtls-rprx-vision&'* ]]
    fi
}
security_xray_listener() {
    local pid
    systemctl is-active --quiet xray || return 1
    pid="$(systemctl show xray -p MainPID --value)" || return 1
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    ss -H -ltnp 'sport = :443' | grep -F "pid=$pid," >/dev/null
}
security_service_user() {
    local user pid uid
    user="$(systemctl show xray -p User --value)" || return 1
    [[ "$user" == xray ]] || return 1
    pid="$(systemctl show xray -p MainPID --value)" || return 1
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    uid="$(stat -c %u "/proc/$pid")" || return 1
    [[ "$uid" != 0 && "$uid" == "$(id -u xray)" ]]
}
security_dns_effective() {
    local resolver="$1" domain="$2" type="$3" output records
    while [[ -n "$domain" ]]; do
        output="$(self_dns_query "$resolver" "$domain" "$type")" || return 1
        [[ "$output" == *'status: NOERROR'* ]] || return 1
        records="$(awk -v type="$type" '$4==type {for(i=5;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}' <<< "$output" | sort -u)"
        if [[ -n "$records" || ( "$type" != NS && "$type" != CAA ) ]]; then printf '%s' "$records"; return 0; fi
        [[ "$domain" == *.* ]] || break
        domain="${domain#*.}"
    done
    [[ "$type" != NS ]]
}
security_dns_snapshot() {
    local domain="$1" resolver type value first='' current
    for resolver in 1.1.1.1 8.8.8.8; do
        current='{}'
        for type in A AAAA CNAME NS CAA; do
            value="$(security_dns_effective "$resolver" "$domain" "$type")" || return 1
            current="$(jq -c --arg type "$type" --arg value "$value" '.[$type]=$value' <<< "$current")" || return 1
        done
        current="$(jq -cS --arg domain "$domain" '.+{domain:$domain}' <<< "$current")" || return 1
        if [[ -n "$first" && "$first" != "$current" ]]; then return 1; fi
        first="$current"
    done
    printf '%s\n' "$first"
}
security_dns_baseline() {
    local domain="$1" snapshot tmp
    self_dns_check "$domain" || return 1
    snapshot="$(security_dns_snapshot "$domain")" || return 1
    tmp="$(mktemp "$SELF_DIR/.renew.XXXXXX")" || return 1
    printf '%s\n' "$snapshot" > "$tmp" && mv "$tmp" "$SELF_DIR/security-dns.json"
}
security_dns_changed() {
    local domain="$1" old current
    [[ -f "$SELF_DIR/security-dns.json" && ! -L "$SELF_DIR/security-dns.json" ]] || { warn '尚无 DNS 基线，请确认域名账户安全后运行 security-check --accept-dns。'; return 3; }
    old="$(jq -ecS --arg domain "$domain" 'select(.domain==$domain)' "$SELF_DIR/security-dns.json")" || return 3
    current="$(security_dns_snapshot "$domain")" || return 3
    if [[ "$old" != "$current" ]]; then warn 'A/AAAA/CNAME/权威 NS/有效 CAA 与已确认基线不同；无法判断变更意图，请核对注册商/DNS 账户。'; return 2; fi
}

security_caa_check() {
    local domain="$1" resolver zone output records summaries=() result
    for resolver in 1.1.1.1 8.8.8.8; do
        zone="$domain"; records=''
        while [[ -n "$zone" ]]; do
            output="$(self_dns_query "$resolver" "$zone" CAA)" || return 3
            [[ "$output" == *'status: NOERROR'* ]] || return 3
            records="$(awk '$4=="CAA" {for(i=5;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}' <<< "$output" | sort)"
            [[ -z "$records" ]] || break
            [[ "$zone" == *.* ]] || break
            zone="${zone#*.}"
        done
        summaries+=("$records")
    done
    [[ "${summaries[0]}" == "${summaries[1]}" ]] || { warn 'CAA 两个解析器结果不一致。'; return 3; }
    result="$(printf '%s' "${summaries[0]}" | python3 -c '
import shlex,sys
rows=[shlex.split(line) for line in sys.stdin if line.strip()]
try:
    issues=[r[2] for r in rows if r[1].lower()=="issue"]
    unknown=any(int(r[0]) & 128 and r[1].lower() not in ("issue","issuewild","iodef") for r in rows)
    le=[x for x in issues if x.split(";",1)[0].strip().lower()=="letsencrypt.org"]
    print("unknown" if unknown else "unrestricted" if not issues else "blocked" if not le else "constraints" if any(";" in x for x in le) else "ok")
except Exception: print("unknown")')" || return 3
    case "$result" in
        ok) return 0 ;;
        blocked) warn 'CAA issue 不允许 LE，后续续期可能失败；未修改 DNS。'; return 1 ;;
        constraints) warn 'CAA 允许 LE，但包含账户/验证方式等约束，请用 cert renew-test 验证。'; return 2 ;;
        unrestricted) warn '未设置有效的非通配符 CAA issue 限制；可考虑仅允许 letsencrypt.org。'; return 2 ;;
        *) warn '无法确认 CAA 的 critical 标志或内容；需人工核对。'; return 3 ;;
    esac
}
security_net_bytes() {
    awk -F: 'NR>2 {name=$1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", name); if(name=="lo") next;
        data=$2; sub(/^[[:space:]]+/, "", data); split(data,c,/[[:space:]]+/); s+=c[1]+c[9]} END{printf "%.0f",s}' /proc/net/dev
}
security_bandwidth() {
    local count first second threshold="${VLESS_WARN_CONNECTIONS:-1000}" rate_threshold="${VLESS_WARN_MIBPS:-100}" rate
    [[ "$threshold" =~ ^[1-9][0-9]{0,6}$ && "$rate_threshold" =~ ^[1-9][0-9]{0,6}$ ]] || return 1
    count="$(ss -H -tn state established '( sport = :443 )' | wc -l)" || return 1
    first="$(security_net_bytes)" || return 1
    sleep 1
    second="$(security_net_bytes)" || return 1
    (( second >= first )) || { warn '接口计数重置，带宽样本未验证。'; return 1; }
    rate=$(( (second-first)/1048576 ))
    say "TCP 443 已建立连接：$count；全机非回环接口 1 秒样本约 ${rate} MiB/s（含其他进程和可能重复统计的虚拟接口）。"
    if (( count > threshold || rate > rate_threshold )); then warn '警告：样本较高，请结合业务核对；这不是恶意访问证据，不自动封禁。'; fi
}
security_item() {
    local label="$1" result=0; shift
    "$@" || result=$?
    case "$result" in
        0) ok "通过：$label" ;;
        2) warn "警告：$label" ;;
        3) warn "未验证：$label" ;;
        *) warn "失败：$label"; SELF_CHECK_FAILURES=$((SELF_CHECK_FAILURES+1)) ;;
    esac
}
security_unauthorized() {
    local result=0
    self_client_probe "$SNI" 127.0.0.1 443 "$1" || result=$?
    (( result != 2 )) || return 3
    [[ "$result" == 1 ]]
}
security_check() {
    need_root
    [[ $# -le 1 ]] || fail '用法：security-check [--accept-dns]'
    self_operation_lock
    load_metadata
    [[ "$NODE_MODE" == self ]] || fail 'security-check 用于自有域名模式；普通模式仍可使用 status。'
    if [[ -n "${1:-}" ]]; then
        [[ "$1" == --accept-dns ]] || fail '用法：security-check [--accept-dns]'
        warn '此操作只确认当前 DNS 基线，不会修改 DNS；应先独立确认注册商和 DNS 账户安全。'
        if [[ -t 0 ]]; then confirm '确认当前 DNS 记录是预期设置？[y/N]：' || return 0; fi
        security_dns_baseline "$SNI" || fail '无法保存直连且一致的 DNS 基线。'
        ok 'DNS 安全基线已确认。'; return 0
    fi
    local SELF_CHECK_FAILURES=0 baseline=0 tmp
    self_report 'Xray TCP 443 正常运行且监听归属正确' security_xray_listener
    self_report 'Nginx 服务运行' systemctl is-active --quiet nginx
    self_report 'Xray 实际以非 root xray 用户运行' security_service_user
    self_report 'Nginx 8443 仅监听本机回环' self_listener_check
    self_report 'REALITY target/SNI/传输/UUID/非空 Short ID 安全约束' self_config_check
    self_report '配置、目录、安装记录和链接权限' security_permissions
    self_report 'REALITY 私钥与客户端公钥配对' self_key_pair_check
    self_report '客户端链接地址符合当前模式且不含私钥' security_link_check
    self_report 'DNS 直连当前 VPS，无 CDN/CNAME/AAAA' self_dns_check "$SNI"
    if [[ "$(public_ipv4 || true)" != "$SERVER_IP" ]]; then warn '警告：当前出口 IPv4 与安装记录的 IP 缓存不同，请确认 VPS IP/DNS 变更是否符合预期。'; fi
    security_item 'DNS 与已确认基线一致' security_dns_changed "$SNI"
    security_item 'CAA 证书颁发机构约束' security_caa_check "$SNI"
    self_report 'TLS 1.3 / X25519 / H2 和有效证书' self_tls_check "$SNI" 127.0.0.1:8443
    self_report 'Nginx 已加载当前证书' self_loaded_cert_matches "$SNI"
    self_report '网站 HTTP/2 200，无跳转' self_http_check "$SNI" 127.0.0.1 443
    self_report '未知和无 SNI 被拒绝' self_reject_check "$SNI"
    self_report 'SNI 与 Host/:authority 不匹配返回 421' self_authority_check "$SNI"
    self_report '证书续期 timer、dry-run 和 hook' self_renew_ready
    self_report '证书剩余有效期至少 14 天' openssl x509 -in "$SELF_DIR/acme/live/$SNI/cert.pem" -checkend 1209600 -noout
    if self_client_probe "$SNI" 127.0.0.1; then baseline=1; ok '通过：合法 REALITY 实际代理请求（本机源）';
    else warn '失败：合法节点基线未通过'; SELF_CHECK_FAILURES=$((SELF_CHECK_FAILURES+1)); fi
    if (( baseline )); then
        security_item '错误 UUID 未获得代理访问（本机负向测试）' security_unauthorized bad-uuid
        security_item '错误 REALITY Short ID 未获得代理访问（本机负向测试）' security_unauthorized bad-reality
        security_item '错误 REALITY 公钥未获得代理访问（本机负向测试）' security_unauthorized bad-public-key
    else warn '未验证：错误认证负向测试（合法基线失败，不能把网络失败算作安全通过）'; fi
    fallback_status
    self_network_status
    security_bandwidth || warn '未验证：无法读取连接/带宽样本。'
    warn '未验证：注册商 MFA/Registrar Lock/自动续费、DNSSEC、DNS 修改提醒和 Token 最小权限须在账户面板确认。'
    warn '未验证：真正外部网络的 8443 可达性和节点连接；本命令的连接检测源为 VPS 本机。'
    warn '公开 SNI 可被任何人填写；普通 HTTPS 访问不等于恶意行为，本检查不自动封禁。'
    tmp="$(mktemp "$SELF_DIR/.renew.XXXXXX")" || return 1
    jq -n --arg domain "$SNI" --arg time "$(date -u +%FT%TZ)" --argjson failures "$SELF_CHECK_FAILURES" \
        '{domain:$domain,time:$time,failed_checks:$failures,external:"unverified"}' > "$tmp" \
        && mv "$tmp" "$SELF_DIR/security-last.json" || return 1
    (( SELF_CHECK_FAILURES==0 ))
}

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
  cert [status|renew-test|token] 证书状态、续期测试或安全更换 Cloudflare Token
  website                      查看本地网站状态
  website-random               更换自有域名随机网页，保留节点信息且不重启服务
  security-check               检查自有域名认证、权限、DNS、TLS 和回落安全
  security-apply               更新自有域名 Nginx 安全配置，不更换网页
  fallback-limit [status|on|off] 可选的回落限速（默认关闭）
  show                         显示 vless:// 导入链接
  addr [ip|domain [连接域名]]   切换客户端连接地址（不修改 REALITY SNI）
  status                       查看服务、配置、端口和伪装站点状态
  transport [status|tcp|xhttp]  查看或切换 TCP + Vision / XHTTP 传输
  transport recover             恢复中断的传输切换
  port [新端口]                修改端口
  sni [新域名|auto]            修改或自动优选 REALITY 伪装域名
  sni-best                     查看当前测速延迟最低的域名，不修改节点
  tfo [on|off]                 查看或切换 TCP Fast Open
  vlessenc [on [native|xorpub|random]|off]  查看或切换 VLESS Encryption 模式
  uuid                         重新生成 UUID
  rotate-keys                  轮换 REALITY 密钥和 Short ID
  rename [新名称]              修改节点名称
  refresh-ip                   刷新公网 IPv4 缓存和链接，保持 IP/域名选择
  start|stop|restart           管理服务
  log [-f|行数]                查看日志
  update                       升级 Xray-core
  uninstall                    卸载并清理
EOF
}

menu_status() {
    if transport_pending; then transport_pending_message; return 0; fi
    if [[ ! -f "$MARKER" ]]; then say " 当前状态：${RED}● 未安装${RESET}"; return 0; fi
    if [[ ! -f "$CONFIG" ]]; then
        warn ' 当前状态：● 节点文件不完整；可选择 26 重试卸载'
        return 0
    fi
    # 安装记录损坏时 load_metadata 会退出；先在子 shell 中校验，菜单仍可进入卸载等操作。
    if ! (load_metadata); then
        warn ' 当前状态：● 安装记录无效（原因见上方）；可选择 26 卸载后重新安装'
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
    say " 当前节点：${NODE_NAME}（$(client_address):${PORT}，SNI ${SNI}）"
    client_address_status
    [[ "$NODE_MODE" != self ]] || self_network_status brief
}

show_menu() {
    if [[ -t 1 ]]; then clear -x 2>/dev/null || true; fi
    say '=================================='
    say " VLESS + REALITY + Vision ${RED}[v${SCRIPT_VERSION}]${RESET}"
    say '=================================='
    say '【安装】'
    say '  1. 安装普通 REALITY（第三方 SNI）'
    say '  2. 安装自有域名 REALITY（偷自己）'
    say '----------------------------------'
    say '【节点管理】'
    say '  3. 查看导入链接'
    say '  4. 查看运行状态'
    say '  5. 启动服务'
    say '  6. 停止服务'
    say '  7. 重启服务'
    say '  8. 重新生成 UUID'
    say '  9. 轮换 REALITY 密钥'
    say ' 10. 修改端口'
    say ' 11. 修改节点名称'
    say ' 12. 服务器地址管理（IP / 域名 / 刷新 IP）'
    say ' 13. 升级 Xray-core'
    say '----------------------------------'
    say '【高级功能】'
    say ' 14. 修改伪装域名（支持自动优选）'
    say ' 15. 查看当前测速延迟最低的域名'
    say ' 16. 开关 TCP Fast Open'
    say ' 17. 开关 VLESS Encryption / 修改模式'
    say '----------------------------------'
    say '【自有域名管理（仅自有域名模式）】'
    say ' 18. 查看自有域名网站状态'
    say ' 19. 查看 SSL 证书'
    say ' 20. 测试证书自动续期'
    say ' 21. 一键检查自有域名配置'
    say ' 22. 自有域名安全检查'
    say ' 23. 可选回落限速'
    say ' 24. 更新 Nginx 安全配置（原安全模板）'
    say '----------------------------------'
    say '【其他】'
    say ' 25. 查看运行日志'
    say ' 26. 卸载节点'
    say ' 27. 更换自有域名随机网页（节点信息不变）'
    say ' 28. 更换 Cloudflare API Token（验证证书续期）'
    say ' 29. 切换节点传输（TCP + Vision / XHTTP）'
    say ' 00. 退出'
    say '=================================='
    menu_status
    say
}
menu_action() {
    case "$1" in
        1) install_node ;; 2) install_self ;;
        3) show_node ;; 4) status_node ;;
        5) start_node ;; 6) stop_node ;; 7) restart_node ;;
        8) warn '操作后旧链接立即失效。'; uuid_node ;;
        9) warn '操作后旧链接立即失效。'; rotate_keys_node ;;
        10) port_node ;; 11) rename_node ;; 12) address_node ;; 13) update_node ;;
        14) sni_node ;; 15) show_fastest_sni ;; 16) tfo_node ;; 17) vlessenc_node ;;
        18) website_status ;; 19) cert_command status ;; 20) cert_command renew-test ;;
        21) check_self ;; 22) security_check ;; 23) fallback_command ;; 24) security_apply ;;
        25) log_node ;; 26) uninstall_node ;; 27) website_random ;; 28) cert_command token ;;
        29) transport_command ;; *) return 2 ;;
    esac
}
# 命令行历史数字参数保留原语义，避免旧自动化把卸载误解为安装等操作。
# 新交互菜单仅由 menu_action 分派；非交互建议使用 install-self/show/uninstall 等命名命令。
legacy_numeric_action() {
    case "$1" in
        1) install_node ;; 2) uninstall_node ;; 3) update_node ;;
        4) start_node ;; 5) stop_node ;; 6) restart_node ;;
        7) port_node ;; 8) sni_node ;;
        9) warn '操作后旧链接立即失效。'; uuid_node ;;
        10) warn '操作后旧链接立即失效。'; rotate_keys_node ;;
        11) rename_node ;; 12) refresh_ip ;; 13) show_node ;;
        14) status_node ;; 15) log_node ;; 16) show_fastest_sni ;;
        17) tfo_node ;; 19) vlessenc_node ;;
        20) install_self ;; 21) website_status ;; 22) cert_command status ;;
        23) cert_command renew-test ;; 24) check_self ;; 25) security_check ;; 26) fallback_command ;; 27) security_apply ;; *) return 2 ;;
    esac
}
interactive_menu() {
    if [[ ! -t 0 ]]; then print_help; return 0; fi
    need_root
    if [[ -f "$MARKER" ]]; then ensure_shortcut quiet || true; fi
    local choice rc
    while true; do
        show_menu
        read -r -p '请输入数字 [1-29，00 退出]：' choice || { say; return 0; }
        case "$choice" in 00|q|Q) return 0 ;; [1-9]|[12][0-9]) ;; *) warn '请输入菜单中的数字。'; sleep 1; continue ;; esac
        say
        set +e
        ( set -e; menu_action "$choice" )
        rc=$?
        set -e
        [[ "$choice" == 26 && ! -f "$MANAGER" ]] && return 0
        (( rc == 0 )) || say
        say
        read -r -p '* 按回车返回主菜单 *' || return 0
    done
}

main() {
    if [[ $- == *x* ]] && { [[ "${1:-}" == install-self ]] || { [[ -f "$MARKER" ]] && [[ "$(sed -n '8p' "$MARKER")" == self ]]; }; }; then
        fail '自有域名操作包含私密配置，禁止使用 bash -x；请使用状态命令和受保护日志排查。'
    fi
    case "${1:-}" in
        '') interactive_menu ;;
        help|-h|--help) print_help ;;
        install) shift; install_node "$@" ;;
        install-self) shift; install_self "$@" ;;
        check-self) check_self ;;
        security-check) shift; security_check "$@" ;;
        security-apply) security_apply ;;
        fallback-limit) shift; fallback_command "$@" ;;
        __fallback-apply) shift; fallback_apply "$@" ;;
        website) website_status ;;
        website-random) shift; website_random "$@" ;;
        cert) shift; cert_command "$@" ;;
        __self-domain) shift; self_domain_apply "$@" ;;
        __cert-renew) self_cert_renew ;;
        __cert-alert) self_cert_alert ;;
        show) show_node ;;
        addr) shift; address_node "$@" ;;
        status) status_node ;;
        transport) shift; transport_command "$@" ;;
        __transport-apply) shift; transport_apply "$@" ;;
        __transport-recover) transport_recover ;;
        port) shift; port_node "$@" ;;
        __port-apply) shift; change_port "$@" ;;
        sni) shift; sni_node "$@" ;;
        __sni-apply) shift; change_sni "$@" ;;
        sni-best) show_fastest_sni ;;
        tfo) shift; tfo_node "$@" ;;
        __tfo-apply) shift; tfo_apply "$@" ;;
        vlessenc) shift; vlessenc_node "$@" ;;
        __vlessenc-apply) shift; vlessenc_apply "$@" ;;
        uuid) uuid_node ;;
        __uuid-apply) change_uuid ;;
        rotate-keys) rotate_keys_node ;;
        __keys-apply) rotate_keys ;;
        rename) shift; rename_node "$@" ;;
        refresh-ip) refresh_ip ;;
        start) start_node ;;
        stop) stop_node ;;
        restart) restart_node ;;
        log|logs) shift; log_node "$@" ;;
        update) update_node ;;
        __update-apply) update_xray ;;
        uninstall) uninstall_node ;;
        [1-9]|1[0-7]|19|2[0-7])
            need_root
            warn '数字命令参数沿用旧编号；交互菜单已重新编号，建议使用 install-self/show/uninstall 等命名命令。' >&2
            legacy_numeric_action "$1" ;;
        *) print_help; exit 2 ;;
    esac
}

main "$@"
