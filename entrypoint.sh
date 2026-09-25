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
    if [ "${INIT_COMM}" != "systemd" ] && [ "${INIT_COMM}" != "init" ]; then
        log_warn "ProcFS Warning : PID 1 is '${INIT_COMM}'. If this is not host systemd/init, verify hostPID: true and /proc volumeMount configurations."
    fi
else
    log_error "ProcFS Error   : /proc directory is not accessible!"
fi

# SysFS Verification
if [ -d "/sys/devices" ]; then
    log_info "SysFS Mount    : /sys is accessible."
else
    log_warn "SysFS Warning  : /sys/devices not found. Some per-core CPU or interrupt metrics may be degraded."
fi

# Target Log Directory Diagnostics
LOG_DIR="/var/log/collectl"
log_info "Checking target telemetry output path: ${LOG_DIR}"
if [ -d "${LOG_DIR}" ]; then
    log_info "Log Directory  : ${LOG_DIR} exists."
else
    log_warn "Log Directory  : ${LOG_DIR} missing. Creating directory structure..."
    mkdir -p "${LOG_DIR}"
    log_info "Log Directory  : Path ${LOG_DIR} successfully initialized."
fi

# Configuration File Inspection
CONF_FILE="/etc/collectl.conf"
if [ -f "${CONF_FILE}" ]; then
    log_info "Configuration  : Found ${CONF_FILE}. Dumping active directives:"
    echo "--------------------------------------------------------------------------"
    grep -v '^\s*#' "${CONF_FILE}" | grep -v '^\s*$' | while read -r line; do
        log_debug "  ${line}"
    done
    echo "--------------------------------------------------------------------------"
else
    log_warn "Configuration  : ${CONF_FILE} not detected! Falling back to built-in binary defaults."
fi

COLLECTL_PID=""

# --- Signal Handling & Buffer Flushing ---
term_handler() {
    echo ""
    log_warn "Signal Caught  : Termination signal received (SIGTERM/SIGINT/SIGHUP)."
    if [ -n "${COLLECTL_PID}" ] && kill -0 "${COLLECTL_PID}" 2>/dev/null; then
        log_info "Signal Handler : Active collectl process detected (PID: ${COLLECTL_PID})."
        log_info "Buffer Flush   : Transmitting SIGINT to trigger in-memory buffer flush (-F60) to ${LOG_DIR}..."
        
        kill -INT "${COLLECTL_PID}" 2>/dev/null || true
        
        log_info "Buffer Flush   : Awaiting collectl log sync and graceful process exit..."
        wait "${COLLECTL_PID}" 2>/dev/null || true
        log_info "Buffer Flush   : Telemetry log buffer flush complete."
    else
        log_warn "Signal Handler : No active collectl subprocess found under PID '${COLLECTL_PID}'."
    fi
    log_info "Shutdown Complete: Container exiting cleanly."
    exit 0
}

trap 'term_handler' SIGTERM SIGINT SIGHUP

# --- Launch Execution ---
log_info "Launching collectl daemon in foreground mode (--nodaemon)..."
/usr/bin/collectl --nodaemon &
COLLECTL_PID=$!

log_info "Daemon Status  : collectl running in background subshell with PID ${COLLECTL_PID}."
log_info "Logging Path   : ${LOG_DIR}"
log_info "Lifecycle      : Listening for CRI-O / kubelet eviction signals..."

# Block script execution while keeping trap handlers reactive
wait "${COLLECTL_PID}"