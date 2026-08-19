{ pkgs, ... }:

{
  # The SSD is formatted with label "carbon-root". Mounting its top-level
  # subvolume lets btrbk snapshot the root and home subvolumes cleanly.
  fileSystems."/mnt/btrfs-root" = {
    device = "/dev/disk/by-label/carbon-root";
    fsType = "btrfs";
    options = [
      "subvolid=5"
      "compress=zstd"
      "noatime"
    ];
  };

  # The 1 TB Seagate is reformatted as Btrfs during installation so it can
  # receive native, incremental snapshots from the SSD.
  fileSystems."/srv/bulk" = {
    device = "/dev/disk/by-label/carbon-bulk";
    fsType = "btrfs";
    options = [
      "compress=zstd"
      "noatime"
      "nofail"
      "x-systemd.device-timeout=10s"
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
      # /swap is a separate Btrfs subvolume, so an active swapfile never
      # prevents snapshots of the root subvolume.
      device = "/swap/swapfile";
      size = 8192;
      priority = 10;
    }
  ];

  boot.kernel.sysctl."vm.swappiness" = 100;

  # Scrubbing the root mount checks the entire SSD Btrfs filesystem, including
  # its home subvolume. The HDD is a separate Btrfs filesystem.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [
      "/"
      "/srv/bulk"
    ];
  };

  # Create these only after the HDD really mounted. This prevents accidental
  # writes to the small SSD when the HDD is missing.
  systemd.services.bulk-directory-setup = {
    description = "Create directories on the bulk data disk";
    wantedBy = [ "multi-user.target" ];
    requires = [ "srv-bulk.mount" ];
    after = [ "srv-bulk.mount" ];
    unitConfig.ConditionPathIsMountPoint = "/srv/bulk";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    script = ''
      install -d -m 0755 -o root -g root /srv/bulk/backups
      install -d -m 0755 -o root -g root /srv/bulk/backups/databases
      install -d -m 0700 -o postgres -g postgres /srv/bulk/backups/databases/postgresql
      install -d -m 0700 -o root -g root /srv/bulk/backups/databases/mariadb
      install -d -m 0700 -o root -g root /srv/bulk/backups/databases/valkey
      install -d -m 0755 -o root -g root /srv/bulk/snapshots
      install -d -m 0755 -o root -g root /srv/bulk/snapshots/carbon
      install -d -m 2775 -o dev24k -g users /srv/bulk/datasets
      install -d -m 2775 -o dev24k -g users /srv/bulk/downloads
    '';
  };

  systemd.services.snapshot-directory-setup = {
    description = "Create the local Btrfs snapshot directory";
    wantedBy = [ "multi-user.target" ];
    unitConfig.RequiresMountsFor = [ "/mnt/btrfs-root" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    script = ''
      install -d -m 0755 -o root -g root /mnt/btrfs-root/snapshots
    '';
  };
}
