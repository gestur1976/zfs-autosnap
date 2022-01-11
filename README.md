# zfs-auto-snapshots
Cyclical periodic snapshots for ZFS filesystems. Being able to set two timeframes. For instance, doing one each 15 minutes the first 2 days and after that keeping only a daily snapshot. It also supports sending through ssh first the entire dataset, and after that only incremental ones.
