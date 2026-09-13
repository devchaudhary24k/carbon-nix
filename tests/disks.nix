# Builds a host's real disk layout on scratch disks inside a VM, installs onto
# it, and boots from it.
#
# tests/services.nix cannot check this. The qemu-vm module throws away every
# fileSystems entry and substitutes its own disk, so a mistake in
# hosts/<name>/disks.nix would only show up during a real install. Here disko
# runs the partitioning for real against /dev/vdb and /dev/vdc.
{
  inputs,
  name,
  pkgs,
}:

inputs.disko.lib.testLib.makeDiskoTest {
  inherit pkgs;
  name = "${name}-disks";
  disko-config = ../hosts/${name}/disks.nix;

  extraTestScript = ''
    with subtest("every subvolume is mounted where the rest of the config expects"):
        for path, subvolume in [
            ("/", "root"),
            ("/home", "home"),
            ("/nix", "nix"),
            ("/var/log", "log"),
            ("/var/lib/docker", "docker"),
            ("/swap", "swap"),
        ]:
            machine.succeed(f"findmnt --noheadings --output SOURCE {path} | grep -F '[/{subvolume}]'")
            options = machine.succeed(f"findmnt --noheadings --output OPTIONS {path}")
            assert "compress=zstd:3" in options, f"{path} lost its compression: {options}"
            assert "noatime" in options, f"{path} lost noatime: {options}"

    with subtest("swap is a sibling of root, so snapshots of root exclude it"):
        machine.succeed("mkdir -p /mnt/btrfs-root")
        machine.succeed("mount -o subvolid=5 /dev/disk/by-label/carbon-root /mnt/btrfs-root")
        for subvolume in ["root", "home", "nix", "log", "docker", "swap"]:
            machine.succeed(f"test -d /mnt/btrfs-root/{subvolume}")

    with subtest("labels and partition labels the rest of the config mounts by"):
        # hosts/carbon/storage.nix mounts the top-level subvolume by label, and
        # the fileSystems disko generates address partitions by partlabel.
        for link in [
            "/dev/disk/by-label/carbon-root",
            "/dev/disk/by-label/carbon-bulk",
            "/dev/disk/by-partlabel/ESP",
            "/dev/disk/by-partlabel/nixos",
            "/dev/disk/by-partlabel/bulk",
        ]:
            machine.succeed(f"test -e {link}")

    with subtest("boot is a FAT ESP"):
        machine.succeed("findmnt --noheadings --output FSTYPE /boot | grep -x vfat")

    with subtest("the bulk disk is Btrfs and may go missing without blocking boot"):
        machine.succeed("findmnt --noheadings --output FSTYPE /srv/bulk | grep -x btrfs")
        # nofail and the device timeout are fstab options rather than kernel
        # mount options, so findmnt's OPTIONS column never shows them.
        entry = machine.succeed("grep -E '[[:space:]]/srv/bulk[[:space:]]' /etc/fstab")
        assert "nofail" in entry, f"/srv/bulk would block boot when absent: {entry}"
        assert "x-systemd.device-timeout=10s" in entry, entry

    with subtest("Btrfs snapshots can be sent from the SSD to the bulk disk"):
        machine.succeed("btrfs subvolume snapshot -r /home /mnt/btrfs-root/home-snapshot")
        machine.succeed("mkdir -p /srv/bulk/snapshots")
        machine.succeed(
            "btrfs send /mnt/btrfs-root/home-snapshot | btrfs receive /srv/bulk/snapshots"
        )
        machine.succeed("test -d /srv/bulk/snapshots/home-snapshot")
  '';
}
