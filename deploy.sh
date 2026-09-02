#!/usr/bin/env bash
# ==============================================================================
# MikroTik RouterOS v7 Deployment Script
# ==============================================================================
set -euo pipefail

TARGET_IP="${1:-192.168.88.1}"
ROUTER_USER="${2:-admin}"
SSH_PORT="${3:-22}"
ROUTER_PASS="${4:-${ROUTER_PASSWORD:-}}"
SCRIPT_FILE="setup.rsc"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/${SCRIPT_FILE}"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

echo "============================================================"
echo " MikroTik hEX Provisioning Deployment"
echo " Target: ${ROUTER_USER}@${TARGET_IP}:${SSH_PORT}"
echo " File:   ${CONFIG_PATH}"
echo "============================================================"

# Check if configuration script exists
if [[ ! -f "${CONFIG_PATH}" ]]; then
    echo "[-] Error: ${CONFIG_PATH} not found!" >&2
    exit 1
fi

# 1. Test ping reachability
echo "[*] Step 1: Testing network connectivity to ${TARGET_IP}..."
if ping -c 2 -W 2 "${TARGET_IP}" > /dev/null 2>&1; then
    echo "[+] Target ${TARGET_IP} is reachable via ICMP."
else
    echo "[!] Warning: Target did not respond to ICMP ping. Proceeding with SSH check..."
fi

# 2. Check SSH availability
echo "[*] Step 2: Testing SSH port ${SSH_PORT}..."
if nc -z -w 3 "${TARGET_IP}" "${SSH_PORT}" 2>/dev/null || (exec 3<>/dev/tcp/"${TARGET_IP}"/"${SSH_PORT}") 2>/dev/null; then
    echo "[+] SSH port ${SSH_PORT} is open."
else
    echo "[-] Error: SSH port ${SSH_PORT} on ${TARGET_IP} is not reachable." >&2
    exit 1
fi

# Determine prefix command (sshpass if password provided)
SCP_CMD=(scp "${SSH_OPTS[@]}" -P "${SSH_PORT}")
SSH_CMD=(ssh "${SSH_OPTS[@]}" -p "${SSH_PORT}")

if [[ -n "${ROUTER_PASS}" ]]; then
    if command -v sshpass >/dev/null 2>&1; then
        SCP_CMD=(sshpass -p "${ROUTER_PASS}" "${SCP_CMD[@]}")
        SSH_CMD=(sshpass -p "${ROUTER_PASS}" "${SSH_CMD[@]}")
    else
        echo "[!] Info: sshpass not installed locally, will prompt for password if needed."
    fi
fi

# 3. Upload setup.rsc via SCP
echo "[*] Step 3: Uploading ${SCRIPT_FILE} to MikroTik router..."
"${SCP_CMD[@]}" "${CONFIG_PATH}" "${ROUTER_USER}@${TARGET_IP}:${SCRIPT_FILE}"
echo "[+] Upload completed successfully."

# 4. Execute configuration import via SSH
echo "[*] Step 4: Importing ${SCRIPT_FILE} on RouterOS..."
"${SSH_CMD[@]}" "${ROUTER_USER}@${TARGET_IP}" "/import verbose=yes file-name=${SCRIPT_FILE}" || true

echo "============================================================"
echo "[+] Deployment script finished!"
echo "    1. INTERNET:    vlan31-internet (A1/Telematica ONT auf ether1)"
echo "    2. HEIMNETZ:    192.168.10.1 / IPv6 SLAAC (bridge-heimnetz, ether3-5)"
echo "    3. SERVER-ZONE: 192.168.20.1 / IPv6 SLAAC (ether2, k3d Cluster)"
echo ""
echo "    Hinweis: Dein PC erhaelt nach DHCP-Erneuerung eine IP aus 192.168.10.0/24."
echo "    Der Router ist nun unter 192.168.10.1 erreichbar."
echo "============================================================"
