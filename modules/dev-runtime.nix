# Makes downloaded, dynamically linked binaries run, and points Node tooling at
# the Nix store.
#
# NixOS has no /usr/lib and no real /lib, so a binary from a vendor installer
# cannot find its loader and fails with "No such file or directory". nix-ld
# installs a shim at /lib64/ld-linux-x86-64.so.2 that supplies the libraries
# listed below. A host that needs more can append to programs.nix-ld.libraries.
{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  devEnv = import ../lib/dev-env.nix { inherit inputs lib pkgs; };
in

{
  programs.nix-ld = {
    enable = true;
    libraries = devEnv.nativeLibraries;
  };

  environment.sessionVariables = devEnv.variables;
}
