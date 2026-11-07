# Builds carbon's real disk layout on scratch disks inside a VM, installs onto
# it, and boots from it.
#
# tests/services.nix cannot check this. The qemu-vm module throws away every
# fileSystems entry and substitutes its own disk, so a mistake in
# hosts/carbon/disks.nix would only show up during a real install. Here disko
# runs the partitioning for real against /dev/vdb and /dev/vdc.
#
# Nukebyte's layout is not tested this way: unlocking its LUKS volume at boot
# needs a passphrase typed on the console.
{ inputs, pkgs }:

inputs.disko.lib.testLib.makeDiskoTest {
  inherit pkgs;
  name = "carbon-disks";
  disko-config = ../hosts/carbon/disks.nix;

  extraTestScript = ''
    with subtest("root is ext4 with noatime and no inline discard"):
        machine.succeed("findmnt --noheadings --output FSTYPE / | grep -x ext4")
        options = machine.succeed("findmnt --noheadings --output OPTIONS /")
        assert "noatime" in options, f"/ lost noatime: {options}"
        assert "discard" not in options, f"/ has inline discard on: {options}"

    with subtest("boot is a FAT ESP"):
        machine.succeed("findmnt --noheadings --output FSTYPE /boot | grep -x vfat")

    with subtest("the bulk disk is ext4 and may go missing without blocking boot"):
        machine.succeed("findmnt --noheadings --output FSTYPE /srv/bulk | grep -x ext4")
        # nofail and the device timeout are fstab options rather than kernel
        # mount options, so findmnt's OPTIONS column never shows them.
        entry = machine.succeed("grep -E '[[:space:]]/srv/bulk[[:space:]]' /etc/fstab")
        assert "nofail" in entry, f"/srv/bulk would block boot when absent: {entry}"
        assert "x-systemd.device-timeout=10s" in entry, entry

    with subtest("filesystem labels"):
        for link in ["/dev/disk/by-label/carbon-root", "/dev/disk/by-label/carbon-bulk"]:
            machine.succeed(f"test -e {link}")
  '';
}
