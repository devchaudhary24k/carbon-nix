# A graphical desktop: KDE Plasma 6 on Wayland, with SDDM as the login
# screen. Hyprland can be added as a second session with
# my.desktop.hyprland.enable (see hyprland.nix).
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
  ];

  options.my.desktop.enable = lib.mkEnableOption "the KDE Plasma desktop";

  config = lib.mkIf cfg.enable {
    services.desktopManager.plasma6.enable = true;

    services.displayManager = {
      sddm = {
        enable = true;
        wayland.enable = true;
      };
      defaultSession = "plasma";
    };

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
