#!/bin/bash

# Define the default PATH to include necessary directories for binary execution.
PATH="/usr/bin:/usr/local/sbin:/usr/local/bin:/bin:/sbin:/var/lib/snapd/snap/bin"

# This script creates a snapshot for every ZFS dataset.
# The snapshots are formatted as follows: dataset@YYYY-MM-DDTHH-MM-SS.
# If the available space falls below the minimum threshold defined by min_free_space_gb,
# the script will remove older snapshots until there is enough free space meeting the min_free_space_gb threshold.

# The script is designed to be executed as a cron job.

# Set pool name using provided argument and optionally set the minimum free space threshold.
if [ -z "$1" ]; then
    echo "Usage: $0 <pool> [min_free_space_gb] [minimum_days_to_keep snapshots (overrides min_free_space_gb)]" > /dev/stderr
    echo > /dev/stderr
    echo "Examples:" > /dev/stderr
    echo "$0 tank 300" > /dev/stderr
    echo "$0 tank (it defaults to 200G of free space and a minimum of 30 days of snapshots)" > /dev/stderr
    exit 1
fi

# Define the log file location.
log_file="/var/log/snapshots.log"
# Define the temporary file path.
tmp_dir="/tmp/snapshots-manager"
# Get current date and time for snapshot naming.
new_snapshots_datetime=$(date +"%Y-%m-%dT%H:%M:%S")

pool="$1"
if [ -z "$2" ]; then
    min_free_space_gb="200"
else
    min_free_space_gb="$2"
fi

if [ -z "$3" ]; then
    minimum_days_to_keep="30"
else    
    minimum_days_to_keep="$3"
fi

days_to_keep_epoch=$(date -d "-${minimum_days_to_keep} days" +"%s")

# Function to log messages with timestamps.
function log_message() {
    echo "$(date +"%Y-%m-%dT%H:%M:%S"): $1" | tee -a "$log_file"
}

# Function to create a snapshot with the current datetime.
function create_snapshot() {
    log_message "Creating snapshot for dataset: $1"
    zfs snapshot "$1@$new_snapshots_datetime"
}

# Function to delete a specified snapshot.
function delete_snapshot() {
    log_message "Deleting snapshot $1"
    zfs destroy "$1"
}

# Function to recalculate free space in the pool and convert it to GB.
function recalculate_free_space() {
    # Extract available space for the pool.
    free_space=$(zfs list -o available "$pool" | tail -n 1)
    free_space_amount=$(echo "$free_space" | grep -E -o '[0-9\.]+')
    # Extract the unit of the available space (e.g., T for TB).
    free_space_unit=$(echo "$free_space" | grep -E -o '[A-Z]$')
    # Convert the space to GB if necessary.
    if [[ "$free_space_unit" == "T" ]]; then
        free_space_gb=$(echo "$free_space_amount" "*" "1024" | bc | grep -E -o '^[0-9]+')
    else
        free_space_gb=$(echo "$free_space_amount" | bc | grep -E -o '^[0-9]+')
    fi
    echo
    log_message "Available space in $pool: ${free_space_gb}G"
}

# Function to delete old snapshots if the free space is below the threshold.
function delete_old_snapshots() {
    if [[ "$free_space_gb" -lt "$min_free_space_gb" ]]; then
        log_message "Deleting old snapshots to free space..."
        echo
        # List all snapshots, sort them by creation time, and write to a file.
        zfs list -t snapshot -p -o creation,name | grep -E '^[0-9]' | sort -n > "$tmp_dir/snapshots.txt"
        snapshots_count=$(wc -l < "$tmp_dir/snapshots.txt")
        # Check if there are any snapshots to delete.
        if [ "$snapshots_count" -gt 0 ]; then
            snapshots_current_datetime=$(head -n 1 "$tmp_dir/snapshots.txt" | grep -E -o '^[0-9]+')
            # Read through the list of snapshots and delete as needed.
            while read -r snapshot_line; do
                # Check if the snapshot is older than the minimum days to keep.
                if [[ $(echo "$snapshot_line" | grep -E -o '^[0-9]+') -gt "$days_to_keep_epoch" ]]; then
                    log_message "Minimum $minimum_days_to_keep days to keep exceeded."
                    break
                fi
                snapshot_datetime=$(echo "$snapshot_line" | grep -E -o '^[0-9]+')
                snapshot_name=$(echo "$snapshot_line" | grep -E -o '[^@^ ]+@[^ ]+$')
                if [[ "$snapshot_datetime" -gt "$snapshots_current_datetime" ]]; then
                    echo
                    log_message "Checking free space..."
                    wait
                    sleep 5
                    recalculate_free_space
                    snapshots_current_datetime="$snapshot_datetime"
                fi
                if [[ "$free_space_gb" -lt "$min_free_space_gb" ]]; then
                    delete_snapshot "$snapshot_name" &
                else
                    echo
                    log_message "Adequate free space achieved."
                    break
                fi
            done < "$tmp_dir/snapshots.txt"
        else
            log_message "No snapshots found. Consider freeing some space as pool performance may be degraded."
        fi
    fi
}

# Main function to coordinate snapshot management.
function main() {
    touch "$log_file"
    chown root:root "$log_file"
    chmod 640 "$log_file"
    rm -rf "${tmp_dir}"
    mkdir -p "$tmp_dir"
    recalculate_free_space
    delete_old_snapshots
    if [ "$free_space_gb" -lt "$min_free_space_gb" ]; then
        echo
        log_message "Couldn't free up enough space by deleting old snapshots. Consider freeing some space as pool performance may be degraded."
        log_message "Free space: ${free_space_gb}G"
    fi
    # Create snapshots for each dataset in the pool.
    zfs list | grep -E -o "^${pool}[^ ]*" | while read -r dataset; do
        create_snapshot "$dataset" &
        log_message "Snapshot created: $dataset@$new_snapshots_datetime"
    done
    # Wait for all background processes to finish.
    wait
}

# Call the main function to execute the script.
main

# Let's clear tmp directory.
rm -rf "${tmp_dir}"
