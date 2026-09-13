# Packages this repo builds itself, exposed as an overlay so they can be used
# as pkgs.<name> anywhere in the configuration.
final: _prev: {
  vite-plus = final.callPackage ./vite-plus { };
}
