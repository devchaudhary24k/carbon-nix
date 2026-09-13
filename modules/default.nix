# The baseline every machine in this repo gets.
#
# Modules that only some machines want (databases, containers, snapshots,
# health reporting, the development runtime) are imported by hosts/<name>
# instead, so a future laptop does not inherit a Postgres server.
{
  imports = [
    ./options.nix
    ./auto-upgrade.nix
    ./network.nix
    ./nix.nix
    ./observability.nix
    ./packages.nix
    ./shell.nix
  ];
}
