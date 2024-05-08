#!/bin/bash

# Redirects all output to a log file while also displaying it on the console.
exec > >(tee -a /var/log/userkiller.log) 2>&1

# Checks if the script is run as root, exits if not.
check_run_as_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "$(date): This script must be run as root"
        exit 1
    fi
}

# Validates that a username is provided as a parameter.
validate_parameters() {
    if [ -z "$1" ]; then
        echo "$(date): Usage: $0 <username_to_exclude>"
        exit 1
    fi
}

# Validates that the SSH port is a number between 1024 and 65535.
validate_ssh_port() {
    if ! [[ "$NEW_SSH_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_SSH_PORT" -lt 1024 ] || [ "$NEW_SSH_PORT" -gt 65535 ]; then
        echo "$(date): Invalid SSH port number: $NEW_SSH_PORT. It must be between 1024 and 65535."
        exit 1
    fi
}

# Prompts the user for a new password and verifies it.
setup_passwords() {
    while true; do
        read -sp "Enter new password for users: " NEW_PASSWORD
        echo
        read -sp "Repeat new password: " REPEAT_PASSWORD
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
        echo "$(date): Processing user $USER"
        pkill -u $USER
        crontab -r -u $USER
        echo "$USER:$NEW_PASSWORD" | chpasswd
    done
}

# Creates a backup user with sudo privileges.
create_backup_user() {
    BACKUP_USER="backup_admin"
    if ! useradd -m -s /bin/bash "$BACKUP_USER" || ! echo "$BACKUP_USER:$NEW_PASSWORD" | chpasswd || ! usermod -aG sudo "$BACKUP_USER"; then
        echo "$(date): Failed to setup backup user $BACKUP_USER"
        exit 1
    fi
    echo "$(date): Backup user $BACKUP_USER created with sudo access"
}

# Updates the SSH daemon configuration to listen on a new port.
update_sshd_config() {
    SSHD_CONFIG="/etc/ssh/ssh_config"

    if [ ! -f "$SSHD_CONFIG" ]; then
        echo "$(date): SSH configuration file not found at $SSHD_CONFIG."
        exit 1
    fi

    if ! sed -i '/^#[ \t]*Port /s/^#//' "$SSHD_CONFIG" || ! sed -i "/^Port /c\\Port $NEW_SSH_PORT" "$SSHD_CONFIG"; then
        echo "$(date): Failed to modify Port line in $SSHD_CONFIG."
        exit 1
    fi

    if ! systemctl restart sshd.service; then
        echo "$(date): Failed to restart SSH service."
        exit 1
    fi
    echo "$(date): sshd has been configured to listen on port $NEW_SSH_PORT."
}

# Converts an IP range into individual IPs and outputs them.
ip_range_to_ips() {
    IFS='-' read -r start end <<< "$1"
    IFS='.' read -r s1 s2 s3 s4 <<< "$start"
    IFS='.' read -r e1 e2 e3 e4 <<< "$end"
    
    start_dec=$(($s1 * 16777216 + $s2 * 65536 + $s3 * 256 + $s4))
    end_dec=$(($e1 * 16777216 + $e2 * 65536 + $e3 * 256 + $e4))

    for ip_dec in $(seq $start_dec $end_dec); do
        echo "$((ip_dec >> 24 & 255)).$((ip_dec >> 16 & 255

        # Convert integers back to IP addresses
        echo "$((ip_dec >> 24 & 255)).$((ip_dec >> 16 & 255)).$((ip_dec >> 8 & 255)).$((ip_dec & 255))"
    done
}

# Configures the firewall using either ufw or iptables, depending on what is available.
configure_firewall() {
    if command -v ufw >/dev/null 2>&1; then
        # Configuring firewall with ufw
        echo "$(date): Configuring firewall with ufw..."
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing

        # Allow new SSH port globally
        ufw allow $NEW_SSH_PORT comment 'Global SSH access'
        echo "$(date): Allowed global access on the new SSH port $NEW_SSH_PORT"

        # Process firewall rules from a file
        while IFS=' ' read -r ip_or_range port; do
            if [[ "$ip_or_range" == *-* ]]; then
                # Expand IP ranges into individual IPs for ufw
                for ip in $(ip_range_to_ips "$ip_or_range"); do
                    ufw allow from "$ip" to any port $port comment 'Range Specified port'
                    echo "$(date): Allowed $ip on port $port"
                done
            else
                # Handle single IP/CIDR
                ufw allow from "$ip_or_range" to any port $port comment 'Specified port'
                echo "$(date): Allowed $ip_or_range on port $port"
            fi
        done < "$INPUT_FILE"
        ufw --force enable
        echo "$(date): UFW rules have been updated based on $INPUT_FILE."
        elif command -v iptables >/dev/null 2>&1; then
        echo "$(date): Configuring firewall with iptables..."
        # Flush existing rules
        iptables -F
        # Set default policies
        iptables -P INPUT DROP
        iptables -P FORWARD DROP
        iptables -P OUTPUT ACCEPT

        # Allow SSH on the new port globally
        iptables -A INPUT -p tcp --dport $NEW_SSH_PORT -j ACCEPT
        echo "$(date): Allowed global access on the new SSH port $NEW_SSH_PORT"

        # Process firewall rules from a file
        while IFS=' ' read -r ip_or_range port; do
            if [[ "$ip_or_range" == *-* ]]; then
                # Handle IP ranges using CIDR notation for iptables
                iptables -A INPUT -p tcp -m iprange --src-range $ip_or_range --dport $port -j ACCEPT
                echo "$(date): Allowed $ip_or_range on port $port"
            else
                # Handle single IP/CIDR
                iptables -A INPUT -p tcp -s "$ip_or_range" --dport $port -j ACCEPT
                echo "$(date): Allowed $ip_or_range on port $port"
            fi
        done < "$INPUT_FILE"
        echo "$(date): iptables rules have been updated based on $INPUT_FILE."
    else
        echo "$(date): No known firewall (ufw or iptables) is active on this system."
    fi
}

# Main function to execute the script
main() {
    check_run_as_root
    validate_parameters "$@"
    EXCLUDE_USER=$1
    NEW_SSH_PORT=2298  # Define your SSH port here
    INPUT_FILE="allowed_ips.txt"  # Define your input file name here
    setup_passwords
    process_users
    create_backup_user
    update_sshd_config
    configure_firewall
    echo "$(date): Operations complete for all users except $EXCLUDE_USER, $BACKUP_USER, and root."
}

main "$@"