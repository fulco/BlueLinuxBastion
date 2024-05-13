#!/bin/bash

# Constants
readonly NEW_SSH_PORT=2298
readonly ALLOWED_CONNECTIONS_FILE="allowed_ips.txt"
readonly LOG_FILE="/var/log/conchecker.log"

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

# Validate the provided username parameter
if [[ $# -ne 1 ]]; then
    log "Error: Please provide exactly one username as an argument."
    log "Usage: $0 <username_to_exclude>"
    exit 1
fi

readonly CURRENT_USER="$1"

# Verify the allowed_ips.txt file
if [[ ! -f "$ALLOWED_CONNECTIONS_FILE" || ! -s "$ALLOWED_CONNECTIONS_FILE" ]]; then
    log "Error: The allowed_ips.txt file does not exist or is empty."
    log "Please create the file and add allowed IP addresses, one per line."
    exit 1
fi

# Function to check for the availability of firewall tools
get_firewall_tool() {
    if command -v ufw &> /dev/null; then
        echo "ufw"
    elif command -v iptables &> /dev/null; then
        echo "iptables"
    else
        echo "none"
    fi
}

# Function to add firewall rules
add_firewall_rule() {
    local local_ip="$1"
    local remote_ip="$2"
    local tool="$3"

    case "$tool" in
        "ufw")
            ufw deny from "$remote_ip" to "$local_ip"
            log "Firewall rule added using ufw to block $remote_ip to $local_ip"
            ;;
        "iptables")
            iptables -A INPUT -s "$remote_ip" -d "$local_ip" -j DROP
            log "Firewall rule added using iptables to block $remote_ip to $local_ip"
            ;;
        *)
            log "No firewall tool available to add rule."
            ;;
    esac
}

# Function to kill a process by PID
kill_process() {
    local pid="$1"
    local signal="$2"
    kill "-$signal" "$pid"
    log "Process with PID $pid killed with signal $signal"
}

# Main function to check connections
check_connections() {
    local current_ssh_connection
    current_ssh_connection=$(who | awk -v user="$CURRENT_USER" '$1 == user {print $NF}' | sed 's/[()]//g')

    local firewall_tool
    firewall_tool=$(get_firewall_tool)

    log "Starting connection checks..."

    while read -r line; do
        local local_ip remote_ip pid_program program_name local_port

        if [[ "$line" =~ ^tcp.*ESTABLISHED$ ]]; then
            local_ip=$(echo "$line" | awk '{print $4}')
            remote_ip=$(echo "$line" | awk '{print $5}')
            pid_program=$(echo "$line" | awk '{print $7}' | awk -F'/' '{print $1}')
            program_name=$(echo "$line" | awk '{print $7}' | awk -F'/' '{print $2}')
            local_port=$(echo "$local_ip" | awk -F':' '{print $NF}')

            # Skip the connection if it belongs to the current user's SSH connection
            if [[ "$program_name" == "sshd" && "$remote_ip" == *"$current_ssh_connection"* ]]; then
                continue
            fi

            # Check if the connection is allowed based on the allowed_ips.txt file or if the local port matches NEW_SSH_PORT
            if ! grep -qE "^$remote_ip\s+$local_port$" "$ALLOWED_CONNECTIONS_FILE" && [[ $local_port -ne $NEW_SSH_PORT ]]; then
                log "Unauthorized connection: $local_ip <-> $remote_ip (Process: $program_name, PID: $pid_program)"

                # Prompt the user to kill the unauthorized process
                read -r -p "Do you want to kill this process? (yes/no) " answer_kill
                if [[ "$answer_kill" =~ ^(yes|y)$ ]]; then
                    log "User chose to kill the process with PID $pid_program"
                    kill_process "$pid_program" "15"
                    sleep 5
                    if ps -p "$pid_program" > /dev/null; then
                        log "Process with PID $pid_program is still running after SIGTERM, sending SIGKILL"
                        kill_process "$pid_program" "9"
                    fi
                else
                    log "User chose not to kill the process with PID $pid_program"
                fi

                # Prompt the user to add a firewall rule to block the unauthorized connection
                read -r -p "Do you want to block this connection using firewall? (yes/no) " answer_firewall
                if [[ "$answer_firewall" =~ ^(yes|y)$ ]]; then
                    log "User chose to block the connection from $remote_ip to $local_ip using $firewall_tool"
                    add_firewall_rule "$local_ip" "$remote_ip" "$firewall_tool"
                else
                    log "User chose not to block the connection from $remote_ip to $local_ip"
                fi
            fi
        fi
    done < <(netstat -antp 2>/dev/null)

    log "Connection checks completed."
}

# Running the main function
check_connections
