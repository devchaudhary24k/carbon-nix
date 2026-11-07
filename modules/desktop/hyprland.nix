# Hyprland as a second session next to KDE Plasma, off by default. With
# my.desktop.hyprland.enable = true, SDDM offers it in its session menu.
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
  cfg = config.my.desktop.hyprland;
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
  options.my.desktop.hyprland.enable = lib.mkEnableOption "Hyprland as an extra session";

  config = lib.mkIf (config.my.desktop.enable && cfg.enable) {
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

    # File chooser and other dialogs for GTK apps under Hyprland.
    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

    # What Plasma has built in and Hyprland does not: file manager with
    # thumbnails and trash, Bluetooth and network tray apps, bar,
    # notifications, launcher, clipboard history, screenshots.
    programs.thunar.enable = true;
    services.gvfs.enable = true;
    services.tumbler.enable = true;
    services.blueman.enable = true;

    environment.systemPackages = with pkgs; [
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

    # Stable names for the two GPUs on a hybrid laptop, so Hyprland can be
    # told which one renders. udev names them card0/card1 in whatever order
    # the drivers load, which changes between boots. Plasma picks on its own.
    services.udev.extraRules = lib.mkIf prime.offload.enable ''
      KERNEL=="card*", SUBSYSTEM=="drm", KERNELS=="${pciAddress prime.amdgpuBusId}", SYMLINK+="dri/amd-igpu"
      KERNEL=="card*", SUBSYSTEM=="drm", KERNELS=="${pciAddress prime.nvidiaBusId}", SYMLINK+="dri/nvidia-dgpu"
    '';
  };
}
