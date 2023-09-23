#!/bin/bash

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

CF_API_TOKEN=""                                  # Cloudflare credentials
DB_PATH="/tmp/cloudflare_rules.db"
IP_WHITELIST=("1.1.1.1" "8.8.8.8")               # Modify or extend this list as needed
VALID_MODES=("challenge" "block" "js_challenge") # Extend this array if more modes are needed
REQUIRED_TOOLS=("curl" "jq" "sqlite3")           # Check for necessary tools

function array_contains() {
    local seeking=$1
    shift
    local result=1
    for element; do
        if [[ $element == $seeking ]]; then
            result=0
            break
        fi
    done
    return $result
}

function is_ip_whitelisted() {
    local IP_TO_CHECK=$1
    for ip in "${IP_WHITELIST[@]}"; do
        if [[ "$IP_TO_CHECK" == "$ip" ]]; then
            return 0
        fi
    done
    return 1
}

function init_db() {
    if [[ ! -f "$DB_PATH" ]]; then
        sqlite3 "$DB_PATH" "CREATE TABLE rules (id INTEGER PRIMARY KEY AUTOINCREMENT, rule_id TEXT, domain TEXT, ip TEXT, added TIMESTAMP, mode TEXT, removed TIMESTAMP, block_count INTEGER, block_duration INTEGER DEFAULT 60);"
        sqlite3 "$DB_PATH" "CREATE INDEX idx_ip ON rules(ip);"
        sqlite3 "$DB_PATH" "CREATE INDEX idx_domain ON rules(domain);"
    fi
}

function get_zone_id() {
    local ZONE_NAME=$1

    local RESPONSE=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones?name=$ZONE_NAME" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")

    local SUCCESS=$(echo $RESPONSE | jq -r '.success')
    local ERRORS=$(echo $RESPONSE | jq -r '.errors[]?.message')

    if [[ "$SUCCESS" != "true" ]]; then
        echo "Failed to fetch zone ID for $ZONE_NAME. Errors: $ERRORS"
        exit 1
    fi

    local ZONE_ID=$(echo $RESPONSE | jq -r '.result[0].id')

    if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
        echo "Could not retrieve zone ID for $ZONE_NAME."
        exit 1
    fi

    echo $ZONE_ID
}

function add_rule() {
    local ZONE_NAME=$1
    local IP=$2
    local MODE=${3:-"challenge"}
    local BLOCK_TIME=${4:-60}
    local ZONE_ID=$(get_zone_id "$ZONE_NAME")

    # Check if IP was ever added (for statistics).
    local EVER_ADDED=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM rules WHERE ip='$IP' AND domain='$ZONE_NAME';")

    # Check if IP is already active (not removed).
    local CURRENTLY_ACTIVE=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM rules WHERE ip='$IP' AND domain='$ZONE_NAME' AND removed IS NULL;")

    if [[ "$CURRENTLY_ACTIVE" -ne 0 ]]; then
        if [[ "$BLOCK_TIME" -eq 0 ]]; then
            echo "IP $IP is already blocked indefinitely for domain $ZONE_NAME. Skipping..."
        else
            echo "IP $IP is already active for domain $ZONE_NAME. Skipping..."
        fi
        exit 1
    fi

    local RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/firewall/access_rules/rules" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data '{"mode":"'$MODE'","configuration":{"target":"ip","value":"'$IP'"},"notes":"Blocked by script"}')

    local SUCCESS=$(echo $RESPONSE | jq -r '.success')
    local ERRORS=$(echo $RESPONSE | jq -r '.errors[]?.message')

    if [[ "$SUCCESS" != "true" ]]; then
        echo "Failed to add IP rule to Cloudflare. Errors: $ERRORS"
        exit 1
    fi

    local RULE_ID=$(echo $RESPONSE | jq -r '.result.id')

    if [[ "$EVER_ADDED" -eq 0 ]]; then
        # New entry, insert into database.
        sqlite3 "$DB_PATH" "INSERT INTO rules (rule_id, domain, ip, added, mode, removed, block_count, block_duration) VALUES ('$RULE_ID', '$ZONE_NAME', '$IP', datetime('now'), '$MODE', NULL, 1, '$BLOCK_TIME');"
    else
        # IP was added before but is not currently active, so we update the previous record.
        sqlite3 "$DB_PATH" "UPDATE rules SET removed=NULL, block_count=block_count+1, rule_id='$RULE_ID', mode='$MODE', added=datetime('now') WHERE ip='$IP' AND domain='$ZONE_NAME';"
    fi
}

