# Interactive shell and editor. These use programs.* rather than a package in
# packages.nix because each option installs the program and writes its
# configuration in one place. The user-level config (fish functions, starship,
# nvim) comes from Home Manager.
{ lib, pkgs, ... }:

{
  programs = {
    direnv.enable = true;

    fish = {
      enable = true;
      shellAliases = {
        ll = "eza --long --all --group-directories-first";
        # Builds, shows what changed, then switches. Reads the repo path from
        # programs.nh.flake.
        rebuild = "nh os switch";
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

    yazi.enable = true;

    ssh.startAgent = true;
  };

  # The stock unit leaves a stale socket behind after an unclean logout, which
  # then makes the next ssh-add fail.
  systemd.user.services.ssh-agent.serviceConfig = {
    ExecStartPre = lib.mkForce "${pkgs.coreutils}/bin/rm -f %t/ssh-agent.socket";
    ExecStart = lib.mkForce "${pkgs.openssh}/bin/ssh-agent -a %t/ssh-agent.socket";
  };
}
