#!/bin/bash

# Redirects all output to a log file while also displaying it on the console.
exec > >(tee -a /var/log/conchecker.log) 2>&1

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

# Validates that a username is provided as a parameter.
validate_parameters() {
    if [ -z "$1" ]; then
        log "Usage: $0 <username_to_exclude>"
        exit 1
    fi
}

# Verify the allowed_ips.txt file
verify_allowed_ips_file() {
    if [ ! -f "$ALLOWED_CONNECTIONS_FILE" ]; then
        log "The allowed_ips.txt file does not exist."
        log "Please create the file and add allowed IP addresses, one per line."
        exit 1
    fi

    if [ ! -s "$ALLOWED_CONNECTIONS_FILE" ]; then
        log "The allowed_ips.txt file is empty."
        log "Please add allowed IP addresses to the file, one per line."
        exit 1
    fi
}

# Validates that exactly one argument is provided.
if [ $# -ne 1 ]; then
    log "Incorrect usage. Please provide exactly one username as an argument."
    log "Usage: $0 <username_to_exclude>"
    exit 1
fi

# Constants
NEW_SSH_PORT=2298  # Define your SSH port here
ALLOWED_CONNECTIONS_FILE="allowed_ips.txt"
CURRENT_USER=$1

# Check if the script is run as root
check_run_as_root

# Validate the provided username parameter
validate_parameters "$CURRENT_USER"

# Verify the allowed_ips.txt file
verify_allowed_ips_file

# Function to check for the availability of firewall tools
check_firewall_tool() {
    if command -v ufw > /dev/null; then
        echo "ufw"
    elif command -v iptables > /dev/null; then
        echo "iptables"
    else
        echo "none"
    fi
}

# Function to add firewall rules
add_firewall_rule() {
    local local_ip=$1
    local remote_ip=$2
    local tool=$3

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
    local pid=$1
    local signal=$2
    kill "-$signal" "$pid"
    log "Process with PID $pid killed with signal $signal"
}

# Main function to check connections
check_connections() {
   local current_ssh_connection
   current_ssh_connection=$(who | awk -v user="$CURRENT_USER" '$1 == user {print $NF}' | sed 's/[()]//g')
   
   local firewall_tool
   firewall_tool=$(check_firewall_tool)

   log "Starting connection checks..."

   netstat -antp | grep 'tcp' | while read -r line; do
       local local_ip
       local_ip=$(echo "$line" | awk '{print $4}')
       
       local remote_ip
       remote_ip=$(echo "$line" | awk '{print $5}')
       
       local pid_program
       pid_program=$(echo "$line" | awk '{print $7}' | awk -F'/' '{print $1}')
       
       local program_name
       program_name=$(echo "$line" | awk '{print $7}' | awk -F'/' '{print $2}')

       # ... (connection checking logic remains the same)

       # Check if the connection is allowed based on the allowed_ips.txt file
       if ! grep -q "$local_ip $remote_ip" "$ALLOWED_CONNECTIONS_FILE"; then
           log "Unauthorized connection: $local_ip <-> $remote_ip (Process: $program_name, PID: $pid_program)"

           # Prompt the user to kill the unauthorized process
           local answer_kill
           read -r -p "Would you like to kill this process? (yes/no) " answer_kill
           if [[ "$answer_kill" == "yes" ]]; then
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
           local answer_firewall
           read -r -p "Would you like to block this connection using firewall? (yes/no) " answer_firewall
           if [[ "$answer_firewall" == "yes" ]]; then
               log "User chose to block the connection from $remote_ip to $local_ip using $firewall_tool"
               add_firewall_rule "$local_ip" "$remote_ip" "$firewall_tool"
           else
               log "User chose not to block the connection from $remote_ip to $local_ip"
           fi
       fi
   done

   log "Connection checks completed."
}

# Running the main function
check_connections
