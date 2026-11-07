# Boot loader, firmware and memory compression. Secure Boot is opt-in per host.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.secureBoot;
in

{
  options.my.secureBoot.enable = lib.mkEnableOption ''
    Secure Boot through lanzaboote. The first boot generates this machine's
    own keys and enrolls them, provided the firmware is in Setup Mode
  '';

  config = lib.mkMerge [
    {
      # Ten entries is enough to roll back through roughly two months of
      # weekly changes.
      boot.loader.systemd-boot = {
        enable = lib.mkDefault true;
        configurationLimit = 10;
      };
      boot.loader.efi.canTouchEfiVariables = true;

      hardware.enableRedistributableFirmware = true;
      services.fwupd.enable = true;
      services.fstrim.enable = true;

      # Compressed swap in RAM, filled before any swap on disk.
      zramSwap = {
        enable = true;
        algorithm = "zstd";
        memoryPercent = 50;
        priority = 100;
      };
      boot.kernel.sysctl."vm.swappiness" = 100;
    }

    (lib.mkIf cfg.enable {
      # lanzaboote replaces the systemd-boot installer with one that signs.
      boot.loader.systemd-boot.enable = lib.mkForce false;
      boot.lanzaboote = {
        enable = true;
        pkiBundle = "/var/lib/sbctl";
        configurationLimit = 10;

        # Trust on first use: the first boot creates the keys, re-signs the
        # boot files, and reboots so systemd-boot can enroll them. The
        # Microsoft keys are enrolled too, because GPU firmware is signed
        # with them.
        autoGenerateKeys.enable = true;
        autoEnrollKeys = {
          enable = true;
          autoReboot = true;
        };
      };

      # Unlocking the disk with the TPM needs systemd in the initrd.
      boot.initrd.systemd.enable = true;
      security.tpm2.enable = true;

      environment.systemPackages = [ pkgs.sbctl ];
    })
  ];
}
