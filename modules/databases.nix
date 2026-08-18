{ pkgs, ... }:

{
  services.postgresql = {
    enable = true;
    # Pin the major version so a routine update cannot silently change the
    # on-disk database format.
    package = pkgs.postgresql_17;
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
        set -eu
        backup_dir=/srv/bulk/backups/databases/postgresql
        ${pkgs.coreutils}/bin/install -d -m 0700 "$backup_dir"
        stamp=$(${pkgs.coreutils}/bin/date +%Y-%m-%d_%H-%M-%S)
        output="$backup_dir/all-$stamp.sql.zst"
        temp="$output.tmp"
        trap '${pkgs.coreutils}/bin/rm -f "$temp"' EXIT
        ${pkgs.postgresql_17}/bin/pg_dumpall \
          | ${pkgs.zstd}/bin/zstd -T0 -6 > "$temp"
        ${pkgs.coreutils}/bin/mv "$temp" "$output"
        trap - EXIT
        ${pkgs.findutils}/bin/find "$backup_dir" -type f -name 'all-*.sql.zst' -mtime +42 -delete
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
        set -eu
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
        ${pkgs.findutils}/bin/find "$backup_dir" -type f -name 'all-*.sql.zst' -mtime +42 -delete
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
        set -eu
        backup_dir=/srv/bulk/backups/databases/valkey
        ${pkgs.coreutils}/bin/install -d -m 0700 "$backup_dir"
        stamp=$(${pkgs.coreutils}/bin/date +%Y-%m-%d_%H-%M-%S)
        ${pkgs.valkey}/bin/valkey-cli --rdb "$backup_dir/valkey-$stamp.rdb"
        ${pkgs.findutils}/bin/find "$backup_dir" -type f -name 'valkey-*.rdb' -mtime +42 -delete
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
