# KDE Plasma 6 on Wayland, with SDDM as the login screen.
{ config, lib, ... }:

{
  options.my.desktop.plasma.enable = lib.mkEnableOption "the KDE Plasma session";

  config = lib.mkIf (config.my.desktop.enable && config.my.desktop.plasma.enable) {
    services.desktopManager.plasma6.enable = true;

    services.displayManager = {
      sddm = {
        enable = true;
        wayland.enable = true;
      };
      defaultSession = "plasma";
    };
  };
}
