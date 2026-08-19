# Generated for carbon by `nixos-generate-config` during installation.
# The Btrfs mount options are kept explicit so they survive every reboot.
{ config, lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/dfb33954-156a-47a2-a30f-f6e029ff79b6";
    fsType = "btrfs";
    options = [ "subvol=root" "compress=zstd:3" "noatime" ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/dfb33954-156a-47a2-a30f-f6e029ff79b6";
    fsType = "btrfs";
    options = [ "subvol=home" "compress=zstd:3" "noatime" ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/dfb33954-156a-47a2-a30f-f6e029ff79b6";
    fsType = "btrfs";
    options = [ "subvol=nix" "compress=zstd:3" "noatime" ];
  };

  fileSystems."/var/log" = {
    device = "/dev/disk/by-uuid/dfb33954-156a-47a2-a30f-f6e029ff79b6";
    fsType = "btrfs";
    options = [ "subvol=log" "compress=zstd:3" "noatime" ];
  };

  fileSystems."/var/lib/docker" = {
    device = "/dev/disk/by-uuid/dfb33954-156a-47a2-a30f-f6e029ff79b6";
    fsType = "btrfs";
    options = [ "subvol=docker" "compress=zstd:3" "noatime" ];
  };

  fileSystems."/swap" = {
    device = "/dev/disk/by-uuid/dfb33954-156a-47a2-a30f-f6e029ff79b6";
    fsType = "btrfs";
    options = [ "subvol=swap" "compress=zstd:3" "noatime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/5FFC-705C";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;
}
