#!/bin/bash

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

# Define the backup user
BACKUP_USER="backup_admin"

# Check if the backup user exists
if id "$BACKUP_USER" >/dev/null 2>&1; then
  echo "Backup user $BACKUP_USER exists"
else
  echo "Backup user $BACKUP_USER does not exist"
  exit 1
fi

# Check if the backup user has sudo access
if sudo -l -U "$BACKUP_USER" >/dev/null 2>&1; then
  echo "Backup user $BACKUP_USER has sudo access"
else
  echo "Backup user $BACKUP_USER does not have sudo access"
  exit 1
fi

# Check if the SSH configuration file is unchanged
SSH_CONFIG="/etc/ssh/sshd_config"
if [ "$(sudo lsattr $SSH_CONFIG)" == "----i---------e-- $SSH_CONFIG" ]; then
  echo "SSH configuration file is unchanged"
else
  echo "SSH configuration file has been modified"
  exit 1
fi

# Check if the firewall rules are unchanged
if command -v ufw >/dev/null 2>&1 && ufw status | grep -qw "active"; then
  # Check UFW rules
  if ufw status numbered | grep -qw "98"; then
    echo "UFW rules are unchanged"
  else
    echo "UFW rules have been modified"
    exit 1
  fi
elif command -v iptables >/dev/null 2>&1; then
  # Check iptables rules
  if iptables -L INPUT --line-numbers | grep -q "tcp dpt:98"; then
    echo "iptables rules are unchanged"
  else
    echo "iptables rules have been modified"
    exit 1
  fi
else
  echo "No known firewall (ufw or iptables) is active on this system"
  exit 1
fi

echo "All checks passed successfully"
exit 0