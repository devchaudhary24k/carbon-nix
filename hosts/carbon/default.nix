# Carbon: headless AMD development box, 240 GB SSD plus 1 TB HDD.
#
# Everything here is true of this machine and no other. Anything a second
# machine could reuse belongs in modules/.
{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  # Minecraft Console Client ships a self-contained .NET binary that looks for
  # ICU and OpenSSL in an FHS that does not exist here. nix-ld gets it running;
  # these are the libraries it asks for.
  mccLibraries = with pkgs; [
    curl
    icu
    krb5
    libunwind
    openssl
    stdenv.cc.cc
    zlib
    zstd
  ];

  # Handing .NET the exact store paths is more reliable than letting it search
  # the generic nix-ld path for ICU.
  mccRuntime = pkgs.writeShellScriptBin "mcc-runtime" ''
    export LD_LIBRARY_PATH="${lib.makeLibraryPath mccLibraries}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    exec /opt/mcc/bin/MinecraftClient "$@"
  '';
in

{
  imports = [
    ./disks.nix
    ./hardware.nix
    ./storage.nix

    # Optional shared modules this machine opts into.
    ../../modules/containers.nix
    ../../modules/databases.nix
    ../../modules/dev-runtime.nix
    ../../modules/health-monitor.nix
    ../../modules/snapshots.nix
  ];

  machine = {
    primaryUser = "dev24k";
    bulkPath = "/srv/bulk";
    btrfsRootPath = "/mnt/btrfs-root";
  };

  networking.hostName = "carbon";
  networking.networkmanager.enable = true;

  # modules/network.nix opens SSH on Tailscale. This is the wired NIC.
  networking.firewall.interfaces.enp8s0.allowedTCPPorts = [ 22 ];

  time.timeZone = "Asia/Kolkata";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  # Installed in UEFI mode. Ten entries is roughly two months of weekly
  # upgrades to roll back through.
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.amd.updateMicrocode = true;
  services.fstrim.enable = true;
  services.fwupd.enable = true;

  # Named one by one rather than allowUnfree, so a new unfree dependency has to
  # be noticed and added here.
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "claude-code"
    ];

  # Packages only this machine needs. The shared toolbox is modules/packages.nix.
  environment.systemPackages = [
    pkgs.dotnet-sdk_10
    mccRuntime
  ];

  # Appended to the libraries modules/dev-runtime.nix already provides.
  programs.nix-ld.libraries = mccLibraries;

  users.users.dev24k = {
    isNormalUser = true;
    description = "Development user";
    shell = pkgs.fish;
    linger = true;
    extraGroups = [
      "docker"
      "wheel"
      "networkmanager"
    ];

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINgrNQxV5Klb6/QSnF9QNwYGTxmtXFZ3AnMlQNd4jwVS"
    ];
  };

  home-manager.users.dev24k = import ../../home/dev24k.nix;

  # Keep this unchanged after the initial installation.
  system.stateVersion = "26.05";
}
