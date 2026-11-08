# Nix itself: flakes, garbage collection, the package overlays, and which
# unfree packages are allowed.
{
  config,
  inputs,
  lib,
  ...
}:

{
  options.my.unfree = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      Unfree packages this machine may install, by name. Named one by one
      rather than allowUnfree = true, so a new unfree dependency has to be
      noticed. Modules append the names they need.
    '';
  };

  config = {
    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      trusted-users = [
        "root"
        config.my.user
      ];
    };

    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };

    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) config.my.unfree;

    nixpkgs.overlays = [
      # Packages built in this repo: pkgs.t3code, pkgs.vite-plus, ...
      (import ../../packages)

      # pkgs.unstable.<name> for tools that move faster than a stable release.
      (final: _prev: {
        unstable = import inputs.nixpkgs-unstable {
          inherit (final.stdenv.hostPlatform) system;
          config.allowUnfreePredicate = config.nixpkgs.config.allowUnfreePredicate;
        };
      })
    ];

    # `nixos-version --configuration-revision` then names the commit the
    # running system was built from, with a -dirty suffix when it was built
    # from uncommitted changes. The auto-upgrade guard relies on this.
    system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
  };
}
