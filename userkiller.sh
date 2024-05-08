#!/bin/bash

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
 echo "This script must be run as root"
 exit 1
fi

# Check if a username is provided
if [ -z "$1" ]; then
 echo "Usage: $0 <username_to_exclude>"
 exit 1
fi

# The username to exclude and root
EXCLUDE_USER=$1

# Generate a default password or allow a secure password input
read -sp "Enter new password for users: " NEW_PASSWORD
echo

# Get all users with login shells who are not the excluded user and not root
USERS=$(awk -v exclude="$EXCLUDE_USER" -F: '$7 ~ /(bash|sh)$/ && $1 != exclude && $1 != "root" {print $1}' /etc/passwd)

# Loop through all users, log them out, kill their processes, clear cron jobs, and change their password
for USER in $USERS; do
 echo "Processing user $USER"

 # Killing user processes
 echo "Killing all processes for $USER"
 pkill -u $USER

 # Clearing user cron jobs
 echo "Clearing cron jobs for $USER"
 crontab -r -u $USER

 # Changing password
 echo "Changing password for $USER"
 echo "$USER:$NEW_PASSWORD" | chpasswd
done

# Part 1: Update SSHD to listen on port 98
# Uncomment the Port line if it is commented
sed -i 's/^#[ \t]*\(Port .*\)/\1/' $SSH_CONFIG
sed -i '/^Port /c\Port 98' /etc/ssh/sshd_config
systemctl restart sshd.service
echo "SSHD has been configured to listen on port 98."

INPUT_FILE="allowed_ips.txt"  # Change this to the path of your input file

# Part 2: Configure firewall rules
# Function to apply changes using ufw
apply_ufw_changes() {
 echo "Applying changes with ufw..."
 ufw status verbose
 ufw --force reset  # Reset rules to ensure a clean slate
 # Set default policies
 ufw default deny incoming
 ufw default allow outgoing
 # Allow connections on the new SSH port from specified IPs
 while IFS= read -r ip; do
  ufw allow from "$ip" to any port $NEW_SSH_PORT comment 'Allowed SSH'
  echo "Allowed $ip on port $NEW_SSH_PORT"
 done < "$INPUT_FILE"
 # Enable the firewall
 ufw --force enable
 echo "UFW rules have been updated based on $INPUT_FILE."
}
# Function to apply changes using iptables
apply_iptables_changes() {
 echo "Applying changes with iptables..."
 iptables -L
 
 # Flush existing iptables rules
 iptables -F
 iptables -X

 # Set default chain policies
 iptables -P INPUT DROP
 iptables -P FORWARD DROP
 iptables -P OUTPUT ACCEPT

 # Allow localhost
 iptables -A INPUT -i lo -j ACCEPT
 iptables -A OUTPUT -o lo -j ACCEPT

 # Allow existing connections to continue
 iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

 # Read from the file and add rules
 while IFS=' ' read -r ip port; do
    iptables -A INPUT -p tcp -s "$ip" --dport "$port" -j ACCEPT
    echo "Allowed $ip on port $port"
 done < "$INPUT_FILE"
 echo "IPTables rules have been updated based on $INPUT_FILE."
 # Drop all other inbound traffic
 iptables -A INPUT -j DROP
}

# Check if ufw is installed and enabled
if command -v ufw >/dev/null 2>&1 && ufw status | grep -qw "active"; then
 apply_ufw_changes
elif command -v iptables >/dev/null 2>&1; then
 apply_iptables_changes
else
 echo "No known firewall (ufw or iptables) is active on this system."
fi

# Add the immutable flag to the sshd config file
sudo chattr +i /etc/ssh/ssh_config
echo "Immutable flag set on /etc/ssh/ssh_config to prevent modifications."

# Move the original chattr to a new location and rename it
sudo mv /usr/bin/chattr /var/log/chattrno

# Create a fake chattr script
echo '#!/bin/bash' | sudo tee /usr/bin/chattr > /dev/null
echo 'echo "Denied... Try again later..."' | sudo tee -a /usr/bin/chattr > /dev/null
# Make the new fake chattr executable
sudo chmod +x /usr/bin/chattr
echo "Chattr has been secured and replaced with a fake script."

echo "Operations complete for all users except $EXCLUDE_USER and root."
echo "Exiting..."