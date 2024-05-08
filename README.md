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
- Creates a backup admin user with sudo access for emergency purposes
- Performs periodic checks to ensure the system remains hardened

## Scripts

### userkiller.sh

This script is the main hardening script that performs the following tasks:
- Logs out all users (except the specified user and root) and kills their processes
- Clears cron jobs for all users (except the specified user and root)
- Changes passwords for all users (except the specified user and root)
- Updates the SSH daemon (sshd) to listen on port 98
- Configures firewall rules using UFW or iptables based on the `allowed_ips.txt` file
- Adds the immutable flag to the sshd configuration file
- Secures the `chattr` command by moving the original binary and replacing it with a fake script
- Creates a backup admin user with sudo access
- Outputs the excluded username and backup username to the `excluded_usernames.txt` file

### croncheck.sh

This script is designed to be run periodically via cron to ensure that the system remains hardened. It performs the following checks:
- Verifies that the backup admin user exists and has sudo access
- Checks if the SSH configuration file is unchanged and has the immutable flag set
- Checks if the firewall rules are unchanged based on the defined rules (port 98)

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

## Configuration

- The `allowed_ips.txt` file should contain the allowed IP addresses and ports for SSH access.
- Modify the text of `cronline.txt` file to specify the desired frequency and path for running the `croncheck.sh` script before installing it in your own `crontab`.

## Disclaimer

These scripts are provided as-is and should be used with caution. It is recommended to test the scripts in a non-production environment before applying them to critical systems. The scripts make significant changes to user accounts, processes, and system configurations, so ensure that you have appropriate backups and understand the implications of running the scripts.

## License

This project is released under the [MIT License](https://opensource.org/licenses/MIT).