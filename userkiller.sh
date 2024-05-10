#!/bin/bash

DEFAULT_LOG_FILE="/var/log/userkiller.log"

# Function to log messages with timestamps
log() {
    local message=$1
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $message"
}

# Checks if the script is run as root, exits if not.
check_run_as_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "This script must be run as root"
        exit 1
    fi
}

# Validates that a username is provided as a parameter, and optionally a log file path.
validate_parameters() {
    if [ -z "$1" ]; then
        log "Usage: $0 <username_to_exclude> [log_file_path]"
        exit 1
    fi
}

# Validates that one or two arguments are provided.
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    log "Incorrect usage. Please provide a username and optionally a log file path as arguments."
    log "Usage: $0 <username_to_exclude> [log_file_path]"
    exit 1
fi

# Validates that the SSH port is a number between 1024 and 65535.
validate_ssh_port() {
    if ! [[ "$NEW_SSH_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_SSH_PORT" -lt 1024 ] || [ "$NEW_SSH_PORT" -gt 65535 ]; then
        log "Invalid SSH port number: $NEW_SSH_PORT. It must be between 1024 and 65535."
        exit 1
    fi
}

# Prompts the user for a new password and verifies it.
setup_passwords() {
    while true; do
        read -rsp "Enter new password for users: " NEW_PASSWORD
        echo
        read -rsp "Repeat new password: " REPEAT_PASSWORD
        echo
        if [ "$NEW_PASSWORD" != "$REPEAT_PASSWORD" ]; then
            echo "Passwords do not match. Please try again."
        elif [ ${#NEW_PASSWORD} -lt 8 ]; then
            echo "Password must be at least 8 characters long."
        else
            break
        fi
    done
}

# Processes each user, kills their processes, removes their crontabs, and updates their passwords.
process_users() {
    USERS=$(awk -v exclude="$EXCLUDE_USER" -F: '$7 ~ /(bash|sh)$/ && $1 != exclude && $1 != "root" {print $1}' /etc/passwd)
    for USER in $USERS; do
        log "Processing user $USER"

        # Kill all processes for the user
        if pkill -u $USER; then
            log "Successfully killed processes for $USER."
        else
            log "Failed to kill processes for $USER. User may not have been running any processes." >&2
        fi

        # Remove user's crontab
        if crontab -r -u $USER 2>/dev/null; then
            log "Successfully removed crontab for $USER."
        else
            log "Failed to remove crontab for $USER or no crontab exists." >&2
            # Continue to the next user
            continue
        fi

        # Update user's password
        if echo "$USER:$NEW_PASSWORD" | chpasswd; then
            log "Password updated successfully for $USER."
        else
            log "Failed to update password for $USER." >&2
            # Continue to the next user
            continue
        fi
    done
}

# Creates a backup user with sudo privileges if it doesn't exist.
create_backup_user() {
    BACKUP_USER="backup_admin"
    if id "$BACKUP_USER" >/dev/null 2>&1; then
        log "Backup user $BACKUP_USER already exists. Skipping creation."
    else
        if useradd -m -s /bin/bash "$BACKUP_USER"; then
            if echo "$BACKUP_USER:$NEW_PASSWORD" | chpasswd; then
                if usermod -aG sudo "$BACKUP_USER"; then
                    log "Backup user $BACKUP_USER created with sudo access"
                else
                    log "Failed to add backup user $BACKUP_USER to sudo group"
                    exit 1
                fi
            else
                log "Failed to set password for backup user $BACKUP_USER"
                exit 1
            fi
        else
            log "Failed to create backup user $BACKUP_USER"
            exit 1
        fi
    fi
}

# Function to manage services
manage_services() {
    log "Listing enabled and running services..."
    systemctl list-units --type=service --state=running --no-pager

    read -rp "Enter the names of services to disable (space-separated), or press Enter to skip: " services_to_disable

    if [ -n "$services_to_disable" ]; then
        for service in $services_to_disable; do
            log "Stopping and disabling service: $service"
            if systemctl stop "$service" && systemctl disable "$service"; then
                log "Service $service has been stopped and disabled successfully."
            else
                log "Failed to stop or disable service: $service"
            fi
        done
    else
        log "No services selected for disabling."
    fi
}

# Updates the SSH daemon configuration to listen on a new port and disables root user login.
# Set the immutable flag on the SSH configuration file, moves the default chattr file to /var/log/chatol, and creates a script to replace it.
update_sshd_config() {

    if [ ! -f "$SSHD_CONFIG" ]; then
        log "SSH configuration file not found at $SSHD_CONFIG."
        exit 1
    fi

    if ! sed -i '/^#[ \t]*Port /s/^#//' "$SSHD_CONFIG" || ! sed -i "/^Port /c\\Port $NEW_SSH_PORT" "$SSHD_CONFIG"; then
        log "Failed to modify Port line in $SSHD_CONFIG."
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
        log "Failed to restart SSH service."
        exit 1
    fi
    log "sshd has been configured to listen on port $NEW_SSH_PORT and disabled root user login."

    # Set the immutable flag on the SSH configuration file
    if chattr +i "$SSHD_CONFIG"; then
        log "Immutable flag set on $SSHD_CONFIG."
    else
        log "Failed to set immutable flag on $SSHD_CONFIG."
        exit 1
    fi

    # Move the default chattr file to /var/log/chatol
    if mv /usr/bin/chattr /var/log/chatol; then
        log "Default chattr file moved to /var/log/chatol."
    else
        log "Failed to move default chattr file to /var/log/chatol."
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

# Converts an IP range into individual IPs and outputs them.
ip_range_to_ips() {
    IFS='-' read -r start end <<< "$1"
    IFS='.' read -r s1 s2 s3 s4 <<< "$start"
    IFS='.' read -r e1 e2 e3 e4 <<< "$end"
    
    start_dec=$(($s1 * 16777216 + $s2 * 65536 + $s3 * 256 + $s4))
    end_dec=$(($e1 * 16777216 + $e2 * 65536 + $e3 * 256 + $e4))

    for ip_dec in $(seq $start_dec $end_dec); do
        # Convert integers back to IP addresses
        echo "$((ip_dec >> 24 & 255)).$((ip_dec >> 16 & 255)).$((ip_dec >> 8 & 255)).$((ip_dec & 255))"
    done
}

# Configures the firewall using either ufw or iptables, depending on what is available.
configure_firewall() {
    if command -v ufw >/dev/null 2>&1; then
        # Configuring firewall with ufw
        log "Configuring firewall with ufw..."
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing

        # Allow new SSH port globally
        ufw allow $NEW_SSH_PORT comment 'Global SSH access'
        log "Allowed global access on the new SSH port $NEW_SSH_PORT"

        # Process firewall rules from a file
        while IFS=' ' read -r ip_or_range port; do
            if [[ "$ip_or_range" == *-* ]]; then
                # Expand IP ranges into individual IPs for ufw
                for ip in $(ip_range_to_ips "$ip_or_range"); do
                    ufw allow from "$ip" to any port $port comment 'Range Specified port'
                    log "Allowed $ip on port $port"
                done
            else
                # Handle single IP/CIDR
                ufw allow from "$ip_or_range" to any port $port comment 'Specified port'
                log "Allowed $ip_or_range on port $port"
            fi
        done < "$INPUT_FILE"
        ufw --force enable
        log "UFW rules have been updated based on $INPUT_FILE."
    elif command -v iptables >/dev/null 2>&1; then
        log "Configuring firewall with iptables..."
        # Flush existing rules
        iptables -F
        # Set default policies
        iptables -P INPUT DROP
        iptables -P FORWARD DROP
        iptables -P OUTPUT ACCEPT

        # Allow SSH on the new port globally
        iptables -A INPUT -p tcp --dport $NEW_SSH_PORT -j ACCEPT
        log "Allowed global access on the new SSH port $NEW_SSH_PORT"

        # Process firewall rules from a file
        while IFS=' ' read -r ip_or_range port; do
            if [[ "$ip_or_range" == *-* ]]; then
                # Handle IP ranges using CIDR notation for iptables
                iptables -A INPUT -p tcp -m iprange --src-range $ip_or_range --dport $port -j ACCEPT
                log "Allowed $ip_or_range on port $port"
            else
                # Handle single IP/CIDR
                iptables -A INPUT -p tcp -s "$ip_or_range" --dport $port -j ACCEPT
                log "Allowed $ip_or_range on port $port"
            fi
        done < "$INPUT_FILE"
        log "iptables rules have been updated based on $INPUT_FILE."
    else
        log "No known firewall (ufw or iptables) is active on this system."
    fi
}

# Generates the croncheck.sh file
generate_croncheck_script() {
    cat > croncheck.sh <<EOL
#!/bin/bash

# Check if the script is run as root
if [ "\$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

# Define the backup user
BACKUP_USER="$BACKUP_USER"

# Check if the backup user exists
if ! id "\$BACKUP_USER" >/dev/null 2>&1; then
  echo "Backup user \$BACKUP_USER does not exist"
  exit 1
fi

# Check if the backup user has sudo access
if ! sudo -l -U "\$BACKUP_USER" >/dev/null 2>&1; then
  echo "Backup user \$BACKUP_USER does not have sudo access"
  exit 1
fi

# Check if the SSH configuration file is unchanged
SSH_CONFIG="$SSHD_CONFIG"
if [ "\$(sudo lsattr \$SSH_CONFIG 2>/dev/null)" != "----i---------e--, \$SSH_CONFIG" ]; then
  echo "SSH configuration file has been modified"
  exit 1
fi

# Check if the firewall rules are unchanged
if command -v ufw >/dev/null 2>&1 && ufw status | grep -qw "active"; then
  # Check UFW rules
  if ! ufw status numbered | grep -qw "$NEW_SSH_PORT"; then
    echo "UFW rules have been modified"
    exit 1
  fi
elif command -v iptables >/dev/null 2>&1; then
  # Check iptables rules
  if ! iptables -L INPUT --line-numbers | grep -q "tcp dpt:$NEW_SSH_PORT"; then
    echo "iptables rules have been modified"
    exit 1
  fi
else
  echo "No known firewall (ufw or iptables) is active on this system"
  exit 1
fi

echo "All checks passed successfully"
exit 0
EOL

    chmod +x croncheck.sh
    log "croncheck.sh script generated successfully."
}

# Generates the cronline.txt file
generate_cronline_file() {
    cat > cronline.txt <<EOL
0 * * * * $(pwd)/croncheck.sh || echo "\$(date): Script execution failed" >> /var/log/croncheck_failure.log
EOL

    log "cronline.txt file generated successfully."
}

# Log processes and their associated executables
log_processes() {
    log "Logging processes and their associated executables"
    sudo ls -l /proc/[0-9]*/exe 2>/dev/null | awk '/ -> / && !/\/usr\/(lib(exec)?|s?bin)\// {print $9, $10, $11}' | sed 's,/proc/\([0-9]*\)/exe,\1,' | tee -a /var/log/process_executables.log
}

# Main function to execute the script
main() {
    check_run_as_root
    validate_parameters "$@"
    EXCLUDE_USER=$1
    if [ $# -eq 2 ]; then
        LOG_FILE=$2
    else
        LOG_FILE=$DEFAULT_LOG_FILE
    fi
    exec > >(tee -a "$LOG_FILE") 2>&1  # Redirect output to the specified or default log file
    NEW_SSH_PORT=2298  # Define your SSH port here
    INPUT_FILE="allowed_ips.txt"  # Define your input file name here
    validate_ssh_port "$NEW_SSH_PORT"
    SSHD_CONFIG="/etc/ssh/ssh_config"
    setup_passwords
    log_processes  # Log processes before making changes
    process_users
    create_backup_user
    update_sshd_config
    manage_services
    configure_firewall
    generate_croncheck_script
    generate_cronline_file
    log "Operations complete for all users except $EXCLUDE_USER, $BACKUP_USER, and root."

    log_processes  # Log processes after making changes
}

main "$@"
