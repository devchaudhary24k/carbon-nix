{ inputs, ... }:

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
    };
  };

  programs.home-manager.enable = true;
}
