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

  virtualisation.docker.enable = true;

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
    inetutils
    jq
    just
    lazydocker
    lazygit
    lshw
    lm_sensors
    mtr
    ninja
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
    tcpdump
    tmux
    tree
    tree-sitter
    unzip
    usbutils
    uv
    wget
    zip
    zoxide
  ];
}
