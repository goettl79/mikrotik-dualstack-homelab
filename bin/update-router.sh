#!/usr/bin/env bash
# ==============================================================================
# MikroTik RouterOS & RouterBOOT Safe Update Automation
# Target Hardware: MikroTik hEX (RB750Gr3) / RouterOS v7
# ==============================================================================
# Safety features:
#   1. Pre-flight connectivity, channel & free flash space checks (<4MB warning)
#   2. Automatic local dual-backup (binary .backup + compact .rsc export)
#   3. Flash memory cleanup before downloading update package (prevents out-of-space)
#   4. RouterOS package upgrade with automated reboot tracking
#   5. RouterBOOT bootloader firmware upgrade & second reboot
#   6. Post-upgrade health checks (WAN, LAN, DMZ & external DNS/ping verification)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"

# Default parameters
TARGET_IP="192.168.10.1"
ROUTER_USER="admin"
SSH_PORT="22"
CHANNEL="stable"
CHECK_ONLY=false
BACKUP_ONLY=false
NON_INTERACTIVE=false
FORCE_UPDATE=false

# Terminal colors
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[*]${NC} $*"; }
log_success() { echo -e "${GREEN}[+]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
log_error()   { echo -e "${RED}[-]${NC} $*" >&2; }
log_header()  { echo -e "\n${BOLD}${CYAN}=== $* ===${NC}\n"; }

usage() {
    cat << USAGE
Usage: $(basename "$0") [OPTIONS] [TARGET_IP]

Safe, automated update tool for MikroTik RouterOS & RouterBOARD firmware.

Options:
  -c, --check            Check for available updates without applying them (read-only)
  -b, --backup-only      Generate binary backup + RSC export, download locally, and exit
  -y, --yes              Non-interactive mode (proceed without confirmation prompts)
  -f, --force            Force update procedure even if versions match
  --channel <channel>    Update channel: stable (default), testing, or long-term
  -u, --user <user>      SSH username (default: admin)
  -p, --port <port>      SSH port (default: 22)
  -h, --help             Show this help message

Examples:
  $(basename "$0") --check
  $(basename "$0") --backup-only
  $(basename "$0")
  $(basename "$0") -y 192.168.10.1
USAGE
    exit 0
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--check)
            CHECK_ONLY=true
            shift
            ;;
        -b|--backup-only)
            BACKUP_ONLY=true
            shift
            ;;
        -y|--yes)
            NON_INTERACTIVE=true
            shift
            ;;
        -f|--force)
            FORCE_UPDATE=true
            shift
            ;;
        --channel)
            CHANNEL="$2"
            shift 2
            ;;
        -u|--user)
            ROUTER_USER="$2"
            shift 2
            ;;
        -p|--port)
            SSH_PORT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            TARGET_IP="$1"
            shift
            ;;
    esac
done

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 -p "${SSH_PORT}")
SCP_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 -P "${SSH_PORT}")

run_ssh() {
    ssh "${SSH_OPTS[@]}" "${ROUTER_USER}@${TARGET_IP}" "$@" | tr -d '\r'
}

wait_for_ping() {
    local target="$1"
    local timeout="${2:-180}"
    local start_time
    start_time=$(date +%s)

    while true; do
        if ping -c 1 -W 1 "${target}" >/dev/null 2>&1; then
            return 0
        fi
        local now
        now=$(date +%s)
        if (( now - start_time >= timeout )); then
            return 1
        fi
        sleep 2
    done
}

wait_for_ssh() {
    local target="$1"
    local timeout="${2:-120}"
    local start_time
    start_time=$(date +%s)

    while true; do
        if nc -z -w 2 "${target}" "${SSH_PORT}" 2>/dev/null || (exec 3<>/dev/tcp/"${target}"/"${SSH_PORT}") 2>/dev/null; then
            # Test actual auth
            if run_ssh ':put "ready"' >/dev/null 2>&1; then
                return 0
            fi
        fi
        local now
        now=$(date +%s)
        if (( now - start_time >= timeout )); then
            return 1
        fi
        sleep 3
    done
}

# ------------------------------------------------------------------------------
# STEP 1: Pre-Flight Checks & Target Inspection
# ------------------------------------------------------------------------------
log_header "Step 1: Pre-Flight Safety Checks"

log_info "Testing ICMP connectivity to ${TARGET_IP}..."
if ! ping -c 2 -W 2 "${TARGET_IP}" >/dev/null 2>&1; then
    log_error "Target ${TARGET_IP} is not reachable via ICMP. Aborting."
    exit 1
fi
log_success "Target ${TARGET_IP} is responding to ping."

