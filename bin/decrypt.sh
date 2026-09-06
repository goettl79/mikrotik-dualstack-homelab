#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1. Decrypt setup.enc.rsc -> setup.rsc (binary mode)
if [[ -f "${SCRIPT_DIR}/setup.enc.rsc" ]]; then
    echo "[*] Decrypting ${SCRIPT_DIR}/setup.enc.rsc -> ${SCRIPT_DIR}/setup.rsc using SOPS..."
    sops -d --input-type binary --output-type binary "${SCRIPT_DIR}/setup.enc.rsc" > "${SCRIPT_DIR}/setup.rsc"
    echo "[+] Successfully decrypted setup.rsc."
fi

# 2. Decrypt inventory.enc.yaml -> inventory.yaml (native YAML mode)
if [[ -f "${SCRIPT_DIR}/inventory.enc.yaml" ]]; then
    echo "[*] Decrypting ${SCRIPT_DIR}/inventory.enc.yaml -> ${SCRIPT_DIR}/inventory.yaml using SOPS..."
    sops -d "${SCRIPT_DIR}/inventory.enc.yaml" > "${SCRIPT_DIR}/inventory.yaml"
    echo "[+] Successfully decrypted inventory.yaml."
fi
