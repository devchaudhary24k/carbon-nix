# Command line tools every machine gets.
#
# Development tools are in modules/dev.nix and desktop apps in
# modules/desktop/. A package that only exists to serve one service stays in
# the module that defines the service.
{ lib, pkgs, ... }:

{
  environment.systemPackages = lib.flatten (
    with pkgs;
    [
      # Shell, files and text
      [
        bat
        delta
        eza
        fd
        file
        jq
        ripgrep
        starship
        # The dotfiles repo links what Nix does not manage with Stow (bin/dots).
        stow
        tmux
        trash-cli
        tree
        unzip
        zip
        zoxide
      ]

      # Git and GitHub
      [
        gh
        git
        git-lfs
        lazygit
      ]

      # Nix tooling
      [
        nix-output-monitor
        nvd
      ]

      # Networking
      [
        bind
        curl
        ethtool
        inetutils
        iperf3
        mtr
        nmap
        rsync
        socat
        tcpdump
        websocat
        wget
        xh
      ]

      # Hardware and system inspection
      [
        btop
        dmidecode
        fastfetch
        htop
        iotop
        lm_sensors
        lshw
        lsof
        ncdu
        pciutils
        smartmontools
        strace
        usbutils
      ]

      # Backup and sync
      [
        rclone
        restic
      ]
    ]
  );
}
