# Unattended deploys from GitHub, for machines that are always on.
#
# Every night the machine builds github:devchaudhary24k/carbon-nix (the main
# branch) and switches to it. It never reads a local checkout, so a change has
# to be pushed to reach the machine, and a change that was only rebuilt by hand
# would be reverted. On 2026-09-13 that removed claude-code, dotnet and the
# mcc-runtime wrapper, which had been rebuilt by hand and never committed.
#
# The guard below stops that. It refuses to switch while the running system
# was built from uncommitted changes, or from a commit that is not on main
# yet, and says why in the journal:
#   journalctl -u nixos-upgrade
#
# This does not update flake.lock. Package updates arrive when flake.lock is
# updated and pushed: nix flake update && git commit -am "Update inputs".
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.autoUpgrade;

  upgradeGuard = pkgs.writeShellApplication {
    name = "auto-upgrade-guard";
    runtimeInputs = with pkgs; [
      cacert
      coreutils
      git
    ];
    text = ''
      remote=${lib.escapeShellArg cfg.repository}
      branch=${lib.escapeShellArg cfg.branch}
      cache=/var/cache/auto-upgrade-guard/repo.git

      running=$(/run/current-system/sw/bin/nixos-version --configuration-revision 2>/dev/null || true)

      refuse() {
        {
          echo "Refusing to upgrade: $1"
          echo "Commit and push your changes to $branch, rebuild once, and the upgrade runs again."
          echo "To deploy $branch anyway: sudo nixos-rebuild switch --flake github:$remote/$branch#${config.networking.hostName}"
        } >&2
        exit 1
      }

      case "$running" in
        "") refuse "the running system does not record which commit it was built from." ;;
        *-dirty) refuse "the running system was built from uncommitted changes ($running)." ;;
      esac

      if [[ ! -d "$cache" ]]; then
        mkdir -p "$(dirname "$cache")"
        git init --quiet --bare "$cache"
      fi
      if ! git -C "$cache" fetch --quiet --force "https://github.com/$remote" "$branch:refs/heads/$branch"; then
        refuse "cannot reach github.com/$remote to compare."
      fi

      if ! git -C "$cache" merge-base --is-ancestor "$running" "$branch" 2>/dev/null; then
        refuse "the running system was built from $running, which is not on $branch."
      fi

      echo "Running system ($running) is on $branch. Upgrading."
    '';
  };
in

{
  options.my.autoUpgrade = {
    enable = lib.mkEnableOption "nightly unattended deploys from GitHub";

    repository = lib.mkOption {
      type = lib.types.str;
      default = "devchaudhary24k/carbon-nix";
      description = "GitHub owner/repo to deploy from.";
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "Branch to deploy.";
    };
  };

  config = lib.mkIf cfg.enable {
    system.autoUpgrade = {
      enable = true;
      flake = "github:${cfg.repository}/${cfg.branch}#${config.networking.hostName}";
      dates = "04:00";
      randomizedDelaySec = "30m";
      allowReboot = false;
      operation = "switch";
    };

    systemd.services.nixos-upgrade.serviceConfig.ExecStartPre = lib.mkBefore [
      "${upgradeGuard}/bin/auto-upgrade-guard"
    ];

    # Running it by hand answers "would tonight's upgrade go ahead?".
    environment.systemPackages = [ upgradeGuard ];
  };
}
