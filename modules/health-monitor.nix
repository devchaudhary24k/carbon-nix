{ config, pkgs, ... }:

let
  carbonHealthCheck = pkgs.writeShellApplication {
    name = "carbon-health-check";
    runtimeInputs = with pkgs; [
      config.services.mysql.package
      config.services.postgresql.package
      config.services.redis.package
      coreutils
      curl
      docker
      findutils
      gawk
      gnugrep
      jq
      systemd
      tailscale
      util-linux
    ];
    text = ''
      state_dir=/var/lib/carbon-monitor
      credential_file="$CREDENTIALS_DIRECTORY/heartbeat-url"
      report_file="$state_dir/last-report"
      first_run_file="$state_dir/first-run"
      cpu_count_file="$state_dir/cpu-high-count"
      issues=()

      add_issue() {
        issues+=("$1")
      }

      heartbeat_url=$(tr -d '\r\n' < "$credential_file")
      heartbeat_url="''${heartbeat_url%/}"
      case "$heartbeat_url" in
        https://uptime.betterstack.com/api/v1/heartbeat/*) ;;
        *)
          echo "The configured heartbeat URL is not a Better Stack heartbeat URL." >&2
          exit 0
          ;;
      esac

      if [[ ! -e "$first_run_file" ]]; then
        touch "$first_run_file"
      fi

      critical_units=(
        NetworkManager.service
        docker.service
        mysql.service
        postgresql.service
        redis.service
        smartd.service
        sshd.service
        tailscaled.service
      )

      for unit in "''${critical_units[@]}"; do
        if ! systemctl is-active --quiet "$unit"; then
          add_issue "SERVICE: $unit is not active"
        fi
      done

      while IFS= read -r unit; do
        [[ -z "$unit" ]] || add_issue "FAILED UNIT: $unit"
      done < <(
        systemctl list-units --state=failed --no-legend --plain --no-pager |
          awk '{ print $1 }'
      )

      critical_timers=(
        btrbk-carbon.timer
        docker-prune.timer
        mariadb-backup.timer
        nixos-upgrade.timer
        postgresql-backup.timer
        valkey-backup.timer
      )

      for timer in "''${critical_timers[@]}"; do
        if ! systemctl is-enabled --quiet "$timer"; then
          add_issue "TIMER: $timer is not enabled"
        fi
      done

      scrub_timer_count=$(
        systemctl list-unit-files 'btrfs-scrub-*.timer' \
          --state=enabled --no-legend --no-pager |
          awk 'END { print NR + 0 }'
      )
      if (( scrub_timer_count < 2 )); then
        add_issue "TIMER: expected two enabled Btrfs scrub timers, found $scrub_timer_count"
      fi

      for mount_path in /mnt/btrfs-root /srv/bulk; do
        if ! mountpoint --quiet "$mount_path"; then
          add_issue "MOUNT: $mount_path is not mounted"
        fi
      done

      disk_summary=()
      for mount_path in / /srv/bulk; do
        if [[ "$mount_path" == / ]] || mountpoint --quiet "$mount_path"; then
          used_percent=$(df --output=pcent "$mount_path" | tail -n 1 | tr -dc '0-9')
          disk_summary+=("$mount_path=''${used_percent}%")
          if [[ "$used_percent" =~ ^[0-9]+$ ]] && (( used_percent >= 90 )); then
            add_issue "DISK: $mount_path is ''${used_percent}% full"
          fi
        fi
      done

      mem_total=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
      mem_available=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
      memory_percent=$((100 * (mem_total - mem_available) / mem_total))
      if (( memory_percent >= 95 )); then
        add_issue "MEMORY: ''${memory_percent}% used"
      fi

      read_cpu_sample() {
        awk '/^cpu / {
          total = 0
          for (field = 2; field <= NF; field++) total += $field
          idle = $5 + $6
          print total, idle
          exit
        }' /proc/stat
      }

      read -r cpu_total_before cpu_idle_before < <(read_cpu_sample)
      sleep 5
      read -r cpu_total_after cpu_idle_after < <(read_cpu_sample)
      cpu_total_delta=$((cpu_total_after - cpu_total_before))
      cpu_idle_delta=$((cpu_idle_after - cpu_idle_before))
      cpu_percent=0
      if (( cpu_total_delta > 0 )); then
        cpu_percent=$((100 * (cpu_total_delta - cpu_idle_delta) / cpu_total_delta))
      fi

      cpu_high_count=0
      if [[ -r "$cpu_count_file" ]]; then
        read -r cpu_high_count < "$cpu_count_file" || cpu_high_count=0
      fi
      [[ "$cpu_high_count" =~ ^[0-9]+$ ]] || cpu_high_count=0

      if (( cpu_percent >= 90 )); then
        cpu_high_count=$((cpu_high_count + 1))
      else
        cpu_high_count=0
      fi
      printf '%s\n' "$cpu_high_count" > "$cpu_count_file"

      if (( cpu_high_count >= 3 )); then
        add_issue "CPU: at least 90% busy for three consecutive checks"
      fi

      load_15=$(awk '{ print $3 }' /proc/loadavg)
      cpu_cores=$(nproc)
      if awk -v load="$load_15" -v cores="$cpu_cores" \
        'BEGIN { exit !(load > cores * 2) }'; then
        add_issue "LOAD: 15-minute load $load_15 exceeds twice the $cpu_cores CPU cores"
      fi

      if systemctl is-active --quiet postgresql.service &&
        ! runuser -u postgres -- psql --quiet --tuples-only \
          --command 'SELECT 1' postgres >/dev/null; then
        add_issue "DATABASE: PostgreSQL query failed"
      fi

      if systemctl is-active --quiet mysql.service &&
        ! mariadb --batch --skip-column-names --execute 'SELECT 1' >/dev/null; then
        add_issue "DATABASE: MariaDB query failed"
      fi

      if systemctl is-active --quiet redis.service &&
        ! valkey-cli ping 2>/dev/null | grep --quiet '^PONG$'; then
        add_issue "DATABASE: Valkey ping failed"
      fi

      if systemctl is-active --quiet docker.service &&
        ! docker info >/dev/null 2>&1; then
        add_issue "DOCKER: daemon health check failed"
      fi

      if systemctl is-active --quiet tailscaled.service &&
        ! tailscale status --json 2>/dev/null |
          jq --exit-status '.BackendState == "Running"' >/dev/null; then
        add_issue "TAILSCALE: backend is not running or authenticated"
      fi

      # Give a fresh installation time to produce its first scheduled data.
      if find "$first_run_file" -mmin +2880 -print -quit | grep --quiet .; then
        for snapshot_name in root home; do
          if ! find /srv/bulk/snapshots/carbon -maxdepth 2 -type d \
            -name "$snapshot_name.*" -cmin -2880 -print -quit 2>/dev/null |
            grep --quiet .; then
            add_issue "SNAPSHOT: no recent $snapshot_name snapshot on the HDD"
          fi
        done
      fi

      if find "$first_run_file" -mmin +12960 -print -quit | grep --quiet .; then
        backup_checks=(
          "/srv/bulk/backups/databases/postgresql|all-*.sql.zst|PostgreSQL"
          "/srv/bulk/backups/databases/mariadb|all-*.sql.zst|MariaDB"
          "/srv/bulk/backups/databases/valkey|valkey-*.rdb|Valkey"
        )
        for check in "''${backup_checks[@]}"; do
          IFS='|' read -r directory pattern label <<< "$check"
          if ! find "$directory" -maxdepth 1 -type f -name "$pattern" \
            -mmin -12960 -print -quit 2>/dev/null | grep --quiet .; then
            add_issue "BACKUP: no $label backup created in the last nine days"
          fi
        done
      fi

      recent_smart_warnings=$(
        journalctl -u smartd.service --since '6 minutes ago' \
          --priority=warning..emerg --no-pager --output=cat 2>/dev/null |
          tail -n 3 || true
      )
      if [[ -n "$recent_smart_warnings" ]]; then
        add_issue "SMART: $recent_smart_warnings"
      fi

      recent_oom=$(
        journalctl --dmesg --since '6 minutes ago' --no-pager --output=cat \
          2>/dev/null |
          grep --extended-regexp --ignore-case \
            'out of memory|oom-killer|killed process' |
          tail -n 3 || true
      )
      if [[ -n "$recent_oom" ]]; then
        add_issue "MEMORY: recent OOM event: $recent_oom"
      fi

      if (( ''${#issues[@]} > 0 )); then
        {
          printf 'carbon health check failed at %s\n' "$(date --iso-8601=seconds)"
          printf -- '- %s\n' "''${issues[@]}"
          printf 'Current: CPU=%s%% memory=%s%% load15=%s disks=%s\n' \
            "$cpu_percent" "$memory_percent" "$load_15" "''${disk_summary[*]}"
        } > "$report_file"
        endpoint="$heartbeat_url/fail"
      else
        printf 'carbon healthy: CPU=%s%% memory=%s%% load15=%s disks=%s at %s\n' \
          "$cpu_percent" "$memory_percent" "$load_15" \
          "''${disk_summary[*]}" "$(date --iso-8601=seconds)" > "$report_file"
        endpoint="$heartbeat_url"
      fi

      if ! curl --fail --silent --show-error --max-time 10 --retry 3 \
        --data-binary "@$report_file" "$endpoint" >/dev/null; then
        echo "Unable to deliver the Better Stack heartbeat; a missed ping will alert externally." >&2
      fi

      exit 0
    '';
  };
in

{
  environment.systemPackages = [ carbonHealthCheck ];

  systemd.tmpfiles.rules = [
    "d /etc/carbon-monitor 0700 root root - -"
  ];

  systemd.services.carbon-health = {
    description = "Check carbon health and report to Better Stack";
    after = [
      "network-online.target"
      "postgresql.service"
      "mysql.service"
      "redis.service"
    ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "/etc/carbon-monitor/heartbeat-url";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${carbonHealthCheck}/bin/carbon-health-check";
      LoadCredential = "heartbeat-url:/etc/carbon-monitor/heartbeat-url";
      StateDirectory = "carbon-monitor";
      StateDirectoryMode = "0700";
      UMask = "0077";
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
    };
  };

  systemd.timers.carbon-health = {
    description = "Run carbon health checks every five minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10m";
      OnUnitActiveSec = "5m";
      RandomizedDelaySec = "30s";
      Persistent = true;
    };
  };
}
