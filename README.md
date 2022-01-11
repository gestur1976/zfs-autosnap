# zfs-auto-snapshots
Set of bash scripts to do cyclical periodic snapshots for ZFS filesystems.

You can set two two timeframes. For instance 2 days and 90 days:

· During the first one, a snapshot can be done each 15 minutes. This allows to recover reently deleted or damaged files without losing almost any data or work time
· To save space, once the first timeframe has ended, all intradiary snapshots are deleted and only one is kept at the end of the day. Snapshots older than 90 days are deleted too.
. It also supports for backup purposes sending the datasets to a local backup pool or to a remote one (through ssh), first it is sent as a whole with all its snapshots, and after that only the incremental ones are sent just after the time of creation in order to keep both copies synched.

