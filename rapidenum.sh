#!/bin/bash

# Constants
DEFAULT_OUTPUT_DIR="./HostServices"
DEFAULT_MAX_RATE=1000
DEFAULT_TIMEOUT=600

# Function to display usage information
usage() {
    echo "Usage: $0 [-d output_directory] [-s service1,service2,...] [-r rate] [-t timeout] network_range"
    echo "  -d output_directory  Specify the output directory for scan results (default: $DEFAULT_OUTPUT_DIR)"
    echo "  -s service1,service2,...  Specify the services to scan (default: all services)"
    echo "  -r rate  Specify the maximum packet rate (default: $DEFAULT_MAX_RATE)"
    echo "  -t timeout  Specify the timeout in seconds for each host (default: $DEFAULT_TIMEOUT)"
    echo "  network_range  The network range to scan (e.g., 10.1.1.0/24)"
}

# Function to log messages with timestamps
log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $message"
}

# Parse command-line arguments
output_dir="$DEFAULT_OUTPUT_DIR"
services=()
max_rate="$DEFAULT_MAX_RATE"
timeout="$DEFAULT_TIMEOUT"

while getopts ":d:s:r:t:" opt; do
    case $opt in
        d) output_dir="$OPTARG" ;;
        s) IFS=',' read -ra services <<< "$OPTARG" ;;
        r) max_rate="$OPTARG" ;;
        t) timeout="$OPTARG" ;;
        \?) log "Error: Invalid option -$OPTARG"; usage; exit 1 ;;
        :) log "Error: Option -$OPTARG requires an argument"; usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))

if [[ $# -ne 1 ]]; then
    usage
    exit 1
fi

network_range="$1"

# Check if Nmap is installed
if ! command -v nmap &>/dev/null; then
    log "Error: Nmap is not installed. Please install Nmap and try again."
    exit 1
fi

# Create the output directory if it doesn't exist
mkdir -p "$output_dir"

# Define the services and their corresponding ports
declare -A services_tcp=(
    ["ftp"]=21
    ["ssh"]=22
    ["telnet"]=23
    ["smtp"]=25
    ["dns"]=53
    ["http"]=80
    ["pop3"]=110
    ["imap"]=143
    ["https"]=443
    ["smb"]=445
    ["mssql"]=1433
    ["oracle"]=1521
    ["mysql"]=3306
    ["rdp"]=3389
    ["postgresql"]=5432
    ["vnc"]=5900
    ["http-alt"]=8080
    ["https-alt"]=8443
    ["smtps"]=465
    ["imaps"]=993
    ["pop3s"]=995
    ["mongodb"]=27017
    ["socks"]=1080
    ["squid"]=3128
    ["rpcbind"]=111
    ["pptp"]=1723
)

declare -A services_udp=(
    ["dns"]=53
    ["dhcp-server"]=67
    ["dhcp-client"]=68
    ["tftp"]=69
    ["snmp"]=161
    ["ntp"]=123
    ["ldap"]=389
    ["ws-discovery"]=3389
    ["nfs"]=2049
)

# Perform a ping sweep to identify live hosts
log "Performing ping sweep on $network_range"
live_hosts=$(nmap -sn --min-rate "$max_rate" --max-retries 1 --max-rtt-timeout 100ms "$network_range" | awk '/is up/{print $2}')

# Perform scans for selected services on live hosts
for service in "${services[@]:-${!services_tcp[@]} ${!services_udp[@]}}"; do
    if [[ -v "services_tcp[$service]" ]]; then
        port="${services_tcp[$service]}"
        protocol="TCP"
    elif [[ -v "services_udp[$service]" ]]; then
        port="${services_udp[$service]}"
        protocol="UDP"
    else
        log "Warning: Unknown service $service"
        continue
    fi

    log "Scanning for $service ($protocol port $port) on live hosts"
    output_file="$output_dir/${service}_hosts.txt"

    if [[ "$protocol" == "TCP" ]]; then
        nmap -sV --min-rate "$max_rate" --max-retries 2 --host-timeout "${timeout}s" -p "$port" --open -oG - "$live_hosts" | awk '/Status: Open/{print $2}' > "$output_file"
    else
        nmap -sU -sV --min-rate "$max_rate" --max-retries 2 --host-timeout "${timeout}s" -p "$port" --open -oG - "$live_hosts" | awk '/Status: Open/{print $2}' > "$output_file"
    fi

    log "Scan results saved to $output_file"
    log "Number of live hosts with $service open: $(wc -l < "$output_file")"
    log "---"
done