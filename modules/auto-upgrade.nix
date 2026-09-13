# Weekly unattended upgrade, with a guard in front of it.
#
# system.autoUpgrade builds from the pushed Git remote, never from the local
# /etc/nixos. On 2026-09-13 that reverted a hand-applied rebuild and removed
# claude-code, dotnet and the mcc-runtime wrapper without warning. The guard
# below refuses to switch while the local checkout still holds work the remote
# has not seen, so the failure is loud instead of silent.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.system.autoUpgrade;
  checkout = "/etc/nixos";

  upgradeGuard = pkgs.writeShellApplication {
    name = "auto-upgrade-guard";
    runtimeInputs = with pkgs; [
      cacert
      git
      openssh
    ];
    text = ''
      checkout=${lib.escapeShellArg checkout}

      if [[ ! -d "$checkout/.git" ]]; then
        echo "$checkout is not a Git checkout, so no local work can be lost."
        exit 0
      fi

      # The checkout belongs to the login user and this runs as root, which git
      # rejects as dubious ownership unless it is told not to.
      in_checkout() {
        git -c safe.directory='*' -C "$checkout" "$@"
      }

      dirty=$(in_checkout status --porcelain)
      if [[ -n "$dirty" ]]; then
        {
          echo "Refusing to upgrade: $checkout has uncommitted changes."
          echo "$dirty"
          echo "Upgrading builds from the remote, so switching now would revert them."
          echo "Commit and push, then run: systemctl start nixos-upgrade"
        } >&2
        exit 1
      fi

      branch=$(in_checkout rev-parse --abbrev-ref HEAD)
      if ! in_checkout fetch --quiet origin "$branch"; then
        echo "Refusing to upgrade: cannot reach origin to compare $branch." >&2
        exit 1
      fi

      localHead=$(in_checkout rev-parse HEAD)
      remoteHead=$(in_checkout rev-parse FETCH_HEAD)
      if [[ "$localHead" != "$remoteHead" ]]; then
        {
          echo "Refusing to upgrade: $checkout does not match origin/$branch."
          echo "  local  $localHead"
          echo "  remote $remoteHead"
          echo "Push the local commits, then run: systemctl start nixos-upgrade"
        } >&2
        exit 1
      fi

      echo "$checkout matches origin/$branch at $localHead."
    '';
  };
in

{
  system.autoUpgrade = {
    enable = lib.mkDefault true;
    flake = lib.mkDefault "github:devchaudhary24k/carbon-nix#${config.networking.hostName}";
    dates = "Sun 04:00";
    randomizedDelaySec = "30m";
    allowReboot = false;
    operation = "switch";
    runGarbageCollection = true;
  };

  # Only attach the guard when the upgrade unit actually exists, otherwise this
  # would define a half-built service on hosts that disable the upgrade.
  systemd.services.nixos-upgrade = lib.mkIf cfg.enable {
    serviceConfig.ExecStartPre = lib.mkBefore [ "${upgradeGuard}/bin/auto-upgrade-guard" ];
  };

  # Running it by hand answers "would the timer switch right now?".
  environment.systemPackages = lib.mkIf cfg.enable [ upgradeGuard ];
}
