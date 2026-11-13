#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source <(sed '$d' "$ROOT/install.sh")

[[ ${#SNI_CANDIDATES[@]} -eq 0 ]]
SNI_CANDIDATES=(www.amazon.com www.samsung.com www.nvidia.com)

probe_target_latency() {
    case "$1" in
        www.amazon.com) printf '72' ;;
        www.samsung.com) printf '31' ;;
        www.nvidia.com) return 1 ;;
    esac
}
SNI=''
select_fastest_sni >/dev/null
[[ "$SNI" == www.samsung.com ]]

need_root() { :; }
load_metadata() { SNI=www.samsung.com; PORT=443; }
if (change_sni auto >/dev/null 2>&1); then
    printf '旧 auto 参数应被明确拒绝\n' >&2
    exit 1
fi

probe_target_latency() { return 1; }
if select_fastest_sni >/dev/null 2>&1; then
    printf '所有候选站点失效时应停止自动选择\n' >&2
    exit 1
fi

MOCK_DIR="$(mktemp -d)"
trap 'rm -rf -- "$MOCK_DIR"' EXIT
SNI_CANDIDATES=(a.example.com b.example.com c.example.com d.example.com e.example.com f.example.com)
probe_target_latency() {
    if [[ ! -e "$MOCK_DIR/$1" ]]; then
        touch "$MOCK_DIR/$1"
        case "$1" in
            a.example.com) printf '1' ;;
            b.example.com) printf '2' ;;
            c.example.com) printf '3' ;;
            d.example.com) printf '4' ;;
            e.example.com) printf '5' ;;
            f.example.com) printf '6' ;;
        esac
    else
        case "$1" in
            f.example.com) printf '1' ;;
            *) printf '100' ;;
        esac
    fi
}
SNI=''
select_fastest_sni >/dev/null
[[ "$SNI" == f.example.com ]]
printf '候选 SNI 优选验证通过\n'
