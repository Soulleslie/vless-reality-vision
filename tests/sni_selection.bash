#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source <(sed '$d' "$ROOT/install.sh")

[[ ${#SNI_CANDIDATES[@]} -eq 68 ]]
declare -A seen=()
for candidate in "${SNI_CANDIDATES[@]}"; do
    valid_host "$candidate"
    [[ ! -v seen[$candidate] ]]
    seen[$candidate]=1
done
[[ -v seen[api.company-target.com] && -v seen[visualstudio.microsoft.com] ]]
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
change_sni auto >/dev/null
[[ "$SNI" == www.samsung.com ]]

probe_target_latency() { return 1; }
if select_fastest_sni >/dev/null 2>&1; then
    printf '所有候选站点失效时应停止自动选择\n' >&2
    exit 1
fi
printf 'SNI 自动优选验证通过\n'
