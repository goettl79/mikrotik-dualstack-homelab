#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1. Re-encrypt inventory.yaml if modified
if [[ -f "${SCRIPT_DIR}/inventory.yaml" ]]; then
    if [[ ! -f "${SCRIPT_DIR}/inventory.enc.yaml" ]] || ! cmp -s "${SCRIPT_DIR}/inventory.yaml" <(sops -d "${SCRIPT_DIR}/inventory.enc.yaml" 2>/dev/null); then
        echo "[*] Changes detected in inventory.yaml. Re-encrypting -> inventory.enc.yaml..."
        sops -e "${SCRIPT_DIR}/inventory.yaml" > "${SCRIPT_DIR}/inventory.enc.yaml"
        git -C "${SCRIPT_DIR}" add inventory.enc.yaml
    fi
fi

# 2. Re-encrypt setup.rsc if modified
if [[ -f "${SCRIPT_DIR}/setup.rsc" ]]; then
    if [[ ! -f "${SCRIPT_DIR}/setup.enc.rsc" ]] || ! cmp -s "${SCRIPT_DIR}/setup.rsc" <(sops -d --input-type binary --output-type binary "${SCRIPT_DIR}/setup.enc.rsc" 2>/dev/null); then
        echo "[*] Changes detected in setup.rsc. Re-encrypting -> setup.enc.rsc..."
        sops -e --input-type binary --output-type binary "${SCRIPT_DIR}/setup.rsc" > "${SCRIPT_DIR}/setup.enc.rsc"
        git -C "${SCRIPT_DIR}" add setup.enc.rsc
    fi
fi

# 3. Execute git commit
git -C "${SCRIPT_DIR}" commit "$@"
