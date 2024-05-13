#!/bin/bash

# Constants
DEFAULT_LOG_FILE="/var/log/userkiller.log"
readonly BACKUP_USER="backup_admin"
readonly NEW_SSH_PORT=2298
readonly SSHD_CONFIG="/etc/ssh/ssh_config"

# Function to log messages with timestamps
log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $message" | tee -a "$LOG_FILE"
}

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
	echo "$(date '+%Y-%m-%d %H:%M:%S'): Error: This script must be run as root."
    exit 1
fi

# Validate the provided username parameter
if [[ $# -ne 1 ]] && [[ $# -ne 2 ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): Error: Incorrect usage. Please provide a username and optionally a log file path as arguments."
    echo "$(date '+%Y-%m-%d %H:%M:%S'): Usage: $0 <username_to_exclude> [log_file_path]"
    exit 1
fi

readonly EXCLUDE_USER="$1"
readonly LOG_FILE="${2:-$DEFAULT_LOG_FILE}"

# Validate that the SSH port is a number between 1024 and 65535
if [[ ! "$NEW_SSH_PORT" =~ ^[0-9]+$ ]] || [[ "$NEW_SSH_PORT" -lt 1024 ]] || [[ "$NEW_SSH_PORT" -gt 65535 ]]; then
    log "Error: Invalid SSH port number: $NEW_SSH_PORT. It must be between 1024 and 65535."
    exit 1
fi

# Prompt the user for a new password and verify it
setup_passwords() {
    while true; do
        read -rsp "Enter new password for users: " NEW_PASSWORD
        echo
        read -rsp "Repeat new password: " REPEAT_PASSWORD
        echo
        if [[ "$NEW_PASSWORD" != "$REPEAT_PASSWORD" ]]; then
            echo "Error: Passwords do not match. Please try again."
        elif [[ ${#NEW_PASSWORD} -lt 8 ]]; then
            echo "Error: Password must be at least 8 characters long."
        else
            break
        fi
    done
}

# Process each user, kill their processes, remove their crontabs, and update their passwords
process_users() {
    local users
    users=$(awk -v exclude="$EXCLUDE_USER" -F: '$7 ~ /(bash|sh)$/ && $1 != exclude && $1 != "root" {print $1}' /etc/passwd)
    for user in $users; do
        log "Processing user $user"

        # Kill all processes for the user
        if pkill -u "$user"; then
            log "Successfully killed processes for $user."
        else
            log "Warning: Failed to kill processes for $user. User may not have been running any processes."
        fi

        # Remove user's crontab
        if crontab -r -u "$user" 2>/dev/null; then
            log "Successfully removed crontab for $user."
        else
            log "Warning: Failed to remove crontab for $user or no crontab exists."
        fi

        # Update user's password
        if echo "$user:$NEW_PASSWORD" | chpasswd; then
            log "Password updated successfully for $user."
        else
            log "Error: Failed to update password for $user."
        fi
    done
}

# Create a backup user with sudo privileges if it doesn't exist
create_backup_user() {
    if id "$BACKUP_USER" &>/dev/null; then
        log "Backup user $BACKUP_USER already exists. Skipping creation."
    else
        if useradd -m -s /bin/bash "$BACKUP_USER"; then
            if echo "$BACKUP_USER:$NEW_PASSWORD" | chpasswd; then
                if usermod -aG sudo "$BACKUP_USER"; then
                    log "Backup user $BACKUP_USER created with sudo access."
                else
                    log "Error: Failed to add backup user $BACKUP_USER to sudo group."
                    exit 1
                fi
            else
                log "Error: Failed to set password for backup user $BACKUP_USER."
                exit 1
            fi
        else
            log "Error: Failed to create backup user $BACKUP_USER."
            exit 1
        fi
    fi
}

# Manage services
manage_services() {
    log "Listing enabled and running services..."
    systemctl list-units --type=service --state=running --no-pager

    read -rp "Enter the names of services to disable (space-separated), or press Enter to skip: " services_to_disable

    if [[ -n "$services_to_disable" ]]; then
        for service in $services_to_disable; do
            log "Stopping and disabling service: $service"
            if systemctl stop "$service" && systemctl disable "$service"; then
                log "Service $service has been stopped and disabled successfully."
            else
                log "Error: Failed to stop or disable service: $service"
            fi
        done
    else
        log "No services selected for disabling."
    fi
}

# Update the SSH daemon configuration and set the immutable flag
update_sshd_config() {
    if [[ ! -f "$SSHD_CONFIG" ]]; then
        log "Error: SSH configuration file not found at $SSHD_CONFIG."
        exit 1
    fi

    if ! sed -i '/^#\s*Port\s/s/^#//' "$SSHD_CONFIG" || ! sed -i "/^Port\s/c\\Port $NEW_SSH_PORT" "$SSHD_CONFIG"; then
        log "Error: Failed to modify Port line in $SSHD_CONFIG."
        exit 1
    fi

    if grep -q "^PermitRootLogin" "$SSHD_CONFIG"; then
        sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
        log "PermitRootLogin has been set to 'no' in $SSHD_CONFIG."
    else
        echo "PermitRootLogin no" >> "$SSHD_CONFIG"
        log "PermitRootLogin 'no' has been added to $SSHD_CONFIG."
    fi

    if ! systemctl restart sshd.service; then
        log "Error: Failed to restart SSH service."
        exit 1
    fi
    log "sshd has been configured to listen on port $NEW_SSH_PORT and disabled root user login."

    # Set the immutable flag on the SSH configuration file
    if chattr +i "$SSHD_CONFIG"; then
        log "Immutable flag set on $SSHD_CONFIG."
    else
        log "Error: Failed to set immutable flag on $SSHD_CONFIG."
        exit 1
    fi

    # Move the default chattr file to /var/log/chatol
    if mv /usr/bin/chattr /var/log/chatol; then
        log "Default chattr file moved to /var/log/chatol."
    else
        log "Error: Failed to move default chattr file to /var/log/chatol."
        exit 1
    fi

    # Create a script to replace the default chattr file
    cat > /usr/bin/chattr <<EOL
#!/bin/bash
echo "Oops..."
EOL
    chmod +x /usr/bin/chattr
    log "Replaced chattr file with a script."
}

# Convert an IP range into individual IPs and output them
ip_range_to_ips() {
    local start end s1 s2 s3 s4 e1 e2 e3 e4 start_dec end_dec ip_dec
    IFS='-' read -r start end <<< "$1"
    IFS='.' read -r s1 s2 s3 s4 <<< "$start"
    IFS='.' read -r e1 e2 e3 e4 <<< "$end"
    
    start_dec=$((s1 * 16777216 + s2 * 65536 + s3 * 256 + s4))
    end_dec=$((e1 * 16777216 + e2 * 65536 + e3 * 256 + e4))

    for ((ip_dec=start_dec; ip_dec<=end_dec; ip_dec++)); do
        echo "$((ip_dec >> 24 & 255)).$((ip_dec >> 16 & 255)).$((ip_dec >> 8 & 255)).$((ip_dec & 255))"
    done
}

# Configure the fire