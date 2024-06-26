#!/bin/bash

# Set default PATH to include necessary directories for binary execution
export PATH="/usr/bin:/usr/local/sbin:/usr/local/bin:/bin:/sbin:/var/lib/snapd/snap/bin"

# Ensure numeric locale is set to C
export LC_NUMERIC=C

# Usage function to display help
usage() {
    cat <<EOF
Usage: $0 <pool> [min_free_space_gb] [minimum_days_to_keep_snapshots] [minimum_days_to_keep_intradiary_snapshots]

Examples:
  $0 tank 300
  $0 tank (defaults to 200GB of free space, 30 days of snapshots, and 7 days of intradiary snapshots)
  $0 tank 500 30 10 (Tries to keep 500GB free for tank, 30 days of snapshots, removing intradiary snapshots older than 10 days)
EOF
    exit 1
}

# Check for mandatory pool argument
if [ -z "$1" ]; then
    usage
fi

# Set pool name and optional parameters with defaults
POOL="$1"
MIN_FREE_SPACE_GB="${2:-200}"
MINIMUM_DAYS_TO_KEEP="${3:-30}"
MINIMUM_DAYS_TO_KEEP_INTRADIARY="${4:-7}"

DAYS_TO_KEEP_EPOCH=$(date -d "-${MINIMUM_DAYS_TO_KEEP} days" +"%s")
DAYS_TO_KEEP_INTRADIARY_EPOCH=$(date -d "-${MINIMUM_DAYS_TO_KEEP_INTRADIARY} days" +"%s")

# Define log file location
LOG_FILE="/var/log/snapshots.log"

# Define temporary file path
TMP_DIR="/tmp/snapshots-manager"

# Get current date and time for snapshot naming
NEW_SNAPSHOT_DATETIME=$(date +"%Y-%m-%dT%H:%M:%S")

# Function to log messages with timestamps
log_message() {
    echo "$(date +"%Y-%m-%dT%H:%M:%S"): $1" | tee -a "$LOG_FILE"
}

# Function to create a snapshot with the current datetime
create_snapshot() {
    log_message "Creating snapshot for dataset: $1"
    zfs snapshot "$1@$NEW_SNAPSHOT_DATETIME"
}

# Function to delete a specified snapshot
delete_snapshot() {
    log_message "Deleting snapshot $1"
    zfs destroy "$1"
}

# Function to recalculate free space in the pool and convert it to GB
recalculate_free_space() {
    local free_space free_space_amount free_space_unit free_space_gb

    free_space=$(zfs list -o available -H "$POOL")
    free_space_amount=$(echo "$free_space" | grep -Eo '[0-9\.]+')
    free_space_unit=$(echo "$free_space" | grep -Eo '[A-Z]$')

    if [[ "$free_space_unit" == "T" ]]; then
        free_space_gb=$(echo "$free_space_amount * 1024" | bc)
    else
        free_space_gb=$(echo "$free_space_amount" | bc)
    fi

    free_space_gb=$(printf "%.0f" "$free_space_gb")
    log_message "Available space in $POOL: ${free_space_gb}G"
}