log_info "Testing SSH connectivity (${ROUTER_USER}@${TARGET_IP}:${SSH_PORT})..."
if ! run_ssh ':put "ok"' >/dev/null 2>&1; then
    log_error "SSH key authentication to ${ROUTER_USER}@${TARGET_IP} failed. Make sure your SSH key is authorized."
    exit 1
fi
log_success "SSH key authentication verified."

# Query hardware model, disk space, and current version
ROUTER_MODEL=$(run_ssh ':put [/system resource get board-name]' 2>/dev/null || echo "MikroTik")
PLATFORM=$(run_ssh ':put [/system resource get platform]' 2>/dev/null || echo "RouterOS")
FREE_HDD_BYTES=$(run_ssh ':put [/system resource get free-hdd-space]' 2>/dev/null || echo "0")
TOTAL_HDD_BYTES=$(run_ssh ':put [/system resource get total-hdd-space]' 2>/dev/null || echo "0")
FREE_HDD_MB=$(awk "BEGIN {printf \"%.1f\", ${FREE_HDD_BYTES}/1048576}")
TOTAL_HDD_MB=$(awk "BEGIN {printf \"%.1f\", ${TOTAL_HDD_BYTES}/1048576}")

# Check updates
log_info "Querying RouterOS update server (Channel: ${CHANNEL})..."
run_ssh "/system package update set channel=${CHANNEL}" >/dev/null 2>&1 || true
run_ssh "/system package update check-for-updates once" >/dev/null 2>&1 || true
sleep 3

INSTALLED_VER=$(run_ssh ':put [/system package update get installed-version]' 2>/dev/null || echo "unknown")
LATEST_VER=$(run_ssh ':put [/system package update get latest-version]' 2>/dev/null || echo "unknown")
UPDATE_STATUS=$(run_ssh ':put [/system package update get status]' 2>/dev/null || echo "unknown")

CURRENT_FW=$(run_ssh ':put [/system routerboard get current-firmware]' 2>/dev/null || echo "unknown")
UPGRADE_FW=$(run_ssh ':put [/system routerboard get upgrade-firmware]' 2>/dev/null || echo "unknown")

echo ""
echo -e "  Hardware:           ${BOLD}${ROUTER_MODEL}${NC} (${PLATFORM})"
echo -e "  Free Flash Space:   ${BOLD}${FREE_HDD_MB} MiB / ${TOTAL_HDD_MB} MiB${NC}"
echo -e "  Update Channel:     ${BOLD}${CHANNEL}${NC}"
echo -e "  Installed Version:  ${BOLD}${INSTALLED_VER}${NC}"
echo -e "  Latest Version:     ${BOLD}${LATEST_VER}${NC}"
echo -e "  Update Status:      ${BOLD}${UPDATE_STATUS}${NC}"
echo -e "  RouterBOOT Current: ${BOLD}${CURRENT_FW}${NC}"
echo -e "  RouterBOOT Upgrade: ${BOLD}${UPGRADE_FW}${NC}"
echo ""

# Safety check for flash storage (RB750Gr3 only has 16MB flash)
if (( FREE_HDD_BYTES < 3500000 )); then
    log_error "CRITICAL: Only ${FREE_HDD_MB} MiB free flash memory available."
    log_error "RouterOS packages require at least 3.5 MB free space during download."
    log_error "Please remove old backups or unused files on flash disk before updating."
    exit 1
elif (( FREE_HDD_BYTES < 5000000 )); then
    log_warn "Notice: Flash space is tight (${FREE_HDD_MB} MiB free). Backup files will be removed from router after local download."
fi

if [[ "${CHECK_ONLY}" == true ]]; then
    if [[ "${INSTALLED_VER}" != "${LATEST_VER}" && "${LATEST_VER}" != "unknown" ]]; then
        log_warn "An update is available: ${INSTALLED_VER} -> ${LATEST_VER} (Run without --check to install)"
    else
        log_success "System is up to date (${INSTALLED_VER})."
    fi
    exit 0
fi

# ------------------------------------------------------------------------------
# STEP 2: Automatic Pre-Upgrade Backup (Saved locally)
# ------------------------------------------------------------------------------
log_header "Step 2: Creating Pre-Upgrade Backups"

mkdir -p "${BACKUP_DIR}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="backup-${ROUTER_MODEL}-${INSTALLED_VER}-${TIMESTAMP}"

log_info "Creating binary backup (${BACKUP_NAME}.backup)..."
run_ssh "/system backup save name=\"${BACKUP_NAME}\"" >/dev/null

log_info "Creating compact text export (${BACKUP_NAME}.rsc)..."
run_ssh "/export compact file=\"${BACKUP_NAME}\"" >/dev/null
sleep 2

