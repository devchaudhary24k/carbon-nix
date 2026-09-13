# Storage behaviour that sits on top of the layout in disks.nix: the extra
# mount btrbk needs, swap, scrubbing, and the directories the backup jobs write
# into.
{ config, pkgs, ... }:

let
  inherit (config.machine) btrfsRootPath bulkPath primaryUser;
in

{
  # disks.nix mounts each subvolume where it belongs. btrbk also needs to see
  # them as siblings, which means mounting the top of the filesystem.
  fileSystems.${btrfsRootPath} = {
    device = "/dev/disk/by-label/carbon-root";
    fsType = "btrfs";
    options = [
      "subvolid=5"
      "compress=zstd:3"
      "noatime"
    ];
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };

  swapDevices = [
    {
      # Lower priority than zram, so compressed RAM fills first and the SSD is
      # only touched once that is exhausted.
      device = "/swap/swapfile";
      size = 8192;
      priority = 10;
    }
  ];

  boot.kernel.sysctl."vm.swappiness" = 100;

  # Scrubbing "/" checks the whole SSD filesystem including the home subvolume.
  # The bulk disk is a separate filesystem and needs its own entry.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [
      "/"
      bulkPath
    ];
  };

  # Only run once the bulk disk really mounted. Without the condition a missing
  # disk would send backups to the 240 GB SSD instead.
  systemd.services.bulk-directory-setup = {
    description = "Create directories on the bulk data disk";
    wantedBy = [ "multi-user.target" ];
    requires = [ "srv-bulk.mount" ];
    after = [ "srv-bulk.mount" ];
    unitConfig.ConditionPathIsMountPoint = bulkPath;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    script = ''
      install -d -m 0755 -o root -g root ${bulkPath}/backups
      install -d -m 0755 -o root -g root ${bulkPath}/backups/databases
      install -d -m 0700 -o postgres -g postgres ${bulkPath}/backups/databases/postgresql
      install -d -m 0700 -o root -g root ${bulkPath}/backups/databases/mariadb
      install -d -m 0700 -o root -g root ${bulkPath}/backups/databases/valkey
      install -d -m 0755 -o root -g root ${bulkPath}/snapshots
      install -d -m 0755 -o root -g root ${bulkPath}/snapshots/${config.networking.hostName}
      install -d -m 2775 -o ${primaryUser} -g users ${bulkPath}/datasets
      install -d -m 2775 -o ${primaryUser} -g users ${bulkPath}/downloads
    '';
  };

  systemd.services.snapshot-directory-setup = {
    description = "Create the local Btrfs snapshot directory";
    wantedBy = [ "multi-user.target" ];
    unitConfig.RequiresMountsFor = [ btrfsRootPath ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    script = ''
      install -d -m 0755 -o root -g root ${btrfsRootPath}/snapshots
    '';
  };
}
