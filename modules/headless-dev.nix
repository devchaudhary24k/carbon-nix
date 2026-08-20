{ lib, pkgs, ... }:

{
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "Sun 06:00";
    options = "--delete-older-than 14d";
  };

  programs = {
    direnv.enable = true;

    # fnm downloads ordinary dynamically linked Linux Node binaries. Let
    # those binaries run on NixOS while the T3 service keeps using Nix Node.
    nix-ld.enable = true;

    fish = {
      enable = true;
      interactiveShellInit = ''
        ${pkgs.fnm}/bin/fnm env --use-on-cd --shell fish | source
      '';
      shellAliases = {
        ll = "eza --long --all --group-directories-first";
        rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#carbon";
      };
    };

    fzf = {
      fuzzyCompletion = true;
      keybindings = true;
    };

    neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
    };

    # Fish initializes Starship and Zoxide from the user's dotfiles.
    ssh.startAgent = true;
    yazi.enable = true;
  };

  # Match the socket path exported by the Fish dotfiles.
  systemd.user.services.ssh-agent.serviceConfig = {
    ExecStartPre = lib.mkForce "${pkgs.coreutils}/bin/rm -f %t/ssh-agent.socket";
    ExecStart = lib.mkForce "${pkgs.openssh}/bin/ssh-agent -a %t/ssh-agent.socket";
  };

  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "Sun 05:30";
      # Remove only objects unused for at least seven days. Volumes are never
      # pruned automatically because they can contain development data.
      flags = [
        "--all"
        "--filter=until=168h"
      ];
    };
  };

  networking.firewall = {
    enable = true;
    logRefusedConnections = false;
    interfaces = {
      enp8s0.allowedTCPPorts = [ 22 ];
      tailscale0.allowedTCPPorts = [ 22 ];
    };
  };

  environment.systemPackages = with pkgs; [
    bat
    bind
    btop
    btrfs-progs
    clang
    cmake
    codex
    curl
    delta
    dmidecode
    docker-compose
    ethtool
    eza
    fd
    file
    fnm
    gcc
    git
    git-lfs
    gnumake
    gh
    htop
    hyperfine
    inetutils
    iotop
    iperf3
    jq
    just
    lazydocker
    lazygit
    lshw
    lm_sensors
    lsof
    mtr
    ncdu
    nh
    ninja
    nix-output-monitor
    nmap
    nodejs_24
    nvd
    openssl
    pciutils
    pkg-config
    python3
    rclone
    restic
    ripgrep
    rsync
    rustup
    shellcheck
    sqlite
    starship
    stow
    socat
    strace
    tcpdump
    tmux
    tokei
    tree
    tree-sitter
    unzip
    usbutils
    uv
    watchexec
    websocat
    wget
    xh
    zip
    zoxide
  ];
}
