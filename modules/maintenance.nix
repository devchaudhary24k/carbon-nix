{ ... }:

{
  system.autoUpgrade = {
    enable = true;
    flake = "github:devchaudhary24k/carbon-nix#carbon";
    dates = "Sun 04:00";
    randomizedDelaySec = "30m";
    allowReboot = false;
    operation = "switch";
    runGarbageCollection = true;
  };
}
