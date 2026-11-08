# Steam and friends. On a hybrid laptop, run a game on the NVIDIA GPU with
# this Steam launch option (right-click the game, Properties, Launch Options):
#
#   nvidia-offload gamemoderun %command%
{ config, lib, ... }:

{
  options.my.gaming.enable = lib.mkEnableOption "Steam and game tooling";

  config = lib.mkIf config.my.gaming.enable {
    programs.steam.enable = true;

    # Raises CPU and GPU clocks while a game runs.
    programs.gamemode.enable = true;

    my.unfree = [
      "steam"
      "steam-unwrapped"
    ];
  };
}
