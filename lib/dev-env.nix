# Build and runtime environment for Node native modules, Prisma, and headless
# Chromium.
#
# modules/dev-runtime.nix exports these as system session variables and the
# Home Manager systemd drop-in reads the same attribute set, so a shell and a
# user service can never end up with different values.
{
  inputs,
  lib,
  pkgs,
}:

let
  prismaEngines =
    inputs.nixpkgs-prisma5.legacyPackages.${pkgs.stdenv.hostPlatform.system}.prisma-engines;

  # Headers and pkg-config files node-gyp needs to build canvas, sharp and
  # similar packages. On NixOS these are not in /usr/include, so the paths have
  # to be handed to the compiler explicitly.
  nativeLibraries = with pkgs; [
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

  # What a downloaded Chromium needs at runtime. A tool that ships its own
  # browser, such as the T3 agent runtime, runs that binary through nix-ld
  # rather than the store copy the variables below point at, so without these
  # it stops at the first missing library instead of opening a page.
  # `includePath` and `pkgConfigPath` leave them out: these are runtime
  # libraries, not headers node-gyp compiles against.
  browserLibraries = with pkgs; [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cups
    dbus
    expat
    libdrm
    libgbm
    libxkbcommon
    libxshmfence
    nspr
    nss
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXi
    xorg.libXrandr
    xorg.libXrender
    xorg.libXtst
    xorg.libxcb
  ];

  includePath = lib.makeSearchPathOutput "dev" "include" nativeLibraries;
  pkgConfigPath = lib.makeSearchPathOutput "dev" "lib/pkgconfig" nativeLibraries;
in

{
  inherit nativeLibraries browserLibraries;

  variables = {
    C_INCLUDE_PATH = includePath;
    CPLUS_INCLUDE_PATH = includePath;
    PKG_CONFIG_PATH = pkgConfigPath;

    # Prisma downloads its engines at install time, and those downloads do not
    # run on NixOS. Point it at the pinned store copies instead.
    PRISMA_FMT_BINARY = "${prismaEngines}/bin/prisma-fmt";
    PRISMA_QUERY_ENGINE_BINARY = "${prismaEngines}/bin/query-engine";
    PRISMA_QUERY_ENGINE_LIBRARY = "${prismaEngines}/lib/libquery_engine.node";
    PRISMA_SCHEMA_ENGINE_BINARY = "${prismaEngines}/bin/schema-engine";

    # Same problem, same fix: the browsers Playwright and Puppeteer download are
    # dynamically linked against an FHS that does not exist here.
    PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "true";
    PUPPETEER_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
    PUPPETEER_SKIP_CHROMIUM_DOWNLOAD = "true";
    PUPPETEER_SKIP_DOWNLOAD = "true";
  };
}
