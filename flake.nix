{
  description = "NixOS configuration for the carbon development machine";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-prisma5.url = "github:NixOS/nixpkgs/5005449a6ed0451dbe6d976a254091445e984047";

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

  outputs = inputs@{ home-manager, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      carbonModules = [
        ./hosts/carbon
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = { inherit inputs; };
            users.dev24k = import ./home/dev24k.nix;
          };
        }
      ];
    in
    {
      nixosConfigurations.carbon = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [ ./hosts/carbon/hardware-configuration.nix ] ++ carbonModules;
      };

      checks.${system}.carbon-vm = import ./tests/carbon-vm.nix {
        inherit carbonModules pkgs;
      };
    };
}