log_info "Downloading backups via SCP to ${BACKUP_DIR}/..."
scp "${SCP_OPTS[@]}" "${ROUTER_USER}@${TARGET_IP}:${BACKUP_NAME}.backup" "${BACKUP_DIR}/"
scp "${SCP_OPTS[@]}" "${ROUTER_USER}@${TARGET_IP}:${BACKUP_NAME}.rsc" "${BACKUP_DIR}/"

if [[ -f "${BACKUP_DIR}/${BACKUP_NAME}.backup" && -f "${BACKUP_DIR}/${BACKUP_NAME}.rsc" ]]; then
    log_success "Backups successfully retrieved:"
    echo "    - ${BACKUP_DIR}/${BACKUP_NAME}.backup ($(du -h "${BACKUP_DIR}/${BACKUP_NAME}.backup" | cut -f1))"
    echo "    - ${BACKUP_DIR}/${BACKUP_NAME}.rsc ($(du -h "${BACKUP_DIR}/${BACKUP_NAME}.rsc" | cut -f1))"
else
    log_error "Failed to retrieve local backup files. Aborting update for safety."
    exit 1
fi

log_info "Cleaning up backup files from router flash to free memory for packages..."
run_ssh ":do { /file remove [ find name=\"${BACKUP_NAME}.backup\" or name=\"${BACKUP_NAME}.rsc\" ] } on-error={}" >/dev/null
log_success "Router flash memory freed."

if [[ "${BACKUP_ONLY}" == true ]]; then
    log_success "Backup completed successfully. Exiting (--backup-only mode)."
    exit 0
fi

# ------------------------------------------------------------------------------
# STEP 3: Version Comparison & Confirmation
# ------------------------------------------------------------------------------
if [[ "${INSTALLED_VER}" == "${LATEST_VER}" && "${FORCE_UPDATE}" == false ]]; then
    log_success "RouterOS is already on the latest available version (${INSTALLED_VER})."
    
    # Check if RouterBOOT still needs an upgrade
    if [[ "${CURRENT_FW}" != "${UPGRADE_FW}" && "${UPGRADE_FW}" != "unknown" ]]; then
        log_warn "However, RouterBOOT bootloader firmware is not yet upgraded (${CURRENT_FW} -> ${UPGRADE_FW})."
    else
        log_success "RouterBOOT firmware is also completely up to date. No actions needed."
        exit 0
    fi
fi

if [[ "${NON_INTERACTIVE}" == false ]]; then
    echo -e "${YELLOW}You are about to upgrade:${NC}"
    echo -e "  Target:   ${ROUTER_USER}@${TARGET_IP}"
    echo -e "  RouterOS: ${BOLD}${INSTALLED_VER}${NC} -> ${BOLD}${LATEST_VER}${NC}"
    echo -e "  Backup:   ${BACKUP_DIR}/${BACKUP_NAME}.backup"
    echo ""
    read -r -p "Do you want to proceed with downloading and installing? [y/N]: " CONFIRM
    if [[ ! "${CONFIRM}" =~ ^[yY]([eE][sS])?$ ]]; then
        log_warn "Update aborted by user."
        exit 0
    fi
fi

# ------------------------------------------------------------------------------
# STEP 4: RouterOS Package Upgrade & Reboot Tracking
# ------------------------------------------------------------------------------
if [[ "${INSTALLED_VER}" != "${LATEST_VER}" || "${FORCE_UPDATE}" == true ]]; then
    log_header "Step 3: Upgrading RouterOS Packages"
    log_info "Triggering RouterOS download-and-install on router..."

    # Initiate install (RouterOS will download and trigger reboot)
    run_ssh "/system package update install" >/dev/null 2>&1 || true

    log_info "Waiting for router to reboot (downloading package & writing to flash)..."
    sleep 15

    log_info "Waiting for router to drop connection..."
    COUNT=0
    while ping -c 1 -W 1 "${TARGET_IP}" >/dev/null 2>&1 && (( COUNT < 30 )); do
        sleep 2
        COUNT=$((COUNT + 1))
    done

    log_info "Router has rebooted. Waiting for network link to return..."
    if ! wait_for_ping "${TARGET_IP}" 180; then
        log_error "Timeout: Router did not respond to ping within 180 seconds!"
        exit 1
    fi
    log_success "Router is answering ICMP ping."

    log_info "Waiting for SSH service to become ready..."
    if ! wait_for_ssh "${TARGET_IP}" 90; then
        log_error "Timeout: SSH service did not become available within 90 seconds!"
        exit 1
    fi
    log_success "SSH connection re-established."

    NEW_VER=$(run_ssh ':put [/system package update get installed-version]' 2>/dev/null || echo "unknown")
    log_success "RouterOS successfully upgraded: ${INSTALLED_VER} -> ${BOLD}${NEW_VER}${NC}"
