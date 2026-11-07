# T3 Code, either as a background server (for a machine you reach remotely)
# or as the desktop app (for the machine you sit at), or both.
#
# The server runs as a systemd user service for the main user, because it
# starts each agent in its own `systemd-run --user` scope. Lingering keeps the
# user's service manager, and so the server, running without a login.
#
# Settings such as LAN access and T3 Connect live in ~/.t3 and are changed
# from the app or with `t3 up`. Updates come from this repo
# (packages/t3code/update.sh), not from `t3 update`.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.t3code;
  user = config.my.user;
in

{
  options.my.t3code = {
    server = {
      enable = lib.mkEnableOption "the T3 Code server as a background service";

      port = lib.mkOption {
        type = lib.types.port;
        default = 3773;
        description = "Port the server listens on.";
      };
    };

    desktop.enable = lib.mkEnableOption "the T3 Code desktop app";
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.server.enable || cfg.desktop.enable) {
      # The `t3` CLI: threads, projects, pairing, status.
      environment.systemPackages = [ pkgs.t3code ];
    })

    (lib.mkIf cfg.desktop.enable {
      environment.systemPackages = [ pkgs.t3code-desktop ];
    })

    (lib.mkIf cfg.server.enable {
      users.users.${user}.linger = true;

      systemd.user.services.t3code = {
        description = "T3 Code server";
        wantedBy = [ "default.target" ];
        unitConfig = {
          ConditionUser = user;
          StartLimitIntervalSec = 300;
          StartLimitBurst = 5;
        };

        # Agents and terminals inherit this, so it has to find everything a
        # login shell would: setuid wrappers (sudo), the user's Home Manager
        # packages, and the system profile.
        path = [
          "/run/wrappers"
          "/etc/profiles/per-user/${user}"
          "/run/current-system/sw"
        ];

        environment = {
          T3CODE_HOME = "%h/.t3";
          T3_BOOT_SERVICE_UNIT = "t3code.service";
        }
        // lib.optionalAttrs config.programs.nix-ld.enable {
          # Prebuilt binaries that agents download (npm, pip) need the
          # loader shim, which login shells get from /etc/profile.
          NIX_LD = "/run/current-system/sw/share/nix-ld/lib/ld.so";
          NIX_LD_LIBRARY_PATH = "/run/current-system/sw/share/nix-ld/lib";
        };

        serviceConfig = {
          Type = "simple";
          WorkingDirectory = "%h";
          ExecStart = "${pkgs.t3code}/bin/t3 serve --port ${toString cfg.server.port}";
          Restart = "always";
          RestartSec = 5;
          # Agents run in their own scopes and survive a server restart.
          KillMode = "mixed";
          OOMPolicy = "continue";
          ManagedOOMPreference = "avoid";
          CPUWeight = 1000;
          IOWeight = 1000;
        };
      };
    })
  ];
}
