# The one login user, the same on every machine, and their Home Manager setup.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  user = config.my.user;
in

{
  users.users.${user} = {
    isNormalUser = true;
    description = "Dev Talan";
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];

    # One key per machine you log in from. Removing a line locks that
    # machine out on the next rebuild.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINgrNQxV5Klb6/QSnF9QNwYGTxmtXFZ3AnMlQNd4jwVS"
      # nukebyte
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM83BbRGFih1A0aYu5K/vFG80IyYUtwzgVEWt6u76gOz"
    ];
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    # A file Home Manager wants to manage but finds already there is moved
    # aside instead of failing the activation.
    backupFileExtension = "hm-backup";
    users.${user} = import ../../home/${user};
  };

  # Lets `nh os switch` and friends find the repo without a path argument.
  programs.nh = {
    enable = true;
    flake = lib.mkDefault "/home/${user}/code/carbon-nix";
  };
}
