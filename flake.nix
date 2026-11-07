{
  description = "NixOS configuration for Dev Talan's machines";

  inputs = {
    # The OS follows a stable release branch. It keeps receiving security fixes;
    # flake.lock pins the exact commit and `nix flake update` moves it forward.
    # Moving to the next release (every May and November) means changing this
    # one line.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Fast-moving tools (claude-code, codex) come from here as pkgs.unstable.*,
    # so they stay current without moving the whole OS onto a rolling release.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Declarative disk partitioning. hosts/<name>/disks.nix is the only place
    # that describes a machine's disks, for both installing and mounting.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Manages the user's home directory: dotfiles, user packages, user services.
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secure Boot for NixOS. Signs the kernel and initrd with keys that live on
    # the machine.
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Community-maintained hardware profiles (GPU bus IDs, ASUS daemons, ...).
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
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
        nukebyte = "x86_64-linux";
      };

      systems = lib.unique (lib.attrValues hosts);
      forEachSystem = lib.genAttrs systems;
      hostsOn = system: lib.filterAttrs (_: hostSystem: hostSystem == system) hosts;

      # Every host imports all of modules/. Each feature there is off until a
      # host switches it on with my.<feature>.enable.
      sharedModules = [
        ./modules
        inputs.disko.nixosModules.disko
        inputs.home-manager.nixosModules.home-manager
        inputs.lanzaboote.nixosModules.lanzaboote
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

      # The services test boots each host's real configuration in a VM. The
      # disks test builds carbon's real disk layout on scratch disks and boots
      # from it.
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
        }) (hostsOn system)
        // lib.optionalAttrs (system == hosts.carbon) {
          carbon-disks = import ./tests/disks.nix { inherit inputs pkgs; };
        }
      );

      formatter = forEachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
