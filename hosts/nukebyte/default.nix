# Nukebyte: the laptop, docked almost all the time with two external
# monitors. The 1440p monitor on USB-C is driven by the NVIDIA GPU, the
# portrait one on HDMI by the AMD iGPU.
#
# Everything here is true of this machine and no other. Anything a second
# machine could reuse belongs in modules/.
{
  imports = [
    ./disks.nix
    ./hardware.nix
  ];

  networking.hostName = "nukebyte";

  my = {
    dev.enable = true;
    desktop.enable = true;
    gaming.enable = true;
    secureBoot.enable = true;
    # The app runs its own local server and can also connect to carbon's.
    t3code.desktop.enable = true;
    # Upgrades only when you run them: rebuild, or nh os switch.
    autoUpgrade.enable = false;
  };

  swapDevices = [
    {
      # Inside the encrypted root, below zram in priority. No hibernation, so
      # it does not need to match RAM size; 16 GB just gives headroom for
      # large builds.
      device = "/swapfile";
      size = 16 * 1024;
      priority = 10;
    }
  ];

  # Set at install time. Leave it alone afterwards; it is not the NixOS
  # version, it records which defaults this installation started with.
  system.stateVersion = "26.05";
}
