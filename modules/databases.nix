{ pkgs, ... }:

let
  postgresqlPackage = pkgs.postgresql_18;

  # Backup filenames never contain spaces. Sort newest first and delete every
  # file after the fifth successful backup.
  keepNewestFive = pattern: ''
    ${pkgs.findutils}/bin/find "$backup_dir" -maxdepth 1 -type f \
      -name '${pattern}' -printf '%T@ %p\0' \
      | ${pkgs.coreutils}/bin/sort -z -nr \
      | ${pkgs.coreutils}/bin/tail -z -n +6 \
      | ${pkgs.coreutils}/bin/cut -z -d ' ' -f 2- \
      | ${pkgs.findutils}/bin/xargs -0 -r ${pkgs.coreutils}/bin/rm -f --
  '';
in

{
  services.postgresql = {
    enable = true;
    # Pin the major version so a routine update cannot silently change the
    # on-disk database format.
    package = postgresqlPackage;
    extensions = postgresqlPackages: [ postgresqlPackages.pgvector ];
  };

  services.mysql = {
    enable = true;
    package = pkgs.mariadb;
    settings.mysqld."bind-address" = "127.0.0.1";
  };

  services.redis = {
    package = pkgs.valkey;
    servers."" = {
      enable = true;
      bind = "127.0.0.1";
      openFirewall = false;
      settings = {
        appendonly = "yes";
        protected-mode = "yes";
      };
    };
  };

  systemd.services = {
    postgresql-backup = {
      description = "Weekly PostgreSQL backup";
      after = [
        "bulk-directory-setup.service"
        "postgresql.service"
      ];
      requires = [ "postgresql.service" ];
      unitConfig.RequiresMountsFor = [ "/srv/bulk" ];
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        UMask = "0077";
      };
      script = ''
        set -euo pipefail
        backup_dir=/srv/bulk/backups/databases/postgresql
        ${pkgs.coreutils}/bin/install -d -m 0700 "$backup_dir"
        stamp=$(${pkgs.coreutils}/bin/date +%Y-%m-%d_%H-%M-%S)
        output="$backup_dir/all-$stamp.sql.zst"
        temp="$output.tmp"
        trap '${pkgs.coreutils}/bin/rm -f "$temp"' EXIT
        ${postgresqlPackage}/bin/pg_dumpall \
          | ${pkgs.zstd}/bin/zstd -T0 -6 > "$temp"
        ${pkgs.coreutils}/bin/mv "$temp" "$output"
        trap - EXIT
        ${keepNewestFive "all-*.sql.zst"}
      '';
    };

    mariadb-backup = {
      description = "Weekly MariaDB backup";
      after = [
        "bulk-directory-setup.service"
        "mysql.service"
      ];
      requires = [ "mysql.service" ];
      unitConfig.RequiresMountsFor = [ "/srv/bulk" ];
      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
      };
      script = ''
        set -euo pipefail
        backup_dir=/srv/bulk/backups/databases/mariadb
        ${pkgs.coreutils}/bin/install -d -m 0700 "$backup_dir"
        stamp=$(${pkgs.coreutils}/bin/date +%Y-%m-%d_%H-%M-%S)
        output="$backup_dir/all-$stamp.sql.zst"
        temp="$output.tmp"
        trap '${pkgs.coreutils}/bin/rm -f "$temp"' EXIT
        ${pkgs.mariadb}/bin/mariadb-dump \
          --all-databases --single-transaction --routines --events \
          | ${pkgs.zstd}/bin/zstd -T0 -6 > "$temp"
        ${pkgs.coreutils}/bin/mv "$temp" "$output"
        trap - EXIT
        ${keepNewestFive "all-*.sql.zst"}
      '';
    };

    valkey-backup = {
      description = "Weekly Valkey backup";
      after = [
        "bulk-directory-setup.service"
        "redis.service"
      ];
      requires = [ "redis.service" ];
      unitConfig.RequiresMountsFor = [ "/srv/bulk" ];
      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
      };
      script = ''
        set -euo pipefail
        backup_dir=/srv/bulk/backups/databases/valkey
        ${pkgs.coreutils}/bin/install -d -m 0700 "$backup_dir"
        stamp=$(${pkgs.coreutils}/bin/date +%Y-%m-%d_%H-%M-%S)
        ${pkgs.valkey}/bin/valkey-cli --rdb "$backup_dir/valkey-$stamp.rdb"
        ${keepNewestFive "valkey-*.rdb"}
      '';
    };
  };

  systemd.timers = {
    postgresql-backup = {
      description = "Weekly PostgreSQL backup timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun *-*-* 02:00:00";
        Persistent = true;
        RandomizedDelaySec = "20m";
      };
    };

    mariadb-backup = {
      description = "Weekly MariaDB backup timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun *-*-* 02:30:00";
        Persistent = true;
        RandomizedDelaySec = "20m";
      };
    };

    valkey-backup = {
      description = "Weekly Valkey backup timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun *-*-* 03:00:00";
        Persistent = true;
        RandomizedDelaySec = "20m";
      };
    };
  };
}
