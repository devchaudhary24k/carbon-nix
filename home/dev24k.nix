# Home Manager configuration for dev24k.
#
# Packages here land in /etc/profiles/per-user/dev24k/bin and are only on this
# user's PATH. System-wide tools belong in modules/packages.nix instead.
{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  username = "dev24k";
  devEnv = import ../lib/dev-env.nix { inherit inputs lib pkgs; };

  # A systemd user service starts without a login shell, so it never sees
  # environment.sessionVariables. Give it the same values plus the paths
  # systemd has to be told about explicitly.
  serviceEnvironment = devEnv.variables // {
    PATH = lib.concatStringsSep ":" [
      "${pkgs.nodejs_24}/bin"
      "/run/wrappers/bin"
      "/etc/profiles/per-user/${username}/bin"
      "/run/current-system/sw/bin"
    ];
    NIX_LD = "/run/current-system/sw/share/nix-ld/lib/ld.so";
    NIX_LD_LIBRARY_PATH = "/run/current-system/sw/share/nix-ld/lib";
  };

  environmentLines = lib.concatLines (
    lib.mapAttrsToList (name: value: ''Environment="${name}=${value}"'') serviceEnvironment
  );
in

{
  home = {
    inherit username;
    homeDirectory = "/home/${username}";
    stateVersion = "26.05";

    packages = [ pkgs.claude-code ];

    file.".gitconfig".source = "${inputs.dotfiles}/home/git/.gitconfig";
  };

  xdg = {
    enable = true;
    configFile = {
      "fish" = {
        source = "${inputs.dotfiles}/home/fish/.config/fish";
        recursive = true;
      };
      "git/ignore".source = "${inputs.dotfiles}/home/git/.config/git/ignore";
      "nvim".source = inputs.lazyvim-starter;
      "starship.toml".source = "${inputs.dotfiles}/home/starship/.config/starship.toml";

      "systemd/user/t3code.service.d/10-nixos-compat.conf".text = ''
        [Service]
        ${environmentLines}
      '';
    };
  };

  programs.home-manager.enable = true;
}
