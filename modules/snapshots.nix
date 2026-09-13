# Daily Btrfs snapshots of root and home, sent incrementally to the bulk disk.
#
# The instance is named after the host so two machines can send snapshots into
# the same directory tree without colliding.
{ config, ... }:

let
  instance = config.networking.hostName;
in

{
  # One snapshot per day, not hourly. Root and home stay briefly on the SSD and
  # are transferred incrementally to the bulk Btrfs disk.
  services.btrbk.instances.${instance} = {
    onCalendar = "*-*-* 03:30:00";
    settings = {
      timestamp_format = "long";

      snapshot_dir = "snapshots";
      snapshot_preserve_min = "1d";
      snapshot_preserve = "3d";

      target_preserve_min = "no";
      target_preserve = "14d 8w 6m";

      volume.${config.machine.btrfsRootPath} = {
        target = "${config.machine.bulkPath}/snapshots/${instance}";
        subvolume = {
          root = { };
          home = { };
        };
      };
    };
  };

  systemd.services."btrbk-${instance}" = {
    after = [
      "bulk-directory-setup.service"
      "snapshot-directory-setup.service"
    ];
    requires = [
      "bulk-directory-setup.service"
      "snapshot-directory-setup.service"
    ];
    unitConfig.RequiresMountsFor = [
      config.machine.btrfsRootPath
      config.machine.bulkPath
    ];
  };
}
