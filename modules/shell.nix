# Interactive shell and editor. These use programs.* rather than a package in
# modules/packages.nix because each option installs the program and writes its
# configuration in one place.
{ lib, pkgs, ... }:

{
  programs = {
    direnv.enable = true;

    fish = {
      enable = true;
      interactiveShellInit = ''
        ${pkgs.fnm}/bin/fnm env --use-on-cd --shell fish | source
      '';
      shellAliases = {
        ll = "eza --long --all --group-directories-first";
        rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#$hostname";
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
  };

  # The stock unit leaves a stale socket behind after an unclean logout, which
  # then makes the next ssh-add fail.
  systemd.user.services.ssh-agent.serviceConfig = {
    ExecStartPre = lib.mkForce "${pkgs.coreutils}/bin/rm -f %t/ssh-agent.socket";
    ExecStart = lib.mkForce "${pkgs.openssh}/bin/ssh-agent -a %t/ssh-agent.socket";
  };
}
