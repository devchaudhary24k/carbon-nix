{ inputs, lib, pkgs, ... }:

let
  nodeNativeLibraries = with pkgs; [
    cairo
    fontconfig
    freetype
    gdk-pixbuf
    giflib
    glib
    harfbuzz
    libjpeg
    libpng
    librsvg
    pango
    pixman
  ];
  nodeNativeIncludePath =
    lib.makeSearchPathOutput "dev" "include" nodeNativeLibraries;
  nodeNativePkgConfigPath =
    lib.makeSearchPathOutput "dev" "lib/pkgconfig" nodeNativeLibraries;
in

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

      "systemd/user/t3code.service.d/10-nixos-compat.conf".text = ''
        [Service]
        Environment="PATH=${pkgs.nodejs_24}/bin:/run/wrappers/bin:/etc/profiles/per-user/dev24k/bin:/run/current-system/sw/bin"
        Environment="NIX_LD=/run/current-system/sw/share/nix-ld/lib/ld.so"
        Environment="NIX_LD_LIBRARY_PATH=/run/current-system/sw/share/nix-ld/lib"
        Environment="C_INCLUDE_PATH=${nodeNativeIncludePath}"
        Environment="CPLUS_INCLUDE_PATH=${nodeNativeIncludePath}"
        Environment="PKG_CONFIG_PATH=${nodeNativePkgConfigPath}"
        Environment="PUPPETEER_EXECUTABLE_PATH=${pkgs.chromium}/bin/chromium"
        Environment="PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true"
        Environment="PUPPETEER_SKIP_DOWNLOAD=true"
      '';
    };
  };

  programs.home-manager.enable = true;
}
