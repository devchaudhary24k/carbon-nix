# Packages this repo builds itself, exposed as an overlay so they can be used
# as pkgs.<name> anywhere in the configuration.
final: _prev: {
  minecraft-console-client = final.callPackage ./minecraft-console-client { };
  t3code = final.callPackage ./t3code { };
  t3code-desktop = final.callPackage ./t3code/desktop.nix { };
  vite-plus = final.callPackage ./vite-plus { };
}
