# Nukebyte's disk, described once. disko uses it both to partition at install
# time and to generate the fileSystems the running system mounts.
#
# One NVMe drive, fully encrypted:
#
#   ESP   1 GB   FAT32, /boot. Holds only signed boot files (Secure Boot).
#   luks  rest   LUKS2, unlocked by the TPM once Secure Boot is on, with a
#                recovery key as the fallback. Inside: ext4 for /, including
#                /home and a swap file.
{
  disko.devices.disk.main = {
    type = "disk";
    # The ASUS TUF A15 has a single NVMe drive fitted. The installer prints
    # the disk it is about to erase and waits for confirmation; check it is
    # the 512 GB drive. Replace this with the /dev/disk/by-id/nvme-... path
    # if a second drive is ever added.
    device = "/dev/nvme0n1";
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

        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            # The installer asks for a passphrase. It is only needed until the
            # TPM is enrolled; see the README for replacing it with a
            # recovery key.
            askPassword = true;
            settings = {
              allowDiscards = true;
              # Try the TPM first; fall back to asking for the passphrase or
              # recovery key.
              crypttabExtraOpts = [ "tpm2-device=auto" ];
            };
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              extraArgs = [
                "-L"
                "nukebyte-root"
              ];
              mountOptions = [ "noatime" ];
            };
          };
        };
      };
    };
  };
}