function del_rule() {
    local ZONE_NAME=$1
    local IP=$2
    local ZONE_ID=$(get_zone_id "$ZONE_NAME")

    local RULE_ID=$(sqlite3 "$DB_PATH" "SELECT rule_id FROM rules WHERE ip='$IP' AND domain='$ZONE_NAME' AND removed IS NULL;")

    local RESPONSE=$(curl -s -X DELETE \
        "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/firewall/access_rules/rules/$RULE_ID" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")

    local SUCCESS=$(echo $RESPONSE | jq -r '.success')
    local ERRORS=$(echo $RESPONSE | jq -r '.errors[]?.message')

    if [[ "$SUCCESS" != "true" ]]; then
        echo "Failed to delete IP rule from Cloudflare. Errors: $ERRORS"
        exit 1
    fi

    sqlite3 "$DB_PATH" "UPDATE rules SET removed=datetime('now') WHERE ip='$IP' and domain='$ZONE_NAME' AND removed IS NULL;"
}

function del_expired_rules() {
    EXPIRED_RULES=$(sqlite3 "$DB_PATH" "SELECT domain, ip FROM rules WHERE removed IS NULL AND block_duration <> 0 AND strftime('%s', 'now') - strftime('%s', added) > block_duration;")

    if [[ -z "$EXPIRED_RULES" ]]; then
        echo "No expired rules found."
        exit 0
    fi

    IFS=$'\n'

    for line in $EXPIRED_RULES; do
        IFS="|" read -r ZONE_NAME IP <<<"$line"
        del_rule "$ZONE_NAME" "$IP"
    done

    # Database optimization
    sqlite3 "$DB_PATH" "VACUUM;"
}

function list_blocked_ips() {
    local ALL=$1

    echo "IP Address - Domain - Date Added - Mode - Block Count"
    echo "-------------------------------------------------------"

    if [[ "$ALL" == "--all" ]]; then
        # List top 10 IPs with the highest block count, including previously added and removed
        sqlite3 -separator ' - ' "$DB_PATH" "SELECT ip, domain, added, mode, block_count FROM rules ORDER BY block_count DESC LIMIT 10;"
    else
        # List only currently blocked IPs
        sqlite3 -separator ' - ' "$DB_PATH" "SELECT ip, domain, added, mode, block_count FROM rules WHERE removed IS NULL;"
    fi
}

for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v $tool &>/dev/null; then
        echo "Error: $tool is not installed." >&2
        exit 1
    fi
done

init_db

# Parameter verification
if [[ "$1" != "add" && "$1" != "del" && "$1" != "list" ]]; then
    echo "Invalid action specified. Use 'add', 'del' or 'list'."
    exit 1
fi

if [[ "$1" == "add" && (-z "$2" || -z "$3") ]]; then
    echo "Zone name and IP address are required for the add operation."
    echo "Usage:"
    echo "$0 add <zone_name> <ip> [mode] [block_time_in_minutes]"
    exit 1
fi

if [[ "$1" == "add" && -n "$4" ]]; then
    if ! array_contains "$4" "${VALID_MODES[@]}"; then
        echo "Invalid mode specified. Valid modes are: ${VALID_MODES[*]}"
        exit 1
    fi
fi

if [[ "$1" == "del" && "$2" != "--cron" && (-z "$2" || -z "$3") ]]; then
    echo "Zone name and IP address are required for the delete operation unless using --cron."
    echo "Usage:"
    echo "$0 del <zone_name> <ip>"
    echo "$0 del --cron"
    exit 1
fi

# Main script logic
case "$1" in
    add)
        # $0 - script
        # $1 - command
        # $2 - zone_name
        # $3 - ip
        # $4 - mode
        # $5 - block_time_in_minutes
        add_rule "$2" "$3" "$4" "$5"
        ;;
    del)
        if [[ "$2" == "--cron" ]]; then
            del_expired_rules
        else
            del_rule "$2" "$3"
        fi
        ;;
    list)
        list_blocked_ips "$2"
        ;;
esac
