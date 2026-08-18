{ pkgs, ... }:

{
  services.journald = {
    storage = "persistent";
    rateLimitInterval = "30s";
    rateLimitBurst = 1000;
    extraConfig = ''
      SystemMaxUse=1G
      SystemKeepFree=5G
      RuntimeMaxUse=128M
      MaxRetentionSec=1month
    '';
  };

  systemd.coredump = {
    enable = true;
    settings.Coredump = {
      Storage = "external";
      Compress = "yes";
      MaxUse = "1G";
      KeepFree = "5G";
    };
  };

  systemd.oomd.enableUserSlices = true;

  services.smartd = {
    enable = true;
    autodetect = true;
  };

  hardware.rasdaemon.enable = true;

  services.sysstat = {
    enable = true;
    collect-frequency = "*:00/5";
  };

  programs.atop = {
    enable = true;
    settings.interval = 300;
  };

  systemd.services.hardware-inventory = {
    description = "Record hardware and network inventory in the journal";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    path = with pkgs; [
      coreutils
      dmidecode
      iproute2
      lshw
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

  environment.systemPackages = with pkgs; [
    atop
    rasdaemon
    smartmontools
    sysstat
  ];
}
