# A graphical desktop: sound, Bluetooth, fonts, power and the apps. The
# session itself is picked per host:
#
#   my.desktop.hyprland.enable   Hyprland, with ly as the login screen
#   my.desktop.plasma.enable     KDE Plasma, with SDDM as the login screen
#
# With both on, SDDM offers both sessions.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.desktop;
in

{
  imports = [
    ./gaming.nix
    ./hyprland.nix
    ./plasma.nix
  ];

  options.my.desktop.enable = lib.mkEnableOption "a graphical desktop";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.hyprland.enable || cfg.plasma.enable;
        message = "my.desktop.enable needs a session: set my.desktop.hyprland.enable or my.desktop.plasma.enable.";
      }
    ];

    programs.dconf.enable = true;

    # Electron and Chromium apps use Wayland instead of XWayland.
    environment.sessionVariables.NIXOS_OZONE_WL = "1";

    # Sound
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    hardware.graphics.enable = true;
    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;
    services.udisks2.enable = true;

    # Closing the lid suspends, except while an external monitor is attached.
    services.logind.settings.Login = {
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "suspend";
      HandleLidSwitchDocked = "ignore";
    };

    programs.firefox.enable = true;

    fonts = {
      enableDefaultPackages = true;
      packages = with pkgs; [
        nerd-fonts.jetbrains-mono
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
      ];
      fontconfig.defaultFonts.monospace = [ "JetBrainsMono Nerd Font" ];
    };

    environment.systemPackages = with pkgs; [
      bitwarden-desktop
      ghostty
      google-chrome
      mpv
      obsidian
      spotify
      telegram-desktop
      vesktop
      # The 26.05 build of 1.144 fails in its patch phase; unstable has the fix.
      # Move back to plain `vscode` once 26.05 builds again.
      unstable.vscode
    ];

    my.unfree = [
      "google-chrome"
      "obsidian"
      "spotify"
      "vscode"
    ];

    users.users.${config.my.user}.extraGroups = [
      "video"
      "input"
    ];
  };
}
