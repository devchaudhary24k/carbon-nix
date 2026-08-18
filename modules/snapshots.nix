{ ... }:

{
  # One snapshot per day, not hourly. Root and home stay briefly on the SSD
  # and are transferred incrementally to the 1 TB Btrfs disk.
  services.btrbk.instances.carbon = {
    onCalendar = "*-*-* 03:30:00";
    settings = {
      timestamp_format = "long";

      snapshot_dir = "snapshots";
      snapshot_preserve_min = "1d";
      snapshot_preserve = "3d";

      target_preserve_min = "no";
      target_preserve = "14d 8w 6m";

      volume."/mnt/btrfs-root" = {
        target = "/srv/bulk/snapshots/carbon";
        subvolume = {
          root = { };
          home = { };
        };
      };
    };
  };

  systemd.services.btrbk-carbon = {
    after = [
      "bulk-directory-setup.service"
      "snapshot-directory-setup.service"
    ];
    requires = [
      "bulk-directory-setup.service"
      "snapshot-directory-setup.service"
    ];
    unitConfig.RequiresMountsFor = [
      "/mnt/btrfs-root"
      "/srv/bulk"
    ];
  };
}
