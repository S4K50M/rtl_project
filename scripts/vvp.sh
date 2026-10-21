#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
if [[ -n ${NOC_IVL_DIR:-} ]]; then exec vvp -M "$NOC_IVL_DIR" "$@"; fi
exec vvp "$@"
