#!/usr/bin/env bash
# 仅用固定延迟替身测调度；不访问公网、不安装软件，不把此耗时冒充整机安装耗时。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_file="$ROOT/install.sh"
if [[ "${1:-}" == --benchmark ]]; then source_file="${2:?请提供对照脚本路径}"; fi
# shellcheck source=/dev/null
source <(sed '$d' "$source_file")
TEST_DIR="$(mktemp -d)"; trap 'rm -rf -- "$TEST_DIR"' EXIT
counter() (
    local kind="$1" delta="$2" active=0 peak=0 calls=0 counter_fd
    exec {counter_fd}> "$TEST_DIR/$kind.lock"; flock -x "$counter_fd"
    if [[ -f "$TEST_DIR/$kind.stats" ]]; then read -r active peak calls < "$TEST_DIR/$kind.stats"; fi
    (( active += delta )) || true
    if (( delta > 0 )); then (( calls += 1 )); fi
    if (( active > peak )); then peak="$active"; fi
    printf '%s %s %s\n' "$active" "$peak" "$calls" > "$TEST_DIR/$kind.stats"
)
public_ipv4() { printf '203.0.113.1'; }
self_dns_query() {
    counter dns 1
    sleep 0.15
    printf ';; status: NOERROR\n'
    if [[ "$3" == A ]]; then printf '%s 60 IN A 203.0.113.1\n' "$2"; fi
    printf '%s %s\n' "$1" "$3" >> "$TEST_DIR/dns.calls"
    counter dns -1
}
start="$(date +%s%3N)"; self_dns_check node.example.test; end="$(date +%s%3N)"
dns_ms=$((end-start))
read -r active peak calls < "$TEST_DIR/dns.stats"
[[ "$active" == 0 && "$calls" == 4 && "$peak" -le 2 ]]
[[ "$(sort "$TEST_DIR/dns.calls")" == $'1.1.1.1 A\n1.1.1.1 AAAA\n8.8.8.8 A\n8.8.8.8 AAAA' ]]
if declare -F self_dns_resolver_check >/dev/null; then [[ "$peak" == 2 ]]; fi
printf 'v%s DNS: %s ms，4 项查询，峰值并行 %s\n' "$SCRIPT_VERSION" "$dns_ms" "$peak"
if declare -F self_dns_resolver_check >/dev/null; then
    (
        # 工作者提前退出，即使退出码为 0，也不能把未完整执行的检查标为通过。
        self_dns_resolver_check() { if [[ "$3" == 8.8.8.8 ]]; then exit "$worker_exit"; fi; return 0; }
        for worker_exit in 0 9; do
            if output="$(self_dns_check node.example.test 2>&1)"; then exit 1; fi
            [[ "$output" == *'8.8.8.8'*'未完整执行'* ]]
        done
    )
fi

# 48 个候选，各批的首项较慢；所有有效候选仍须复测，失败候选不复测。
SNI_CANDIDATES=()
for ((index=0; index<48; index++)); do printf -v host 's%02d.example.test' "$index"; SNI_CANDIDATES+=("$host"); done
probe_target_latency() {
    counter sni 1
    case "$1" in s00.*|s16.*|s32.*) sleep 0.4 ;; *) sleep 0.01 ;; esac
    printf '%s\n' "$1" >> "$TEST_DIR/sni.calls"
    counter sni -1
    case "$1" in s47.*) return 1 ;; s01.*) printf 1 ;; s00.*|s16.*|s32.*) printf 400 ;; *) printf 10 ;; esac
}
start="$(date +%s%3N)"; select_fastest_sni > "$TEST_DIR/sni.log"; end="$(date +%s%3N)"
sni_ms=$((end-start))
read -r active peak calls < "$TEST_DIR/sni.stats"
[[ "$active" == 0 && "$peak" -le 16 && "$calls" == 95 && "$SNI" == s01.example.test ]]
[[ "$(sort "$TEST_DIR/sni.calls" | uniq -c | awk '$2=="s47.example.test" {print $1}')" == 1 ]]
[[ "$(sort "$TEST_DIR/sni.calls" | uniq -c | awk '$2!="s47.example.test" && $1!=2 {print}')" == '' ]]
printf 'v%s SNI: %s ms，48 项初筛 + 47 项复测，峰值并行 %s\n' "$SCRIPT_VERSION" "$sni_ms" "$peak"
if declare -F sni_wait_any_supported >/dev/null; then
    (
        # 模拟旧 Bash：未满 16 个时继续补任务，达到上限才沿用原批次等待。
        sni_wait_any_supported() { return 1; }
        legacy_pids=()
        for index in 1 2; do sleep 0.05 & legacy_pids+=("$!"); done
        sni_wait_slot legacy_pids
        [[ "${#legacy_pids[@]}" == 2 ]]
        for pid in "${legacy_pids[@]}"; do wait "$pid"; done
        legacy_pids=()
        for index in {1..16}; do sleep 0.05 & legacy_pids+=("$!"); done
        sni_wait_slot legacy_pids
        [[ "${#legacy_pids[@]}" == 0 ]]
    )
fi

# 新版只在当前执行链复用成功刷新的 apt 索引，失败不缓存，下一次运行须重新刷新。
if declare -F apt_update_once >/dev/null; then
    apt_fail=0
    apt-get() { [[ "$1" == update ]]; printf 'update\n' >> "$TEST_DIR/apt.calls"; [[ "$apt_fail" == 0 ]]; }
    apt_update_once; apt_update_once; (apt_update_once)
    [[ "$(wc -l < "$TEST_DIR/apt.calls")" == 1 ]]
    VLESS_APT_INDEX_READY=0; apt_fail=1
    if apt_update_once; then exit 1; fi
    [[ "$VLESS_APT_INDEX_READY" == 0 ]]
    apt_fail=0; apt_update_once
    [[ "$(wc -l < "$TEST_DIR/apt.calls")" == 3 ]]
    (
        # shellcheck source=/dev/null
        source <(sed '$d' "$source_file")
        apt_update_once
    )
    [[ "$(wc -l < "$TEST_DIR/apt.calls")" == 4 ]]
    printf 'apt 索引复用、失败重试与新执行链刷新通过\n'
fi
