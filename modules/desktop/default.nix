# A graphical desktop: Hyprland as the main session, KDE Plasma as the
# fallback, ly as the login screen. Pick the session in ly with the arrow keys
# on its top line; it remembers the last one.
#
# The Hyprland configuration itself (keys, monitors, bar) lives in the
# dotfiles repo and is linked into place by home/dev24k/desktop.nix.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.desktop;
  prime = config.hardware.nvidia.prime;

  # "PCI:6:0:0" (decimal, the form NixOS takes) to "0000:06:00.0" (the form
  # udev and the kernel use).
  pciAddress =
    busId:
    let
      parts = lib.splitString ":" busId;
      hex = n: lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString (lib.toInt n)));
    in
    "0000:${hex (lib.elemAt parts 1)}:${hex (lib.elemAt parts 2)}.${lib.elemAt parts 3}";
in

{
  imports = [ ./gaming.nix ];

  options.my.desktop.enable = lib.mkEnableOption "the graphical desktop";

  config = lib.mkIf cfg.enable {
    services.displayManager.ly.enable = true;

    programs.hyprland = {
      enable = true;
      # Runs Hyprland as a proper systemd session, so apps started from it get
      # the right environment and logging out cleans up after them.
      withUWSM = true;
    };
    # Screen locker and its PAM entry. hypridle starts it after 10 minutes.
    programs.hyprlock.enable = true;
    # Asks for your password when an app needs root. Started by Hyprland.
    systemd.packages = [ pkgs.hyprpolkitagent ];

    services.desktopManager.plasma6.enable = true;

    # File chooser and other dialogs for GTK apps under Hyprland.
    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
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
    services.blueman.enable = true;

    hardware.graphics.enable = true;
    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;

    # Closing the lid suspends, except while an external monitor is attached.
    services.logind.settings.Login = {
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "suspend";
      HandleLidSwitchDocked = "ignore";
    };

    # File manager for Hyprland (Plasma brings Dolphin), with thumbnails,
    # trash and removable drives.
    programs.thunar.enable = true;
    services.gvfs.enable = true;
    services.tumbler.enable = true;
    services.udisks2.enable = true;

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
      # Apps
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

      # Hyprland session pieces
      brightnessctl
      cliphist
      fuzzel
      grimblast
      hypridle
      hyprpolkitagent
      libnotify
      networkmanagerapplet
      pavucontrol
      playerctl
      swaynotificationcenter
      waybar
      wl-clipboard
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

    # Stable names for the two GPUs on a hybrid laptop, so Hyprland can be
    # told which one renders. udev names them card0/card1 in whatever order
    # the drivers load, which changes between boots.
    services.udev.extraRules = lib.mkIf prime.offload.enable ''
      KERNEL=="card*", SUBSYSTEM=="drm", KERNELS=="${pciAddress prime.amdgpuBusId}", SYMLINK+="dri/amd-igpu"
      KERNEL=="card*", SUBSYSTEM=="drm", KERNELS=="${pciAddress prime.nvidiaBusId}", SYMLINK+="dri/nvidia-dgpu"
    '';
  };
}
