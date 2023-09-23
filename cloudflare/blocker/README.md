# Cloudflare IP Blocker Script

This script is a utility to add, delete, or list IP addresses in Cloudflare's firewall access rules. It is designed to be used by administrators to manage IP blocking with convenience and efficiency.

## Features

- **Add IP Rule**: Block an IP address by adding it to Cloudflare's firewall access rules.
- **Delete IP Rule**: Unblock an IP address by removing it from Cloudflare's firewall access rules.
- **List Blocked IPs**: Display a list of the currently blocked IP addresses.
- **Delete Expired Rules**: Remove IP blocking rules that have expired based on their block duration.
- **Persistent Storage**: Uses a SQLite database to store rule data persistently.
- **Block Time Management**: Supports specifying block time, including indefinite blocking.

## Requirements

- bash
- curl
- jq
- sqlite3

## Database Structure

The script maintains a SQLite database (cloudflare_rules.db) with the following structure:

 - `id`: Unique identifier for each rule.
 - `rule_id`: ID assigned by Cloudflare to the rule.
 - `domain`: The Cloudflare zone (domain) for which the rule is added.
 - `ip`: IP address being blocked.
 - `added`: Timestamp when the rule was added.
 - `mode`: The mode for blocking (challenge, block, js_challenge).
 - `removed`: Timestamp when the rule was removed. NULL if the rule is still active.
 - `block_count`: Count of how many times the IP has been blocked.
 - `block_duration`: The duration (in minutes) for which the IP should be blocked. 0 means indefinite.

## Usage

1. **Initialize the script**: Run the script with administrative privileges.
2. **Add IP Rule**: `./script.sh add <zone_name> <ip> [mode] [block_time_in_minutes]`
3. **Delete IP Rule**: `./script.sh del <zone_name> <ip>`
4. **List Blocked IPs**: `./script.sh list [--all]`
5. **Delete Expired Rules (Cron Job)**: `./script.sh del --cron`

## Parameters

- `zone_name`: The Cloudflare zone name of the domain.
- `ip`: The IP address to block or unblock.
- `mode`: (Optional) The block mode, can be "challenge", "block", or "js_challenge".
- `block_time_in_minutes`: (Optional) The duration to block the IP address in minutes. Set to 0 for indefinite blocking.
- `--all`: (Optional) List all IP addresses, including those that were unblocked.

## Notes

- Ensure that the script is executed with root privileges.
- Modify the `IP_WHITELIST` and `VALID_MODES` arrays as needed.
- The script checks for the necessary tools at runtime and will exit if any are missing.
- The SQLite database is located at `/tmp/cloudflare_rules.db`.
