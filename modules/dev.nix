# Everything for writing and running code: compilers, language runtimes,
# coding agents, Docker, and nix-ld for binaries that were not built by Nix.
#
# Databases are not installed on the machine. Each project runs its own in
# Docker, so versions never clash between projects.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.dev;
in

{
  options.my.dev.enable = lib.mkEnableOption "development tools";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = lib.flatten (
      with pkgs;
      [
        # Compilers and build tools
        [
          clang
          cmake
          gcc
          gnumake
          just
          ninja
          pkg-config
          shellcheck
          tree-sitter
        ]

        # Language runtimes and package managers
        [
          bun
          fnm
          nodejs_24
          pnpm
          python3
          ruff
          rustup
          uv
          yarn-berry
        ]

        # Coding agents. These release every few days, so they come from
        # nixos-unstable instead of the stable release.
        [
          unstable.claude-code
          unstable.codex
        ]

        # Application development
        [
          chromium
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

        # Nix development
        [
          nil
          nixfmt
        ]
      ]
    );

    my.unfree = [ "claude-code" ];

    # Switches Node versions per project from .nvmrc / .node-version.
    programs.fish.interactiveShellInit = ''
      ${pkgs.fnm}/bin/fnm env --use-on-cd --shell fish | source
    '';

    virtualisation.docker = {
      enable = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
        # Images unused for a week. Volumes, where project data lives, are
        # never pruned automatically.
        flags = [
          "--all"
          "--filter=until=168h"
        ];
      };
    };
    users.users.${config.my.user}.extraGroups = [ "docker" ];

    # NixOS has no /usr/lib and no real /lib, so a binary downloaded by npm,
    # pip or a vendor installer cannot find its libraries and fails with "No
    # such file or directory". nix-ld puts a loader at the usual place and
    # hands it the libraries below. Together they cover Prisma's engines,
    # Playwright and Puppeteer browsers, sharp, canvas, Electron and most
    # prebuilt Node and Python wheels. When something still fails on a
    # missing .so, add the package that ships it here and rebuild.
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc.lib
        zlib
        zstd
        bzip2
        xz
        openssl
        curl
        icu
        libuuid
        libxml2
        libsodium
        util-linux
        systemd
        attr
        acl

        # Graphics and fonts (canvas, sharp, headless browsers)
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

        # Headless Chromium, as downloaded by Playwright and Puppeteer
        alsa-lib
        at-spi2-atk
        at-spi2-core
        atk
        cups
        dbus
        expat
        gtk3
        libdrm
        libgbm
        libxkbcommon
        nspr
        nss
        libx11
        libxcomposite
        libxdamage
        libxext
        libxfixes
        libxrandr
        libxcb
        libxshmfence
      ];
    };
  };
}
