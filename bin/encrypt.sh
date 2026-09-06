#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1. Encrypt setup.rsc -> setup.enc.rsc (binary mode)
SOURCE_RSC="${1:-${SCRIPT_DIR}/setup.rsc}"
if [[ -f "${SOURCE_RSC}" ]]; then
    echo "[*] Encrypting ${SOURCE_RSC} -> ${SCRIPT_DIR}/setup.enc.rsc using SOPS (binary)..."
    sops -e --input-type binary --output-type binary "${SOURCE_RSC}" > "${SCRIPT_DIR}/setup.enc.rsc"
    echo "[+] Successfully encrypted setup.enc.rsc."
fi

# 2. Encrypt inventory.yaml -> inventory.enc.yaml (native YAML mode)
if [[ -f "${SCRIPT_DIR}/inventory.yaml" ]]; then
    echo "[*] Encrypting ${SCRIPT_DIR}/inventory.yaml -> ${SCRIPT_DIR}/inventory.enc.yaml using SOPS (native YAML)..."
    sops -e "${SCRIPT_DIR}/inventory.yaml" > "${SCRIPT_DIR}/inventory.enc.yaml"
    echo "[+] Successfully encrypted inventory.enc.yaml."
fi
