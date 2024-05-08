# Linux System Hardening Scripts

This repository contains a set of scripts designed to harden Linux systems, particularly for competitions, by performing a series of security-focused tasks. It is intended to be used by blue teams to lock down a system and enhance its security posture.

![a-captivating-3d-render-illustration-of-a-fortifie-p-ujbcuIQmiC5cFKNzGclg-SaUKsmqTQTWg8K9Vjn6gxA](https://github.com/fulco/BlueLinuxBastion/assets/802660/52bd88c5-a985-4ed2-af29-9698733b0198)

## Scripts

### userkiller.sh

This script is the main hardening script that performs the following tasks:
- Logs out all users (except the specified user and root) and kills their processes
- Clears cron jobs for all users (except the specified user and root)
- Changes passwords for all users (except the specified user and root)
- Updates the SSH daemon (sshd) to listen on a custom port (defined by `$NEW_SSH_PORT`)
- Configures firewall rules using UFW (Uncomplicated Firewall) or iptables based on a specified input file
- Adds the immutable flag to the sshd configuration file to prevent modifications
- Secures the `chattr` command by moving the original binary and replacing it with a fake script
- Creates a backup admin user with sudo access for emergency purposes
- Logs script actions to a file for future reference and troubleshooting

### croncheck.sh

This script is designed to be run periodically via cron to ensure that the system remains hardened. It performs the following checks:
- Verifies that the backup admin user exists and has sudo access
- Checks if the SSH configuration file is unchanged and has the immutable flag set
- Checks if the firewall rules are unchanged based on the defined rules (port specified by `$NEW_SSH_PORT`)

### cronline.txt

This file contains an example cron entry to run the `croncheck.sh` script periodically and log any failures to the `/var/log/script_failure.log` file.

## Usage

1. Clone the repository or download the script files.
2. Make the scripts executable using the command: `chmod +x userkiller.sh croncheck.sh`.
3. Run the `userkiller.sh` script with root privileges and provide the username to exclude as an argument:
   ```
   sudo ./userkiller.sh <username_to_exclude>
   ```
4. Enter the new password for the users when prompted.
5. The script will perform the hardening tasks and display relevant information.
6. Set up a cron job to run the `croncheck.sh` script periodically to ensure the system remains hardened. Modify the `cronline.txt` file with the appropriate path to the script and add it to your crontab.

## Prerequisites

- The scripts must be run with root privileges.
- The system should have either UFW or iptables installed for configuring firewall rules.
- An input file (`allowed_ips.txt`) should be created, containing the allowed IP addresses and ports for SSH access.

## Configuration

- The `allowed_ips.txt` file should contain the allowed IP addresses and ports for access in this format:
   ```
   192.168.1.23 98
   192.168.1.45 8080
   ```
- The `userkiller.sh` script sets the SSH port using the `$NEW_SSH_PORT` variable. By default, it is set to 98. If needed, you can modify the value of `$NEW_SSH_PORT` in the script.
- The `userkiller.sh` script logs its actions to the `/var/log/userkiller.log` file. You can change the log file path by modifying the `exec` command at the beginning of the script.
- Modify the command contained in the `cronline.txt` file to specify the desired frequency and path for running the `croncheck.sh` script and install to the root crontab.

## Password Complexity

It is recommended to enforce strong password complexity requirements when setting new passwords for users. You can modify the `userkiller.sh` script to include password validation checks to ensure that the `$NEW_PASSWORD` meets the desired complexity criteria.

## Logging

The `userkiller.sh` script logs its actions to the `/var/log/userkiller.log` file. Each log entry includes a timestamp to track when each action was performed. You can review this log file for troubleshooting and auditing purposes.

The `croncheck.sh` script logs any failures to the `/var/log/script_failure.log` file, as specified in the `cronline.txt` file. Each failure entry includes a timestamp and an indication that the script execution failed.

## Disclaimer

These scripts are provided as-is and should be used with caution. It is recommended to test the scripts in a non-production environment before applying them to critical systems. The scripts make significant changes to user accounts, processes, and system configurations, so ensure that you have appropriate backups and understand the implications of running the scripts.

## License

This project is released under the [MIT License](https://opensource.org/licenses/MIT).
