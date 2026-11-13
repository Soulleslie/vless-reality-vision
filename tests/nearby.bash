#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
need_root() { :; }
ensure_dependencies() { :; }
public_ipv4() { printf '45.94.40.68'; }
getent() {
    if [[ "$1" == ahostsv6 ]]; then
        [[ "$2" == v6.example.com ]] && printf '2001:db8::1 STREAM v6.example.com\n'
        return 0
    fi
    case "$2" in
        outside.example.com) printf '1.1.1.1 STREAM outside.example.com\n' ;;
        *) printf '45.94.40.70 STREAM %s\n' "$2" ;;
    esac
}
timeout() { shift; "$@"; }
openssl() {
    printf 'Protocol version: TLSv1.3\nVerification: OK\nVerify return code: 0 (ok)\n'
    [[ "$*" == *bad-h2.example.com* ]] || printf 'ALPN protocol: h2\n'
}
curl() {
    case "${@: -1}" in
        *cf.example.com/*) printf 'HTTP/2 200\ncf-ray: test\n\nFINAL_STATUS:200\n' ;;
        *redirect.example.com/*) printf 'HTTP/2 302\nlocation: https://other.example.com/\n\nFINAL_STATUS:302\n' ;;
        *) printf 'HTTP/2 200\nserver: nginx\n\nFINAL_STATUS:200\n' ;;
    esac
}

nearby_target_ok good.example.com 45.94.40.68
for invalid in outside.example.com v6.example.com cf.example.com redirect.example.com \
    bad-h2.example.com visualstudio.microsoft.com; do
    if nearby_target_ok "$invalid" 45.94.40.68; then
        printf '不合格域名被接受：%s\n' "$invalid" >&2
        exit 1
    fi
done

cat > "$TEST_DIR/domains.txt" <<'EOF'
# bgp.tools Forward DNS 候选，每行一个域名
good.example.com
good.example.com
outside.example.com
cf.example.com
redirect.example.com
visualstudio.microsoft.com
EOF
SNI=''
select_nearby_sni "$TEST_DIR/domains.txt" >/dev/null
[[ "$SNI" == good.example.com && ${#SNI_CANDIDATES[@]} -eq 0 ]]
SNI=old.example.com
show_nearby_sni "$TEST_DIR/domains.txt" > "$TEST_DIR/output.txt"
[[ "$(< "$TEST_DIR/output.txt")" == *'此操作只显示结果，不修改节点配置'* ]]
[[ "$SNI" == old.example.com ]]
printf '同网段候选验证与优选通过\n'
