# Carbon's disks, described once.
#
# disko turns this into both the commands installer/install.sh runs to
# partition the machine and the fileSystems entries the running system mounts,
# so the layout and the mount options cannot drift apart. Nothing else in this
# repo declares a partition.
#
# Plain ext4 on both disks. No snapshots and no backup jobs: projects keep
# their data in Git and in Docker volumes.
{
  disko.devices.disk = {
    # 240 GB WD Green SATA SSD: the system, home and Docker.
    ssd = {
      type = "disk";
      # Addressed by serial. /dev/sda and /dev/sdb can swap between boots, and
      # the installer erases whatever this points at.
      device = "/dev/disk/by-id/ata-WD_Green_2.5_240GB_251587803145";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            priority = 1;
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };

          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              extraArgs = [
                "-L"
                "carbon-root"
              ];
              # noatime avoids a write on every read. No `discard`: this
              # DRAM-less SSD stalls on inline TRIM, so services.fstrim trims
              # once a week instead.
              mountOptions = [ "noatime" ];
            };
          };
        };
      };
    };

    # 1 TB Seagate HDD: bulk storage for datasets, downloads and anything
    # large that does not need SSD speed.
    bulk = {
      type = "disk";
      device = "/dev/disk/by-id/ata-ST1000DM010-2EP102_ZN1MPLB5";
      content = {
        type = "gpt";
        partitions.bulk = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/srv/bulk";
            extraArgs = [
              "-L"
              "carbon-bulk"
            ];
            mountOptions = [
              "noatime"
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
