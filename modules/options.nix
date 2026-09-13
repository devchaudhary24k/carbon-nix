# Facts that differ per machine but that several shared modules have to agree
# on. Each host sets these in hosts/<name>/default.nix.
{ lib, ... }:

{
  options.machine = {
    primaryUser = lib.mkOption {
      type = lib.types.str;
      example = "dev24k";
      description = ''
        Login name of the person who uses this machine. Shared modules use it
        when they create directories that the user has to write to.
      '';
    };

    bulkPath = lib.mkOption {
      type = lib.types.path;
      default = "/srv/bulk";
      description = ''
        Mount point of the large secondary disk. Database dumps and Btrfs
        snapshot targets are written below it.
      '';
    };

    btrfsRootPath = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/btrfs-root";
      description = ''
        Mount point of the top-level Btrfs subvolume, subvolid 5. btrbk needs it
        to see the root and home subvolumes as siblings.
      '';
    };
  };
}
