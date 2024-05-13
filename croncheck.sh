#!/bin/bash

# Constants
readonly BACKUP_USER="backup_admin"
readonly SSH_CONFIG="/etc/ssh/sshd_config"
readonly LOG_FILE="/var/log/croncheck.log"

# Function to log messages with timestamps
log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $message" | tee -a "$LOG_FILE"
}

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    log "Error: This script must be run as root."
    exit 1
fi

# Check if the backup user exists
if ! id "$BACKUP_USER" &>/dev/null; then
    log "Error: Backup user $BACKUP_USER does not exist."
    exit 1
fi

# Check if the backup user has sudo access
if ! sudo -l -U "$BACKUP_USER" &>/dev/null; then
    log "Error: Backup user $BACKUP_USER does not have sudo access."
    exit 1
fi

# Check if the SSH configuration file is unchanged
if ! sudo lsattr "$SSH_CONFIG" 2>/dev/null | grep -q '^----i---------e--, '; then
    log "Error: SSH configuration file has been modified."
    exit 1
fi

# Check if the firewall rules are unchanged
if command -v ufw &>/dev/null && ufw status | grep -qw "active"; then
    # Check UFW rules
    if ! ufw status numbered | grep -qw "98"; then
        log "Error: UFW rules have been modified."
        exit 1
    fi
elif command -v iptables &>/dev/null; then
    # Check iptables rules
    if ! iptables -L INPUT --line-numbers | grep -q "tcp dpt:98"; then
        log "Error: iptables rules have been modified."
        exit 1
    fi
else
    log "Warning: No known firewall (ufw or iptables) is active on this system."
    exit 1
fi

log "All checks passed successfully."
exit 0
