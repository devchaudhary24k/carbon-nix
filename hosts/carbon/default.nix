{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/databases.nix
    ../../modules/headless-dev.nix
    ../../modules/maintenance.nix
    ../../modules/observability.nix
    ../../modules/snapshots.nix
    ../../modules/storage.nix
  ];

  networking.hostName = "carbon";
  networking.networkmanager.enable = true;

  time.timeZone = "Asia/Kolkata";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  # Assumes the installer is booted in UEFI mode.
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.amd.updateMicrocode = true;
  services.fstrim.enable = true;
  services.fwupd.enable = true;

  users.users.dev24k = {
    isNormalUser = true;
    description = "Development user";
    shell = pkgs.fish;
    extraGroups = [
      "docker"
      "wheel"
      "networkmanager"
    ];

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINgrNQxV5Klb6/QSnF9QNwYGTxmtXFZ3AnMlQNd4jwVS"
    ];
  };

  # Keep this value unchanged after the initial installation.
  system.stateVersion = "26.05";
}
