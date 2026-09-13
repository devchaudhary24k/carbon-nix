{
  description = "NixOS configuration for Dev Talan's machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Prisma 5 was removed from nixpkgs after this commit. It is pinned on its
    # own so everything else can keep tracking nixos-26.05.
    nixpkgs-prisma5.url = "github:NixOS/nixpkgs/5005449a6ed0451dbe6d976a254091445e984047";

    # Declarative disk partitioning. hosts/<name>/disks.nix is the only place
    # that describes a machine's disks, for both installing and mounting.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dotfiles = {
      url = "github:devchaudhary24k/dotfiles";
      flake = false;
    };

    lazyvim-starter = {
      url = "github:LazyVim/starter";
      flake = false;
    };
  };

  outputs =
    inputs@{ nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      # Every machine this repo builds. Adding one means adding a line here and
      # a directory under hosts/ with the same name.
      hosts = {
        carbon = "x86_64-linux";
      };

      systems = lib.unique (lib.attrValues hosts);
      forEachSystem = lib.genAttrs systems;
      hostsOn = system: lib.filterAttrs (_: hostSystem: hostSystem == system) hosts;

      # Applied to every host. Anything added here has to work unchanged on a
      # second machine; per-machine facts belong in hosts/<name>/.
      sharedModules = [
        ./modules
        inputs.disko.nixosModules.disko
        inputs.home-manager.nixosModules.home-manager
        { nixpkgs.overlays = [ (import ./packages) ]; }
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = { inherit inputs; };
          };
        }
      ];

      mkHost =
        name: system:
        lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = sharedModules ++ [ ./hosts/${name} ];
        };
    in
    {
      nixosConfigurations = lib.mapAttrs mkHost hosts;

      # Two tests per host. The services test boots the real configuration in a
      # VM with disposable mounts; the disks test builds the real disk layout on
      # a scratch disk and boots from it.
      checks = forEachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        lib.concatMapAttrs (name: _: {
          "${name}-services" = import ./tests/services.nix {
            inherit
              inputs
              name
              pkgs
              sharedModules
              ;
          };
          "${name}-disks" = import ./tests/disks.nix {
            inherit inputs name pkgs;
          };
        }) (hostsOn system)
      );

      formatter = forEachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
