# Carbon's disks, described once.
#
# disko turns this into both the commands installer/install.sh runs to
# partition the machine and the fileSystems entries the running system mounts,
# so the layout and the mount options cannot drift apart. Nothing else in this
# repo declares a partition.
{ ... }:

let
  # zstd:3 is the Btrfs default level and costs little CPU here. noatime avoids
  # a metadata write on every read, which matters on a SATA SSD.
  btrfsOptions = [
    "compress=zstd:3"
    "noatime"
  ];

  subvolume = mountpoint: {
    inherit mountpoint;
    mountOptions = btrfsOptions;
  };
in

{
  disko.devices.disk = {
    # 240 GB WD Green SATA SSD, holding the system.
    ssd = {
      type = "disk";
      # Addressed by serial. /dev/sda and /dev/sdb can swap between boots, and
      # this script erases whatever it is pointed at.
      device = "/dev/disk/by-id/ata-WD_Green_2.5_240GB_251587803145";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            # disko would default this to "disk-ssd-ESP". Carbon was installed
            # before disko and its partitions are already named ESP, nixos and
            # bulk. The generated fileSystems address partitions by partlabel,
            # so these have to keep matching what is on the disk.
            label = "ESP";
            priority = 1;
            size = "1024M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [
                "fmask=0022"
                "dmask=0022"
              ];
              extraArgs = [
                "-n"
                "CARBONBOOT"
              ];
            };
          };

          nixos = {
            label = "nixos";
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [
                "-L"
                "carbon-root"
              ];
              subvolumes = {
                "root" = subvolume "/";
                "home" = subvolume "/home";
                "nix" = subvolume "/nix";
                "log" = subvolume "/var/log";
                "docker" = subvolume "/var/lib/docker";
                # Swap gets its own subvolume so an active swapfile never blocks
                # a snapshot of root. hosts/carbon/storage.nix creates the file.
                "swap" = subvolume "/swap";
              };
            };
          };
        };
      };
    };

    # 1 TB Seagate, holding backups and received snapshots. Btrfs is required
    # rather than ext4 because a Btrfs snapshot can only be sent to Btrfs.
    bulk = {
      type = "disk";
      device = "/dev/disk/by-id/ata-ST1000DM010-2EP102_ZN1MPLB5";
      content = {
        type = "gpt";
        partitions.bulk = {
          label = "bulk";
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [
              "-L"
              "carbon-bulk"
            ];
            mountpoint = "/srv/bulk";
            mountOptions = btrfsOptions ++ [
              # The machine still has to boot when this disk is absent or slow.
              "nofail"
              "x-systemd.device-timeout=10s"
            ];
          };
        };
      };
    };
  };
}
