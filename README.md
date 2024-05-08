# Blue Linux Bastion: Linux System Hardening Scripts

This repository contains a set of scripts designed to enhance the security of Linux systems. These scripts are ideal for blue teams during security competitions or for anyone looking to implement stringent security measures on their Linux systems.

![Image of the Bastion](https://github.com/fulco/BlueLinuxBastion/assets/802660/52bd88c5-a985-4ed2-af29-9698733b0198)


## Scripts Overview

### userkiller.sh
- Logs out and kills processes for all non-essential users.
- Clears non-essential user cron jobs and updates their passwords.
- Updates SSH to listen on a custom port and configures firewall rules.
- Secures key system files and commands to prevent tampering.
- Adds a backup admin user with sudo access for emergencies.
- Detailed logging of actions for auditing and troubleshooting.

### croncheck.sh
- Regularly verifies the integrity of key system configurations to ensure ongoing compliance with hardening standards.
- Checks include verifying backup admin user presence and privileges, immutability of SSH configurations, and firewall rules consistency.

### cronline.txt
- Provides a sample cron job setup to automate the execution of `croncheck.sh` and logs failures for administrative review.

## Getting Started

### Prerequisites
- Root access is required.
- Input a user (your primary user) to not change. 
- Either UFW or iptables must be installed for firewall configuration.
- An input file named `allowed_ips.txt` containing IP addresses and ports for SSH access should be prepared.

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/fulco/BlueLinuxBastion.git
   ```
2. Make the scripts executable:
   ```bash
   chmod +x userkiller.sh croncheck.sh
   ```

### Usage
1. Execute the `userkiller.sh` script with a username to exclude from the hardening process:
   ```bash
   sudo ./userkiller.sh <username_to_exclude>
   ```
2. Follow the prompts to set new user passwords.
3. Set up a cron job using the contents of `cronline.txt` to maintain system hardening.

## Configuration
- Modify `userkiller.sh` to set the `NEW_SSH_PORT` or change the log file path.
- Edit `cronline.txt` to match the desired cron schedule and script path.

## Contributing
Contributions to improve the scripts or documentation are welcome. Please submit pull requests for review.

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Disclaimer
Use these scripts with caution. They are provided as-is, and you should test them in a controlled environment before applying them to production systems.
```