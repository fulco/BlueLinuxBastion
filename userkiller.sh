#!/bin/bash

exec > >(tee -a /var/log/userkiller.log) 2>&1

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "$(date): This script must be run as root"
  exit 1
fi

# Check if a username is provided
if [ -z "$1" ]; then
  echo "$(date): Usage: $0 <username_to_exclude>"
  exit 1
fi

# The username to exclude and root
EXCLUDE_USER=$1
SSH_CONFIG="/etc/ssh/ssh_config"
NEW_SSH_PORT=98

if ! [[ "$NEW_SSH_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_SSH_PORT" -lt 1 ] || [ "$NEW_SSH_PORT" -gt 65535 ]; then
  echo "$(date): Invalid SSH port number: $NEW_SSH_PORT"
  exit 1
fi

# Generate a default password or allow a secure password input
read -sp "Enter new password for users: " NEW_PASSWORD
echo

INPUT_FILE_DIR="./"
# Define the input file and username output file
INPUT_FILE="allowed_ips.txt"
USERNAME_FILE="excluded_usernames.txt"

if [ ! -r "$INPUT_FILE" ]; then
  echo "$(date): Input file $INPUT_FILE does not exist or is not readable"
  exit 1
fi

# Get all users with login shells who are not the excluded user and not root
USERS=$(awk -v exclude="$EXCLUDE_USER" -F: '$7 ~ /(bash|sh)$/ && $1 != exclude && $1 != "root" {print $1}' /etc/passwd)

# Loop through all users, log them out, kill their processes, clear cron jobs, and change their password
for USER in $USERS; do
  echo "$(date): Processing user $USER"

  # Killing user processes
  echo "$(date): Killing all processes for $USER"
  pkill -u $USER

  # Clearing user cron jobs
  echo "$(date): Clearing cron jobs for $USER"
  crontab -r -u $USER

  # Changing password
  echo "$(date): Changing password for $USER"
  echo "$USER:$NEW_PASSWORD" | chpasswd
done

# Create a backup user for emergency access
BACKUP_USER="backup_admin"
if ! useradd -m -s /bin/bash "$BACKUP_USER"; then
  echo "$(date): Failed to create backup user $BACKUP_USER"
  exit 1
fi

if ! echo "$BACKUP_USER:$NEW_PASSWORD" | chpasswd; then
  echo "$(date): Failed to set password for backup user $BACKUP_USER"
  exit 1
fi

if ! usermod -aG sudo "$BACKUP_USER"; then
  echo "$(date): Failed to add backup user $BACKUP_USER to sudo group"
  exit 1
fi
echo "$(date): Backup user $BACKUP_USER created with sudo access"

# Output the excluded username and backup username to the file
echo "Excluded username: $EXCLUDE_USER" > "$INPUT_FILE_DIR/$USERNAME_FILE"
echo "Backup username: $BACKUP_USER" >> "$INPUT_FILE_DIR/$USERNAME_FILE"

# Part 1: Update sshd to listen on the defined port
# Uncomment the Port line if it is commented
sed -i 's/^#[ \t]*\(Port .*\)/\1/' /etc/ssh/ssh_config
sed -i "/^Port /c\\Port $NEW_SSH_PORT" /etc/ssh/ssh_config
systemctl restart sshd.service
echo "$(date): sshd has been configured to listen on port $NEW_SSH_PORT."

# Part 2: Configure firewall rules
# Function to apply changes using ufw
apply_ufw_changes() {
  echo "$(date): Applying changes with ufw..."
  ufw status verbose
  ufw --force reset  # Reset rules to ensure a clean slate
  
  # Set default policies
  ufw default deny incoming
  ufw default allow outgoing
  
  # Allow connections on the new SSH port from specified IPs
  while IFS= read -r ip; do
    ufw allow from "$ip" to any port $NEW_SSH_PORT comment 'Allowed SSH'
    echo "$(date): Allowed $ip on port $NEW_SSH_PORT"
  done < "$INPUT_FILE"
  
  # Enable the firewall
  ufw --force enable
  echo "$(date): UFW rules have been updated based on $INPUT_FILE."
}

# Function to apply changes using iptables
apply_iptables_changes() {
  echo "$(date): Applying changes with iptables..."
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
    echo "$(date): Allowed $ip on port $port"
  done < "$INPUT_FILE"
  
  echo "$(date): IPTables rules have been updated based on $INPUT_FILE."
  
  # Drop all other inbound traffic
  iptables -A INPUT -j DROP
}

# Check if ufw is installed and enabled
if command -v ufw >/dev/null 2>&1 && ufw status | grep -qw "active"; then
  apply_ufw_changes
elif command -v iptables >/dev/null 2>&1; then
  apply_iptables_changes
else
  echo "$(date): No known firewall (ufw or iptables) is active on this system."
fi

# Add the immutable flag to the sshd config file
sudo chattr +i /etc/ssh/ssh_config
echo "$(date): Immutable flag set on /etc/ssh/ssh_config to prevent modifications."

# Move the original chattr to a new location and rename it
sudo mv /usr/bin/chattr /var/log/chattrno

# Create a fake chattr script
echo '#!/bin/bash' | sudo tee /usr/bin/chattr > /dev/null
echo 'echo "Denied... Try again later..."' | sudo tee -a /usr/bin/chattr > /dev/null

# Make the new fake chattr executable
sudo chmod +x /usr/bin/chattr
echo "$(date): Chattr has been secured and replaced with a fake script."

echo "$(date): Operations complete for all users except $EXCLUDE_USER, $BACKUP_USER, and root."
echo "$(date): Exiting..."