# Every host imports all of this. core/ applies to every machine; everything
# else stays off until a host switches it on in hosts/<name>/default.nix:
#
#   my.dev.enable = true;
#   my.desktop.enable = true;
#
# So adding a module here never changes a machine that did not ask for it.
{
  imports = [
    ./core
    ./dev.nix
    ./desktop
    ./services/mcc.nix
    ./services/t3code.nix
  ];
}
