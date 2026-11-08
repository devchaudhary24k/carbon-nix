# What every machine gets, laptop or server.
{ lib, ... }:

{
  imports = [
    ./auto-upgrade.nix
    ./boot.nix
    ./logging.nix
    ./monitoring.nix
    ./network.nix
    ./nix.nix
    ./packages.nix
    ./shell.nix
    ./tailscale.nix
    ./users.nix
  ];

  options.my.user = lib.mkOption {
    type = lib.types.str;
    default = "dev24k";
    description = "Login name of the person who uses this machine.";
  };

  config = {
    time.timeZone = lib.mkDefault "Asia/Kolkata";
    i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
    console.keyMap = lib.mkDefault "us";
  };
}
