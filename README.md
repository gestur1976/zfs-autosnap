# ZFS-AutoSnap

`zfs-autosnap` is a Bash script for managing ZFS dataset snapshots on a Linux system with ZFS filesystems. The script automatically creates snapshots for each dataset in a given ZFS pool and monitors the free space available. If the free space drops below a specified threshold, the script deletes the oldest snapshots until the free space is above this threshold.

## Features

- **Automatic Snapshot Creation:** Creates a snapshot for every dataset in the specified ZFS pool.
- **Space Monitoring and Management:** Monitors the available space and deletes old snapshots if space falls below a certain threshold.
- **Configurable Free Space Threshold:** Allows for a custom threshold for minimum free space; defaults to 200 GB if not specified.
- **Logging:** Logs all operations to a file for audit and review.

## Requirements

- [OpenZFS](https://github.com/openzfs/zfs)
- Bash shell

## Installation

1. Clone the repository to your local machine.
2. Make the script executable:

```bash
chmod +x zfs-autosnap.sh
```

3. Copy the script for example to /usr/local/bin

```bash
sudo cp zfs-autosnap.sh /usr/local/bin/
```

## Usage

Run the script with the pool name as the first parameter and the minimum free space in GB as an optional second parameter.
```bash
zfs-autosnap.sh poolname [min_free_space_gb] [days_to_keep_snapshots] [days_to_keep_intradiary_snapshots]
```
If the second parameter is omitted, the script defaults to ensuring a minimum of 200 GB of free space.
If the third parameter is omitted, the script defaults to keeping 30 days of snapshots.
If the fourth parameter is omitted, the script defaults to keeping 7 days of intradiary snapshots.

## Examples:

```bash
zfs-autosnap.sh tank 1000 60 14 # Deletes snapshots older than 60 days or when 1000 GB threshold is reached and deletes all intradiary snapshots older than 14 days.
zfs-autosnap.sh tank 1000 60    # Deletes snapshots older than 60 days or when 1000 GB threshold is reached and deletes all intradiary snapshots older than 7 days.
zfs-autosnap.sh tank 300        # Deletes snapshots older than 30 days or when 300 GB threshold is reached and deletes all intradiary snapshots older than 7 days.
zfs-autosnap.sh tank            # Deletes snapshots older than 30 days or when 200 GB threshold is reached and deletes all intradiary snapshots older than 7 days.
```

If the second parameter is omitted, the script defaults to ensuring a minimum of 200 GB of free space.

## Configuration
To run this script as a cron job, edit your crontab with `crontab -e` and add a line like the following:

```cron
*/15 * * * * /path/to/zfs-autosnap.sh poolname 200 60 7 > /dev/null 2>&1
```

This example will run the script every 15 minutes, ensuring that `poolname` has at least 200 GB of free space and 7 days of intradiary snapshots.

## Log File

The script writes its log to `/var/log/snapshots.log`. Make sure the user running the script has the necessary permissions to write to this file.

## Notes

Before using the script, ensure that you understand the ZFS snapshot and delete operations and their impact on your system.
This script assumes the ZFS tools are installed and the pool name provided is valid and mounted.

## License

This script is released under the MIT License.

## Contributing

Contributions to this project are welcome. Please fork the repository and submit a pull request.

## Support

If you have any questions or need help with the script, please open an issue in the GitHub repository.