# Function to delete old snapshots if the free space is below the threshold
delete_old_snapshots() {
    recalculate_free_space
    if [[ "$free_space_gb" -lt "$MIN_FREE_SPACE_GB" ]]; then
        log_message "Deleting old snapshots to free space..."

        zfs list -t snapshot -p -o creation,name | grep -E '^[0-9]' | sort -n > "$TMP_DIR/snapshots.txt"
        local snapshots_count snapshots_current_datetime snapshot_line snapshot_datetime snapshot_name

        snapshots_count=$(wc -l < "$TMP_DIR/snapshots.txt")

        if [ "$snapshots_count" -gt 0 ]; then
            snapshots_current_datetime=$(head -n 1 "$TMP_DIR/snapshots.txt" | grep -Eo '^[0-9]+')

            while read -r snapshot_line; do
                if [[ $(echo "$snapshot_line" | grep -Eo '^[0-9]+') -gt "$DAYS_TO_KEEP_EPOCH" ]]; then
                    log_message "Minimum $MINIMUM_DAYS_TO_KEEP days to keep exceeded."
                    break
                fi

                snapshot_datetime=$(echo "$snapshot_line" | grep -Eo '^[0-9]+')
                snapshot_name=$(echo "$snapshot_line" | grep -Eo '[^@^ ]+@[^ ]+$')

                if [[ "$snapshot_datetime" -gt "$snapshots_current_datetime" ]]; then
                    log_message "Checking free space..."
                    wait
                    sleep 1
                    recalculate_free_space
                    snapshots_current_datetime="$snapshot_datetime"
                fi

                if [[ "$free_space_gb" -lt "$MIN_FREE_SPACE_GB" ]]; then
                    delete_snapshot "$snapshot_name" &
                else
                    log_message "Adequate free space achieved."
                    break
                fi
            done < "$TMP_DIR/snapshots.txt"
        else
            log_message "No snapshots found. Consider freeing some space as pool performance may be degraded."
        fi
    fi
}

# Function to delete intradiary snapshots older than the minimum days to keep
delete_intradiary_snapshots() {
    log_message "Deleting intradiary snapshots older than ${MINIMUM_DAYS_TO_KEEP_INTRADIARY} days..."
    zfs list -t snapshot -p -o creation,name | grep -E '^[0-9]' | sort -n > "${TMP_DIR}/snapshots.txt"
    grep -E "${dataset}@[^ ]+$" "${TMP_DIR}/snapshots.txt" | rev | cut -d@ -f1 | cut -dT -f2 | rev | sort | uniq > "${TMP_DIR}/snapshot-dates.txt"

    zfs list -o name -H | while read -r dataset; do
        while read -r snapshots_date; do
            grep -F "${dataset}@${snapshots_date}" "${TMP_DIR}/snapshots.txt" | head -n -1 | while read -r snapshot_line; do
                local snapshot_epoch snapshot

                snapshot_epoch=$(echo "$snapshot_line" | grep -o -E '^[0-9]+')

                if [[ "$snapshot_epoch" -lt "$DAYS_TO_KEEP_INTRADIARY_EPOCH" ]]; then
		    ZFS_PROCESSES="$(ps ax | grep -v grep | grep -Fc 'zfs destroy')"
	            while [[ "$ZFS_PROCESSES" -gt "500" ]]; do
	            	sleep 2
		        ZFS_PROCESSES="$(ps ax | grep -v grep | grep -Fc 'zfs destroy')"
	            done
                    snapshot=$(echo "$snapshot_line" | rev | grep -o -E "^[^@]+@[^ ]+" | rev)
                    delete_snapshot "${snapshot}" &
                    
                fi
            done
        done < "${TMP_DIR}/snapshot-dates.txt"
    done
}

# Main function to coordinate snapshot management
main() {
    touch "$LOG_FILE"
    chown root:root "$LOG_FILE"
    chmod 640 "$LOG_FILE"

    rm -rf "${TMP_DIR}"
    mkdir -p "$TMP_DIR"

    recalculate_free_space
    delete_intradiary_snapshots
    wait
    sleep 1
    delete_old_snapshots
    
    if [ "$free_space_gb" -lt "$MIN_FREE_SPACE_GB" ]; then
        log_message "Couldn't free up enough space by deleting old snapshots. Consider freeing some space as pool performance may be degraded."
        log_message "Free space: ${free_space_gb}G"
    fi

    zfs list -H -o name | grep -E "^${POOL}[^ ]*" | while read -r dataset; do
        create_snapshot "$dataset" &
        log_message "Snapshot created: $dataset@$NEW_SNAPSHOT_DATETIME"
    done

    wait

    # Clean up temporary directory
    rm -rf "${TMP_DIR}"
}

# Execute the main function
main
