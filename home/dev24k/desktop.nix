# User-level desktop setup, only on machines with my.desktop.enable.
#
# The configuration files live in the dotfiles repo (home/hypr, home/waybar,
# home/uwsm); this only links them into place. Each machine's monitor layout
# is home/hypr/.config/hypr/monitors/<hostname>.lua, linked as monitors.lua.
#
# KDE Plasma rewrites its own config files constantly, and Nix-managed links
# are read-only, so the KDE settings are linked by the dotfiles repo's Stow
# helper instead: dots link
{
  inputs,
  lib,
  osConfig,
  ...
}:

let
  hypr = "${inputs.dotfiles}/home/hypr/.config/hypr";
  monitors = "${hypr}/monitors/${osConfig.networking.hostName}.lua";

  linkDir = package: dir: {
    source = "${inputs.dotfiles}/home/${package}/.config/${dir}";
    recursive = true;
  };
in

{
  config = lib.mkIf osConfig.my.desktop.enable {
    xdg.configFile = {
      "hypr" = linkDir "hypr" "hypr";
      "waybar" = linkDir "waybar" "waybar";
      "uwsm" = linkDir "uwsm" "uwsm";
    }
    // lib.optionalAttrs (builtins.pathExists monitors) {
      "hypr/monitors.lua".source = monitors;
    };

    # Dark theme for GTK and portal-aware apps.
    dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
  };
}
