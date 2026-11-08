# Local logs and history, kept on the machine itself. Nothing is sent anywhere.
#
# Where to look when something went wrong:
#
#   sysreport                        one-page summary of the machine right now
#   journalctl -b -p warning         warnings and errors since this boot
#   journalctl -b -1 -p err          errors from the previous boot (crashes)
#   journalctl -u <service>          one service's log
#   journalctl -k --grep 'refused'   connections the firewall blocked
#   sar -n DEV                       network traffic per interface, every 5 min
#   sar -u / sar -r                  CPU / memory over the day
#   atop -r                          replay per-process usage (t and T to step)
#   vnstat -d / vnstat -m            data used per day / month
#   coredumpctl list                 programs that crashed
#   smartctl -a /dev/<disk>          disk health
{ config, pkgs, ... }:

let
  sysreport = pkgs.writeShellApplication {
    name = "sysreport";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      lm_sensors
      procps
      smartmontools
      systemd
      util-linux
      vnstat
    ];
    text = ''
      section() { printf '\n== %s\n' "$1"; }

      echo "${config.networking.hostName}: $(date --iso-8601=seconds)"
      uptime

      section "Failed services"
      systemctl --failed --no-legend --plain || true

      section "Errors since boot (newest 15)"
      journalctl -b -p err --no-pager -n 15 -o short-iso || true

      section "Out-of-memory kills since boot"
      journalctl -k -b --no-pager -o short-iso --grep 'Out of memory|oom-kill' || echo "none"

      section "Crashes in the last week"
      coredumpctl list --no-pager --since '-7d' 2>/dev/null || echo "none"

      section "Disks"
      df -h -x tmpfs -x devtmpfs -x efivarfs -x overlay

      section "Memory"
      free -h

      section "Temperatures"
      sensors 2>/dev/null | grep -E '^(Tctl|edge|Composite|temp1)' || echo "no sensors"

      section "Network, last two days"
      vnstat -d 2 2>/dev/null || echo "vnstat has no data yet"

      if (( EUID == 0 )); then
        section "Disk health"
        for disk in /dev/sd? /dev/nvme?n1; do
          [[ -e "$disk" ]] || continue
          printf '%s: ' "$disk"
          smartctl -H "$disk" | grep -E 'result|Status' || echo "unknown"
        done
      else
        printf '\n(run with sudo to include disk health)\n'
      fi
    '';
  };
in

{
  services.journald = {
    storage = "persistent";
    rateLimitInterval = "30s";
    rateLimitBurst = 1000;
    extraConfig = ''
      SystemMaxUse=2G
      SystemKeepFree=5G
      RuntimeMaxUse=128M
      MaxRetentionSec=3month
    '';
  };

  # Crashed programs keep a compressed core dump for inspection.
  systemd.coredump = {
    enable = true;
    settings.Coredump = {
      Storage = "external";
      Compress = "yes";
      MaxUse = "1G";
      KeepFree = "5G";
    };
  };

  # Kills the offending user process under memory pressure instead of letting
  # the whole machine freeze.
  systemd.oomd.enableUserSlices = true;

  # Disk health, checked continuously. Warnings go to the journal.
  services.smartd = {
    enable = true;
    autodetect = true;
  };

  # Memory and CPU hardware errors.
  hardware.rasdaemon.enable = true;

  # CPU, memory, disk and per-interface network history, every 5 minutes.
  services.sysstat = {
    enable = true;
    collect-frequency = "*:00/5";
  };

  # Per-process history, so "what was eating CPU at 3 am" has an answer.
  programs.atop = {
    enable = true;
    settings.interval = 300;
  };

  # Data used per interface per hour, day and month.
  services.vnstat.enable = true;

  environment.systemPackages = [
    sysreport
    pkgs.sysstat
  ];

  # A snapshot of the hardware at every boot, so "what changed" can be
  # answered from the journal after a part is swapped or a firmware update.
  systemd.services.hardware-inventory = {
    description = "Record hardware and network inventory in the journal";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    path = with pkgs; [
      coreutils
      dmidecode
      iproute2
      pciutils
      procps
      util-linux
      usbutils
    ];
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal";
      StandardError = "journal";
    };
    script = ''
      echo "=== hardware inventory: $(date --iso-8601=seconds) ==="
      uname -a
      lscpu
      free -h
      lsblk -e7 -o NAME,PATH,MODEL,SERIAL,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS
      lspci -nnk
      lsusb
      ip -brief address
      dmidecode --type system --type baseboard --type bios
    '';
  };
}
