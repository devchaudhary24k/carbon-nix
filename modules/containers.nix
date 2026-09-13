{
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "Sun 05:30";
      flags = [
        "--all"
        "--filter=until=168h"
      ];
    };
  };
}
