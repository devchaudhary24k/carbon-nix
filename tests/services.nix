# Boots a host's real configuration in a VM and checks that the services it
# claims to run actually come up.
#
# Disks are the one thing this cannot test: the qemu-vm module replaces
# fileSystems wholesale with its own scratch disk. tests/disks.nix covers the
# layout separately.
{
  inputs,
  name,
  pkgs,
  sharedModules,
}:

let
  # The overlay in packages/ is what puts vite-plus into pkgs. Applying it here
  # too keeps the expected version tied to the package rather than a literal
  # that silently goes stale after an upgrade.
  vitePlusVersion = (pkgs.extend (import ../packages)).vite-plus.version;
in

pkgs.testers.runNixOSTest {
  name = "${name}-services";

  # By default each node reuses the caller's package set and nixpkgs.config
  # becomes read-only. This host sets both an overlay (for vite-plus) and an
  # allowUnfreePredicate (for claude-code), so the node has to evaluate its own.
  node.pkgsReadOnly = false;

  nodes.machine =
    { lib, ... }:
    {
      _module.args = { inherit inputs; };

      imports = sharedModules ++ [ ../hosts/${name} ];

      virtualisation = {
        cores = 2;
        diskSize = 4096;
        graphics = false;
        memorySize = 3072;
      };

      # Stand-ins for the two real disks. The qemu-vm module discards every
      # fileSystems entry the host declares, so these have to be re-added here.
      virtualisation.fileSystems."/srv/bulk" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "mode=0755" ];
      };
      virtualisation.fileSystems."/mnt/btrfs-root" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "mode=0755" ];
      };
      swapDevices = lib.mkForce [ ];

      # The upgrade service and its guard stay defined so the test can exercise
      # them, but the timer is unhooked: it is persistent, and a VM booting with
      # a stale clock would otherwise start a real upgrade.
      systemd.timers.nixos-upgrade.wantedBy = lib.mkForce [ ];

      # Btrfs operations need real disks.
      services.btrbk.instances = lib.mkForce { };
      services.btrfs.autoScrub.enable = lib.mkForce false;
      systemd.services."btrbk-${name}".enable = lib.mkForce false;

      # Meaningful on physical hardware, not in QEMU.
      boot.loader.systemd-boot.enable = lib.mkForce false;
      boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
      hardware.rasdaemon.enable = lib.mkForce false;
      services.fwupd.enable = lib.mkForce false;
      services.smartd.enable = lib.mkForce false;
    };

  testScript =
    { nodes, ... }:
    let
      user = nodes.machine.machine.primaryUser;
      bulk = nodes.machine.machine.bulkPath;
    in
    ''
      machine.start()
      machine.wait_for_unit("multi-user.target")

      for unit in [
          "sshd.service",
          "docker.service",
          "postgresql.service",
          "mysql.service",
          "redis.service",
          "tailscaled.service",
          "home-manager-${user}.service",
          "bulk-directory-setup.service",
      ]:
          machine.wait_for_unit(unit)

      with subtest("databases answer"):
          machine.succeed("psql --version | grep -E 'PostgreSQL\\) 18\\.'")
          machine.succeed("sudo -u postgres createdb vector_test")
          machine.succeed(
              "sudo -u postgres psql --dbname vector_test --set ON_ERROR_STOP=1 "
              "--command=\"CREATE EXTENSION vector; SELECT '[1,2,3]'::vector(3);\" "
              "| grep -F '[1,2,3]'"
          )
          machine.succeed("mariadb --batch --skip-column-names --execute 'SELECT 1' | grep -x 1")
          machine.succeed("valkey-cli ping | grep -x PONG")

      with subtest("containers"):
          machine.succeed("docker info >/dev/null")
          machine.succeed("systemctl is-enabled docker-prune.timer | grep -x enabled")

      with subtest("the single package list is installed"):
          for command in [
              "nh", "nvd", "nom", "lsof", "strace", "iotop", "ncdu",
              "hyperfine", "watchexec", "tokei", "xh", "websocat", "socat",
              "nmap", "iperf3", "bun", "yarn", "codex", "atop", "sar",
              "smartctl", "bwrap",
          ]:
              machine.succeed(f"command -v {command}")
          machine.succeed("vp --version | grep -F 'vp v${vitePlusVersion}'")

      with subtest("per-user packages reach the user, not the system"):
          machine.succeed("test -x /etc/profiles/per-user/${user}/bin/claude")
          machine.fail("test -e /run/current-system/sw/bin/claude")

      with subtest("home manager and dotfiles"):
          machine.succeed("test -e /home/${user}/.config/fish/config.fish")
          machine.succeed(
              "runuser -u ${user} -- fish -c "
              "'type -q fnm; and type -q starship; and type -q zoxide'"
          )
          machine.succeed("grep -q 'ssh-ed25519' /etc/ssh/authorized_keys.d/${user}")

      with subtest("the upgrade guard refuses to discard local work"):
          machine.succeed("command -v auto-upgrade-guard")
          # No checkout at all is not something the guard should block on.
          machine.succeed("auto-upgrade-guard")

          machine.succeed(
              "mkdir -p /etc/nixos && git -c init.defaultBranch=main -C /etc/nixos init -q "
              "&& git -C /etc/nixos config user.email test@example.com "
              "&& git -C /etc/nixos config user.name Test"
          )
          machine.succeed("touch /etc/nixos/flake.nix")
          # An uncommitted file is exactly the case that lost claude-code.
          machine.fail("auto-upgrade-guard")
          machine.succeed(
              "git -C /etc/nixos add -A && git -C /etc/nixos commit -qm test"
          )
          # Committed but with no reachable remote is still refused, because the
          # upgrade would build the remote's version instead.
          machine.fail("auto-upgrade-guard")

      with subtest("health check runs every branch without a heartbeat"):
          machine.succeed("systemctl is-enabled health-monitor.timer | grep -x enabled")
          machine.succeed("command -v health-check")
          machine.succeed(
              "install -d -m 0700 /tmp/health-credentials /var/lib/health-monitor"
          )
          machine.succeed(
              "printf '%s\\n' 'https://uptime.betterstack.com/api/v1/heartbeat/test-token' "
              "> /tmp/health-credentials/heartbeat-url"
          )
          status, _ = machine.execute(
              "CREDENTIALS_DIRECTORY=/tmp/health-credentials "
              "HEALTH_CHECK_DRY_RUN=1 health-check "
              "> /tmp/health.stdout 2> /tmp/health.stderr"
          )
          if status != 0:
              stdout = machine.succeed("cat /tmp/health.stdout")
              stderr = machine.succeed("cat /tmp/health.stderr")
              raise Exception(
                  f"health-check exited {status}\nstdout:\n{stdout}\nstderr:\n{stderr}"
              )
          machine.succeed("test -s /var/lib/health-monitor/last-report")
          machine.succeed("! grep -q 'awk: fatal' /tmp/health.stderr")

      with subtest("backups keep exactly five files"):
          backup_cases = [
              ("postgresql-backup.service", "${bulk}/backups/databases/postgresql", "all", "sql.zst"),
              ("mariadb-backup.service", "${bulk}/backups/databases/mariadb", "all", "sql.zst"),
              ("valkey-backup.service", "${bulk}/backups/databases/valkey", "valkey", "rdb"),
          ]

          for unit, directory, prefix, suffix in backup_cases:
              machine.succeed(f"systemctl start {unit}")
              machine.succeed(
                  f"for n in $(seq 1 7); do "
                  f"touch -d @$n {directory}/{prefix}-old-$n.{suffix}; "
                  "done"
              )
              machine.succeed(f"systemctl start {unit}")
              machine.succeed(
                  f"find {directory} -maxdepth 1 -type f "
                  f"-name '{prefix}-*.{suffix}' | wc -l | grep -x 5"
              )
    '';
}
