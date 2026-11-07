# ASUS TUF Gaming A15 (2021, FA506IC): Ryzen 7 4800H with Radeon graphics,
# RTX 3050 Laptop GPU, 16 GB RAM, 512 GB NVMe.
#
# Most of the hardware setup comes from nixos-hardware's profile for this
# model: AMD CPU and GPU, NVIDIA PRIME offload, asusd (fan profiles, keyboard
# light, charge limit) and supergfxd (GPU modes). This file holds what the
# profile does not, and the corrections to it.
{
  inputs,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    inputs.nixos-hardware.nixosModules.asus-fa506ic
  ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-amd" ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = true;

  hardware.nvidia = {
    # The profile writes these as PCI:0:6:0 and PCI:0:1:0, which looks like a
    # typo: on this platform the GPUs sit at 06:00.0 and 01:00.0, as in the
    # profile for the FA706IC (the 17" model with the same board). Confirm
    # after the first boot with: lspci -D | grep -E 'VGA|3D'
    prime = {
      amdgpuBusId = lib.mkForce "PCI:6:0:0";
      nvidiaBusId = lib.mkForce "PCI:1:0:0";
    };

    # Saves video memory across suspend, so apps on the NVIDIA GPU survive a
    # sleep. Fine-grained power management turns the GPU off entirely when
    # nothing uses it, which only happens away from the dock.
    powerManagement = {
      enable = true;
      finegrained = true;
    };
  };

  my.unfree = [
    "nvidia-x11"
    "nvidia-settings"
  ];
}
