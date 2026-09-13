# Every package installed system-wide, in one list.
#
# Two things deliberately live elsewhere. Packages that only exist to support a
# service, like the generated health-check script, stay in the module that
# wires them into systemd. Packages that only one machine needs go in
# hosts/<name>/default.nix.
#
# Software also arrives through programs.* options in modules/shell.nix, which
# install a package and write its configuration together. Listing neovim or
# fish here as well would install them twice over.
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
        just
        lazygit
      ]

      # Compilers and build tools
      [
        clang
        cmake
        gcc
        gnumake
        ninja
        pkg-config
        shellcheck
        tree-sitter
      ]

      # Language runtimes and version managers
      [
        bun
        fnm
        nodejs_24
        python3
        rustup
        uv
        yarn-berry
      ]

      # Application development
      [
        bubblewrap
        chromium
        codex
        hyperfine
        openssl
        sqlite
        tokei
        vite-plus
        watchexec
      ]

      # Containers
      [
        docker-compose
        lazydocker
      ]

      # Nix tooling
      [
        nh
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
        atop
        btop
        btrfs-progs
        dmidecode
        fastfetch
        htop
        iotop
        lm_sensors
        lshw
        lsof
        ncdu
        pciutils
        rasdaemon
        smartmontools
        strace
        sysstat
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