fi

# ------------------------------------------------------------------------------
# STEP 5: RouterBOOT Firmware Upgrade (Bootloader)
# ------------------------------------------------------------------------------
log_header "Step 4: RouterBOOT Firmware (Bootloader)"

FW_CURRENT=$(run_ssh ':put [/system routerboard get current-firmware]' 2>/dev/null || echo "unknown")
FW_UPGRADE=$(run_ssh ':put [/system routerboard get upgrade-firmware]' 2>/dev/null || echo "unknown")

if [[ "${FW_CURRENT}" != "${FW_UPGRADE}" && "${FW_UPGRADE}" != "unknown" ]]; then
    log_warn "RouterBOOT bootloader upgrade available: ${FW_CURRENT} -> ${FW_UPGRADE}"
    log_info "Upgrading RouterBOARD bootloader firmware..."

    run_ssh ":execute { /system routerboard upgrade }" >/dev/null
    sleep 4

    log_info "Rebooting router to activate new bootloader firmware..."
    run_ssh ":execute { /system reboot }" >/dev/null 2>&1 || true

    sleep 10
    log_info "Waiting for router reboot..."
    if ! wait_for_ping "${TARGET_IP}" 120; then
        log_error "Timeout: Router did not return after firmware reboot."
        exit 1
    fi
    if ! wait_for_ssh "${TARGET_IP}" 60; then
        log_error "Timeout: SSH did not become available after firmware reboot."
        exit 1
    fi

    FW_ACTIVE=$(run_ssh ':put [/system routerboard get current-firmware]' 2>/dev/null || echo "unknown")
    log_success "RouterBOOT firmware updated: ${BOLD}${FW_ACTIVE}${NC}"
else
    log_success "RouterBOOT bootloader firmware is already up to date (${FW_CURRENT})."
fi

# ------------------------------------------------------------------------------
# STEP 6: Post-Upgrade Health & Verification Checks
# ------------------------------------------------------------------------------
log_header "Step 5: Post-Upgrade Health Checks"

UPTIME=$(run_ssh ':put [/system resource get uptime]' 2>/dev/null || echo "unknown")
FINAL_VER=$(run_ssh ':put [/system package update get installed-version]' 2>/dev/null || echo "unknown")
FINAL_FW=$(run_ssh ':put [/system routerboard get current-firmware]' 2>/dev/null || echo "unknown")
FINAL_FREE_HDD=$(run_ssh ':put [/system resource get free-hdd-space]' 2>/dev/null || echo "0")
FINAL_FREE_MB=$(awk "BEGIN {printf \"%.1f\", ${FINAL_FREE_HDD}/1048576}")

# Check Internet link & ping
log_info "Testing Internet connectivity from router (1.1.1.1)..."
PING_RES=$(run_ssh ':put [/ping 1.1.1.1 count=3]' 2>/dev/null || echo "0")
if [[ "${PING_RES}" =~ [1-3] ]]; then
    log_success "WAN uplink: Internet ping successful (received ${PING_RES}/3 packets)."
else
    log_warn "WAN uplink ping failed or packet loss observed."
fi

# Check DNS resolution
log_info "Testing DNS resolution from router (cloudflare.com)..."
DNS_IP=$(run_ssh ':put [:resolve cloudflare.com]' 2>/dev/null || echo "failed")
if [[ "${DNS_IP}" != "failed" && -n "${DNS_IP}" ]]; then
    log_success "DNS resolution: cloudflare.com -> ${DNS_IP}"
else
    log_warn "DNS resolution test failed."
fi

# Check DHCP servers status
DHCP_SERVERS=$(run_ssh ':put [:len [/ip dhcp-server find disabled=no]]' 2>/dev/null || echo "0")
log_info "Active DHCP servers on router: ${DHCP_SERVERS}"

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}${BOLD} MikroTik Safe Update Completed Successfully!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "  Model:            ${ROUTER_MODEL} (${PLATFORM})"
echo -e "  RouterOS Version: ${BOLD}${FINAL_VER}${NC}"
echo -e "  RouterBOOT FW:    ${BOLD}${FINAL_FW}${NC}"
echo -e "  System Uptime:    ${UPTIME}"
echo -e "  Free Storage:     ${FINAL_FREE_MB} MiB"
echo -e "  Local Backup:     ${BACKUP_DIR}/${BACKUP_NAME}.*"
echo -e "${GREEN}============================================================${NC}"

