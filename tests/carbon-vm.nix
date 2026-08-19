{ carbonModules, pkgs }:

pkgs.testers.runNixOSTest {
  name = "carbon-vm";

  nodes.machine =
    { lib, ... }:
    {
      imports = carbonModules;

      virtualisation = {
        cores = 2;
        diskSize = 4096;
        graphics = false;
        memorySize = 3072;
      };

      # Replace hardware-specific storage with disposable VM mounts. The real
      # Btrfs disk layout is exercised separately by install.sh.
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

      # Avoid external upgrades and Btrfs operations inside this service test.
      system.autoUpgrade.enable = lib.mkForce false;
      services.btrbk.instances = lib.mkForce { };
      services.btrfs.autoScrub.enable = lib.mkForce false;
      systemd.services.btrbk-carbon.enable = lib.mkForce false;

      # These are meaningful on carbon's physical hardware, not in QEMU.
      boot.loader.systemd-boot.enable = lib.mkForce false;
      boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
      hardware.rasdaemon.enable = lib.mkForce false;
      services.fwupd.enable = lib.mkForce false;
      services.smartd.enable = lib.mkForce false;
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    for unit in [
        "sshd.service",
        "docker.service",
        "postgresql.service",
        "mysql.service",
        "redis.service",
        "tailscaled.service",
        "home-manager-dev24k.service",
        "bulk-directory-setup.service",
    ]:
        machine.wait_for_unit(unit)

    machine.succeed("psql --version | grep -E 'PostgreSQL\\) 18\\.'")
    machine.succeed("sudo -u postgres createdb vector_test")
    machine.succeed(
        "sudo -u postgres psql --dbname vector_test --set ON_ERROR_STOP=1 "
        "--command=\"CREATE EXTENSION vector; SELECT '[1,2,3]'::vector(3);\" "
        "| grep -F '[1,2,3]'"
    )

    machine.succeed("mariadb --batch --skip-column-names --execute 'SELECT 1' | grep -x 1")
    machine.succeed("valkey-cli ping | grep -x PONG")
    machine.succeed("docker info >/dev/null")
    machine.succeed("systemctl is-enabled docker-prune.timer | grep -x enabled")
    machine.succeed("systemctl is-enabled carbon-health.timer | grep -x enabled")
    machine.succeed("command -v carbon-health-check")

    for command in [
        "nh", "nvd", "nom", "lsof", "strace", "iotop", "ncdu",
        "hyperfine", "watchexec", "tokei", "xh", "websocat", "socat",
        "nmap", "iperf3",
    ]:
        machine.succeed(f"command -v {command}")

    machine.succeed("test -e /home/dev24k/.config/fish/config.fish")
    machine.succeed("runuser -u dev24k -- fish -c 'type -q fnm; and type -q starship; and type -q zoxide'")
    machine.succeed("grep -q 'ssh-ed25519' /etc/ssh/authorized_keys.d/dev24k")

    backup_cases = [
        ("postgresql-backup.service", "/srv/bulk/backups/databases/postgresql", "all", "sql.zst"),
        ("mariadb-backup.service", "/srv/bulk/backups/databases/mariadb", "all", "sql.zst"),
        ("valkey-backup.service", "/srv/bulk/backups/databases/valkey", "valkey", "rdb"),
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
