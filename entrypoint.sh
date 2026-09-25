#!/bin/bash
set -eo pipefail

# --- Colorized & Timestamped Logging Helpers ---
log_info()  { echo -e "[\e[32mINFO\e[0m]  [$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
log_warn()  { echo -e "[\e[33mWARN\e[0m]  [$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
log_error() { echo -e "[\e[31mERROR\e[0m] [$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
log_debug() { echo -e "[\e[34mDEBUG\e[0m] [$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

echo "=========================================================================="
echo "          OpenShift Container Platform - collectl Telemetry Daemon       "
echo "=========================================================================="

log_info "Initializing node telemetry daemon container..."
log_info "Host Node Name : ${NODE_NAME:-$(hostname)}"
log_info "Kernel Release : $(uname -r)"
log_info "Container PID  : $$"

# --- Environment & Mount Diagnostics ---
log_info "Validating runtime mounts and filesystem isolation..."

# ProcFS Verification
if [ -d "/proc/1" ]; then
    INIT_COMM=$(cat /proc/1/comm 2>/dev/null || echo "unknown")
    log_info "ProcFS Mount   : /proc is mounted (Host PID 1 executable: '${INIT_COMM}')"
else
    log_error "ProcFS Error   : /proc directory is not accessible!"
fi

# SysFS Verification
if [ -d "/sys/devices" ]; then
    log_info "SysFS Mount    : /sys is accessible."
else
    log_warn "SysFS Warning  : /sys/devices not found."
fi

# Target Log Directory Diagnostics
LOG_DIR="/var/log/collectl"
log_info "Checking target telemetry output path: ${LOG_DIR}"
if [ ! -d "${LOG_DIR}" ]; then
    log_warn "Log Directory  : ${LOG_DIR} missing. Creating directory structure..."
    mkdir -p "${LOG_DIR}"
fi

# Configuration File Inspection & Args Extraction
CONF_FILE="/etc/collectl.conf"
ARGS=""
if [ -f "${CONF_FILE}" ]; then
    log_info "Configuration  : Found ${CONF_FILE}."
    
    # Safely extract ONLY DaemonCommands. We use sed to handle the spaces around the '=' sign.
    # The other variables (ProcessFilter, Interval) are natively parsed by the collectl perl binary.
    ARGS=$(grep -E '^DaemonCommands[[:space:]]*=' "${CONF_FILE}" | sed 's/^[^=]*=[[:space:]]*//' | tr -d "\"'")
    
    if [ -n "${ARGS// /}" ]; then
        log_info "Daemon ARGS    : Extracted DaemonCommands: ${ARGS}"
    else
        log_warn "Daemon ARGS    : No DaemonCommands found in ${CONF_FILE}"
    fi
else
    log_warn "Configuration  : ${CONF_FILE} not detected! Falling back to built-in binary defaults."
fi

COLLECTL_PID=""

# --- Signal Handling & Buffer Flushing ---
term_handler() {
    echo ""
    log_warn "Signal Caught  : Termination signal received (SIGTERM/SIGINT/SIGHUP)."
    if [ -n "${COLLECTL_PID}" ] && kill -0 "${COLLECTL_PID}" 2>/dev/null; then
        log_info "Signal Handler : Transmitting SIGINT to trigger in-memory buffer flush (-F60) to ${LOG_DIR}..."
        kill -INT "${COLLECTL_PID}" 2>/dev/null || true
        wait "${COLLECTL_PID}" 2>/dev/null || true
        log_info "Buffer Flush   : Telemetry log buffer flush complete."
    fi
    log_info "Shutdown Complete: Container exiting cleanly."
    exit 0
}

trap 'term_handler' SIGTERM SIGINT SIGHUP

# --- Launch Execution ---
if [ -n "${ARGS// /}" ]; then
    log_info "Launching collectl daemon in foreground mode with extracted arguments..."
    # ARGS intentionally unquoted so bash splits it into proper arguments for the binary
    /usr/bin/collectl --nodaemon ${ARGS} &
else
    log_info "Launching collectl daemon in foreground mode with default arguments..."
    /usr/bin/collectl --nodaemon &
fi

COLLECTL_PID=$!

# --- Process Parameter Verification ---
# Brief sleep to allow kernel to populate process cmdline
sleep 1

if kill -0 "${COLLECTL_PID}" 2>/dev/null; then
    # /proc/PID/cmdline is null-byte separated (\0), we translate it to spaces to print nicely
    ACTUAL_CMD=$(tr '\0' ' ' < "/proc/${COLLECTL_PID}/cmdline")
    
    log_info "Daemon Status  : collectl successfully running in background with PID ${COLLECTL_PID}."
    log_info "Daemon Process : Confirmed execution with exact arguments seen by the OS:"
    log_info "                 > ${ACTUAL_CMD}"
else
    log_error "Daemon Status  : collectl process (PID ${COLLECTL_PID}) failed to start or died immediately."
    exit 1
fi

log_info "Logging Path   : ${LOG_DIR}"
log_info "Lifecycle      : Listening for CRI-O / kubelet eviction signals..."

wait "${COLLECTL_PID}"