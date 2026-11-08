# Beszel: a small dashboard with history and alerts for every machine.
#
# One machine runs the hub (the web UI, on port 8090, reachable over the
# tailnet). Every machine runs an agent that the hub pulls CPU, memory, disk,
# network, temperature, GPU and Docker container stats from.
#
# Setup after the hub's first start:
#   1. Open http://carbon:8090 and create the admin account.
#   2. Click "Add system". The dialog shows the hub's public key.
#   3. Paste that key into hubKey below, rebuild every machine.
#   4. Back in the dialog, add each machine by its Tailscale name, port 45876.
{ config, lib, ... }:

let
  cfg = config.my.monitoring;
in

{
  options.my.monitoring = {
    hub.enable = lib.mkEnableOption "the Beszel hub (the dashboard) on this machine";

    hubKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      # A public key, so it is safe to commit.
      default = null;
      example = "ssh-ed25519 AAAA...";
      description = ''
        The hub's public key, shown in its "Add system" dialog. The agent on
        each machine only answers a hub holding the matching private key, and
        stays off until this is set.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.hub.enable {
      services.beszel.hub = {
        enable = true;
        host = "0.0.0.0";
        port = 8090;
      };
    })

    (lib.mkIf (cfg.hubKey != null) {
      services.beszel.agent = {
        enable = true;
        smartmon.enable = true;
        environment = {
          KEY = cfg.hubKey;
          LISTEN = "45876";
        };
        extraPath = lib.optional config.hardware.nvidia.enabled config.hardware.nvidia.package.bin;
      };

      # Container stats.
      systemd.services.beszel-agent.serviceConfig.SupplementaryGroups =
        lib.optional config.virtualisation.docker.enable "docker";
    })

    {
      warnings = lib.optional (cfg.hubKey == null) ''
        my.monitoring.hubKey is not set, so the Beszel agent is off on
        ${config.networking.hostName}. See modules/core/monitoring.nix.
      '';
    }
  ];
}
