#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
need_root() { :; }
ensure_dependencies() { :; }
timeout() { shift; "$@"; }
openssl() {
    [[ "$*" == *'-tls1_3'* && "$*" == *'-groups X25519'* && "$*" == *'-alpn h2'* \
        && "$*" == *'-verify_hostname'* ]] || return 1
    [[ "$*" == *bad-tls.example.com* ]] || printf 'Protocol version: TLSv1.3\n'
    [[ "$*" == *bad-h2.example.com* ]] || printf 'ALPN protocol: h2\n'
    [[ "$*" == *bad-cert.example.com* ]] || printf 'Verification: OK\n'
}
curl() {
    local url="${@: -1}"
    printf '%s\n' "$url" >> "$TEST_DIR/requests"
    case "$url" in
        https://redirect.example.com/*)
            printf 'HTTP/2 301\nlocation: https://final.example.com/\n\nFINAL_STATUS:301\n' ;;
        https://same.example.com/)
            printf 'HTTP/2 302\nlocation: /new\n\nFINAL_STATUS:302\n' ;;
        https://same.example.com/new)
            printf 'HTTP/2 200\nserver: nginx\n\nFINAL_STATUS:200\n' ;;
        https://cdn.example.com/*)
            printf 'HTTP/2 200\ncf-ray: example\n\nFINAL_STATUS:200\n' ;;
        *) printf 'HTTP/2 200\nserver: nginx\n\nFINAL_STATUS:200\n' ;;
    esac
}
probe_target_latency() { printf '25'; }

output="$(show_sni_check good.example.com)"
[[ "$output" == *'必需条件通过'* && "$output" == *'平均 25 ms'* \
    && "$output" == *'节点配置未修改'* ]]
output="$(show_sni_check same.example.com)"
[[ "$output" == *'必需条件通过'* ]]
[[ "$(< "$TEST_DIR/requests")" == *'https://same.example.com/new'* ]]
output="$(show_sni_check cdn.example.com)"
[[ "$output" == *'可能使用 CDN'* ]]
for invalid in bad-tls.example.com bad-h2.example.com bad-cert.example.com; do
    if show_sni_check "$invalid" >/dev/null 2>&1; then
        printf '不合格域名被接受：%s\n' "$invalid" >&2
        exit 1
    fi
done
if show_sni_check redirect.example.com > "$TEST_DIR/redirect.out" 2>&1; then
    printf '跨域跳转应被拒绝\n' >&2
    exit 1
fi
[[ "$(< "$TEST_DIR/redirect.out")" == *'请改用该目标域名重新检查'* ]]
if rg -q 'https://final.example.com/' "$TEST_DIR/requests"; then
    printf '检查时不应请求跳转目标站点\n' >&2
    exit 1
fi
printf '手动域名完整检查通过\n'
