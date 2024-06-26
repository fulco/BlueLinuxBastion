# Blue Linux Bastion: Linux System Hardening Scripts

This repository contains a set of scripts designed to enhance the security of Linux systems. These scripts are designed for blue teams during security competitions or for anyone looking to implement stringent security measures on their Linux systems. They are designed for my personal needs and may not meet your own.

![Image of the Bastion](https://github.com/fulco/BlueLinuxBastion/assets/802660/52bd88c5-a985-4ed2-af29-9698733b0198)

## Scripts Overview

### userkiller.sh

This script is the main hardening script that performs the following tasks:
- Logs out all users (except the specified user and root) and kills their processes
- Clears cron jobs for all users (except the specified user and root)
- Changes passwords for all users (except the specified user and root)
- Updates the SSH daemon (sshd) to listen on a custom port (defined by `$NEW_SSH_PORT`)
- Configures firewall rules using UFW (Uncomplicated Firewall) or iptables based on a specified input file
- Creates a backup admin user with sudo access for emergency purposes
- Logs script actions to a file for future reference and troubleshooting (default log file: `/var/log/userkiller.log`, can be changed with an optional argument)
- Generates the `croncheck.sh` script and `cronline.txt` file for periodic system checks
- Manages system services by displaying enabled and running services and allowing the user to selectively disable non-needed services
- Logs processes and their associated executables before and after making changes

### croncheck.sh

This script is generated by the `userkiller.sh` script and is designed to be run periodically via cron to ensure that the system remains hardened. It performs the following checks:
- Verifies that the backup admin user exists and has sudo access
- Checks if the SSH configuration file is unchanged and has the immutable flag set
- Checks if the firewall rules are unchanged based on the defined rules (port specified by `$NEW_SSH_PORT`)

### cronline.txt

This file is generated by the `userkiller.sh` script and contains a sample cron entry to run the `croncheck.sh` script periodically and log any failures to the `/var/log/croncheck_failure.log` file.

### conchecker.sh

The `conchecker.sh` script is designed to monitor network connections on the Linux system and identify unauthorized connections. It performs the following tasks:
- Retrieves the current user's SSH connection IP and excludes it from the checks
- Parses the output of `netstat -antp` to extract connection details
- Checks if each connection is allowed based on the `allowed_ips.txt` file
- If a connection is unauthorized:
  - Prompts the user to kill the associated process
  - Prompts the user to add a firewall rule to block the connection
- Logs detailed information about the script's actions with timestamps

### rapidenum.sh

The `rapidenum.sh` script is designed to perform more network scans (as may be of use during competitions) using Nmap to check for open ports associated with specific TCP and UDP services on a given network range. It includes various optimizations to speed up the scanning process:
- Parallelizes the scans by splitting the network range into smaller subsets
- Adjusts Nmap timing and performance options for faster scanning
- Limits the scanned ports based on prior knowledge of likely open ports
- Uses Nmap's ping sweep to identify live hosts before scanning for open ports
- Optimizes the script by removing unnecessary output and using efficient command-line tools

## Usage, Prerequisites, Configuration, and More

For detailed information on how to use these scripts, including prerequisites, configuration, troubleshooting, and more, please refer to the [Blue Linux Bastion Wiki](https://github.com/fulco/BlueLinuxBastion/wiki).

Note: The `$EUID` variable used in the scripts is a built-in shell variable in Bash that represents the effective user ID of the current user. It does not need to be explicitly defined in the script.

## Contributing

Contributions are welcome to enhance the scripts' functionality or documentation. Please fork the repository, make your changes, and submit a pull request for review.

## License

This project is released under the [MIT License](https://opensource.org/licenses/MIT).

## Disclaimer

These scripts are provided as-is and should be used with extreme caution. It is strongly recommended to thoroughly test the scripts in a non-production environment before applying them to critical systems. The scripts make significant changes to user accounts, processes, and system configurations, so ensure that you have appropriate backups and fully understand the implications of running the scripts.
