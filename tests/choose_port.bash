#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source <(sed '$d' "$ROOT/install.sh")

ss() { return 0; }
PORT=''
choose_port <<< ''
[[ "$PORT" == 443 ]]

ss() {
    if [[ "$*" == *':443'* ]]; then printf 'LISTEN 0 4096 0.0.0.0:443\n'; fi
}
PORT=''
choose_port <<< $'\n8443'
[[ "$PORT" == 8443 ]]
printf '默认端口与占用重试验证通过\n'
