# BlueLinuxBastion

This script is designed to harden Linux systems, particularly for competitions, by performing a series of security-focused tasks. It is intended to be used by blue teams to lock down a system and enhance its security posture.

## Features

- Logs out all users (except the specified user and root) and kills their processes
- Clears cron jobs for all users (except the specified user and root)
- Changes passwords for all users (except the specified user and root)
- Updates the SSH daemon (sshd) to listen on a custom port (98)
- Configures firewall rules using UFW (Uncomplicated Firewall) or iptables based on a specified input file
- Adds the immutable flag to the sshd configuration file to prevent modifications
- Secures the `chattr` command by moving the original binary and replacing it with a fake script

## Usage

1. Clone the repository or download the script file.
2. Make the script executable using the command: `chmod +x script_name.sh`.
3. Run the script with root privileges and provide the username to exclude as an argument:
   ```
   sudo ./script_name.sh <username_to_exclude>
   ```
4. Enter the new password for the users when prompted.
5. The script will perform the hardening tasks and display relevant information.

## Prerequisites

- The script must be run with root privileges.
- The system should have either UFW or iptables installed for configuring firewall rules.
- An input file (`allowed_ips.txt`) should be created, containing the allowed IP addresses and ports for SSH access.

## Configuration

- The script uses the `allowed_ips.txt` file to configure firewall rules. Modify this file to include the desired IP addresses and ports for SSH access.
- The script sets the SSH port to 98. If needed, you can modify the `NEW_SSH_PORT` variable in the script to use a different port.

## Disclaimer

This script is provided as-is and should be used with caution. It is recommended to test the script in a non-production environment before applying it to critical systems. The script makes significant changes to user accounts, processes, and system configurations, so ensure that you have appropriate backups and understand the implications of running the script.

## License

This script is released under the [MIT License](https://opensource.org/licenses/MIT).