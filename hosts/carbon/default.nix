# Carbon: headless AMD development box, 240 GB SSD plus 1 TB HDD. Always on,
# reached over Tailscale.
#
# Everything here is true of this machine and no other. Anything a second
# machine could reuse belongs in modules/.
{ config, ... }:

{
  imports = [
    ./disks.nix
    ./hardware.nix
  ];

  networking.hostName = "carbon";

  my = {
    dev.enable = true;
    autoUpgrade.enable = true;
    t3code.server.enable = true;
    monitoring.hub.enable = true;

    # Carbon is the always-on machine, so it is the exit node, and it makes
    # the home LAN reachable from anywhere.
    tailscale = {
      exitNode = true;
      subnetRoutes = [ "192.168.31.0/24" ];
    };
  };

  # SSH from the LAN on the wired NIC, as a fallback for when Tailscale is down.
  networking.firewall.interfaces.enp8s0.allowedTCPPorts = [ 22 ];

  swapDevices = [
    {
      # Below zram in priority, so the SSD is only used once compressed RAM is
      # full.
      device = "/swapfile";
      size = 8 * 1024;
      priority = 10;
    }
  ];

  # Writable by the user, on the HDD.
  systemd.tmpfiles.rules = [
    "d /srv/bulk/datasets 2775 ${config.my.user} users -"
    "d /srv/bulk/downloads 2775 ${config.my.user} users -"
  ];

  # Minecraft bots. The account directories under /opt/mcc hold logins and
  # cached session tokens, so they are deliberately not managed by Nix.
  services.minecraft-mcc = {
    enable = true;
    user = config.my.user;
    accounts = {
      dev24k = { };
      devchaudhary24k = { };
      hammersamster = { };
      kartik = { };
    };
  };

  # Set at install time. Leave it alone afterwards; it is not the NixOS
  # version, it records which defaults this installation started with.
  system.stateVersion = "26.05";
}
