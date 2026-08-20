{ inputs, pkgs, ... }:

{
  home = {
    username = "dev24k";
    homeDirectory = "/home/dev24k";
    stateVersion = "26.05";

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

      # T3 starts from the lingering user systemd manager, not a login shell.
      # Pin Nix Node/npm for its updater and pass nix-ld through to terminals
      # so project-specific Node versions downloaded by fnm work on NixOS.
      "systemd/user/t3code.service.d/10-nixos-compat.conf".text = ''
        [Service]
        Environment="PATH=${pkgs.nodejs_24}/bin:/run/wrappers/bin:/etc/profiles/per-user/dev24k/bin:/run/current-system/sw/bin"
        Environment="NIX_LD=/run/current-system/sw/share/nix-ld/lib/ld.so"
        Environment="NIX_LD_LIBRARY_PATH=/run/current-system/sw/share/nix-ld/lib"
      '';
    };
  };

  programs.home-manager.enable = true;
}
