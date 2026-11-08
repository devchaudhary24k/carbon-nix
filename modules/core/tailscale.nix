# Tailscale on every machine, with the features worth having day to day.
#
#   MagicDNS        reach machines by name: ssh carbon, http://carbon:3000
#   Tailscale SSH   log in with your Tailscale identity, no keys to copy
#   Taildrop        files sent from the phone or another machine land in
#                   ~/Downloads/Taildrop
#   Exit node       a host can offer itself as a VPN (my.tailscale.exitNode)
#   Subnet router   a host can expose its LAN to the tailnet
#                   (my.tailscale.subnetRoutes)
#   Serve / Funnel  share a local port over HTTPS, inside the tailnet or
#                   publicly: tailscale serve 3000, tailscale funnel 3000
#
# Settings below are applied with `tailscale set` on every boot, so they stay
# true even after a reinstall. Logging in is still one manual step:
# sudo tailscale up
{ config, lib, ... }:

let
  cfg = config.my.tailscale;
  advertises = cfg.exitNode || cfg.subnetRoutes != [ ];
in

{
  options.my.tailscale = {
    exitNode = lib.mkEnableOption ''
      offering this machine as an exit node. Approve it once in the admin
      console, then other devices can send all their traffic through it
    '';

    subnetRoutes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "192.168.31.0/24" ];
      description = ''
        LAN ranges this machine makes reachable over the tailnet. Approve them
        once in the admin console.
      '';
    };

    acceptRoutes = lib.mkEnableOption ''
      using subnet routes other machines advertise. Leave this off on a
      machine that usually sits on the advertised LAN itself, or its LAN
      traffic takes a detour through the router
    '';
  };

  config = {
    services.tailscale = {
      enable = true;
      openFirewall = true;
      # "client" lets this machine use exit nodes; "both" also lets it act as
      # one or as a subnet router.
      useRoutingFeatures = if advertises then "both" else "client";
      extraSetFlags = [
        "--ssh"
        "--operator=${config.my.user}"
        "--accept-routes=${lib.boolToString cfg.acceptRoutes}"
        "--advertise-exit-node=${lib.boolToString cfg.exitNode}"
        "--advertise-routes=${lib.concatStringsSep "," cfg.subnetRoutes}"
      ];
    };

    # Every port is open to your own tailnet devices and to nothing else, so a
    # dev server is reachable from the other machine without editing the
    # firewall each time a project picks a new port.
    networking.firewall.trustedInterfaces = [ "tailscale0" ];

    # Receives Taildrop files without having to run `tailscale file get`.
    systemd.user.services.taildrop = {
      description = "Receive Taildrop files into ~/Downloads/Taildrop";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = config.my.user;
      serviceConfig = {
        ExecStartPre = "/run/current-system/sw/bin/mkdir -p %h/Downloads/Taildrop";
        ExecStart = "${config.services.tailscale.package}/bin/tailscale file get --loop --conflict=rename %h/Downloads/Taildrop";
        Restart = "on-failure";
        RestartSec = 30;
      };
    };
  };
}
