# carbon-nix

NixOS configuration for my machines. One repo, one `flake.lock`, one host so
far.

## Layout

```
flake.nix          Inputs, and one nixosConfiguration per host
hosts/<name>/      Everything true of exactly one machine
modules/           Everything a second machine could import unchanged
home/              Home Manager, per user
packages/          Packages built here because nixpkgs does not have them
lib/               Nix helpers shared between modules and Home Manager
installer/         Scripts for bare metal and for secrets that stay out of Git
tests/             VM tests, run by nix flake check
```

The split between `hosts/` and `modules/` is the rule that keeps the repo
honest. A disk serial, a network interface name, a hostname or a username goes
in `hosts/<name>/`. If a file in `modules/` mentions carbon, it is in the wrong
place.

`modules/default.nix` lists what every machine gets. Anything else in
`modules/` is opt-in, and `hosts/carbon/default.nix` imports the ones carbon
wants. That is why Postgres is listed there and not in the baseline.

Three values differ per machine and are needed by several shared modules, so
they are options rather than literals. `modules/options.nix` defines them and
`hosts/carbon/default.nix` sets them:

```nix
machine = {
  primaryUser = "dev24k";
  bulkPath = "/srv/bulk";
  btrfsRootPath = "/mnt/btrfs-root";
};
```

## Everyday changes

Edit, apply, commit, push:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#carbon   # or: rebuild
git -C /etc/nixos commit -am "Add the thing"
git -C /etc/nixos push
```

Pushing is not optional. See the next section.

## The weekly upgrade will revert anything you did not push

`system.autoUpgrade` runs every Sunday at 04:00 and builds from
`github:devchaudhary24k/carbon-nix#carbon`, the pushed repo, never from the
local `/etc/nixos`. On 2026-09-13 that removed `claude-code`, `dotnet-sdk` and
the `mcc-runtime` wrapper, because all three had been rebuilt by hand and never
committed.

`modules/auto-upgrade.nix` now runs a guard before the switch. It refuses to
upgrade when `/etc/nixos` has uncommitted changes, or when the checkout does
not match `origin/<branch>`. The upgrade unit fails instead of switching, the
health check reports a failed unit, and the heartbeat tells you.

Run the same check by hand at any time:

```bash
auto-upgrade-guard
```

To clear a blocked upgrade, push and then start it:

```bash
git -C /etc/nixos push
sudo systemctl start nixos-upgrade
```

## Where packages go

`modules/packages.nix` holds every system-wide package, grouped by what it is
for. That is the file to edit.

Three things deliberately live elsewhere:

`programs.*` in `modules/shell.nix` installs neovim, fish, fzf, direnv and yazi
along with their configuration. Adding them to the package list as well would
install them twice.

A package that only exists to serve a systemd unit stays in the module that
defines the unit. `health-check` in `modules/health-monitor.nix` is the only
current example.

`home/dev24k.nix` installs into `/etc/profiles/per-user/dev24k/bin`, which is
on that user's PATH and nowhere else. `claude-code` is there. A root systemd
unit cannot see it, which is correct for a CLI you run yourself.

## Installing software without Nix

It works, and two things on carbon already depend on it: `/opt/mcc` and
`~/.codex/packages/standalone`.

NixOS has no `/usr/lib` and no real `/lib`, so a downloaded binary cannot find
its loader and fails with `No such file or directory`, which is about the
loader and not about the binary. `programs.nix-ld` is enabled and installs a
shim at `/lib64/ld-linux-x86-64.so.2` that supplies libraries instead. When
something still fails on a missing `.so`, add the package to
`programs.nix-ld.libraries` and rebuild.

Anything under `$HOME` or `/opt` persists. Both sit on Btrfs subvolumes Nix
never touches, and both are covered by the daily snapshots. What you give up is
reproducibility, rollback and version pinning: wipe the machine and `/opt/mcc`
does not come back.

Use Nix when the package is in nixpkgs. Use nix-ld plus a manual install for a
vendor binary you need today. Package it properly, the way `packages/vite-plus`
does, once you know you will depend on it. Keep manual installs under `/opt` or
`~/.local` so there is one list of what sits outside Nix.

## Disks

`hosts/carbon/disks.nix` describes the partitions, filesystems, Btrfs
subvolumes and mount options once. disko turns that into the commands the
installer runs and into the `fileSystems` entries the running system mounts, so
the two cannot drift.

Carbon predates disko and its partitions are already named `ESP`, `nixos` and
`bulk`. The `label` on each partition pins those names, because the generated
`fileSystems` address partitions through `/dev/disk/by-partlabel/`.

Swap is on its own subvolume. An active swapfile on the root subvolume would
block snapshots of root.

## Installing on new hardware

```bash
git clone https://github.com/devchaudhary24k/carbon-nix
cd carbon-nix
sudo ./installer/install.sh --host carbon
```

The script reads the disk list out of `hosts/carbon/disks.nix`, refuses to run
outside a NixOS installer, refuses to touch a mounted disk, prints what it is
about to erase, and requires the exact phrase `ERASE CARBON`. Then disko
partitions and mounts, and `nixos-install` runs.

Afterwards:

```bash
sudo tailscale up --ssh=false
sudo /etc/nixos/installer/setup-monitoring.sh
```

`setup-monitoring.sh` reads a Better Stack heartbeat URL without echoing it and
writes it to `/etc/health-monitor/heartbeat-url`, mode 0600, outside Git. Until
that file exists the health service is skipped.

## Adding a machine

1. `mkdir hosts/<name>` and add `default.nix`, `hardware.nix` and `disks.nix`.
2. Set `machine.primaryUser` and `networking.hostName`.
3. Import the optional modules that machine wants.
4. Add one line to `hosts` in `flake.nix`.

That gives you `nixosConfigurations.<name>` and both VM tests for free.

## Monitoring

`modules/health-monitor.nix` checks the machine every five minutes and pings a
Better Stack heartbeat. It reports failed units, critical services, database
connectivity, mounts, disks above 90%, sustained CPU load, memory pressure,
stale backups and snapshots, SMART warnings and recent OOM kills. A failing
check posts the report body. A missed ping catches the machine being down.

## Backups and snapshots

btrbk snapshots root and home once a day at 03:30, keeps 3 days on the SSD, and
sends them incrementally to the bulk disk where 14 daily, 8 weekly and 6
monthly copies are kept. `/nix`, logs, Docker data and swap are separate
subvolumes and are deliberately not snapshotted.

Postgres, MariaDB and Valkey each dump weekly to the bulk disk and keep their
five newest dumps. Postgres 18 ships pgvector; turn it on per database with
`CREATE EXTENSION vector;`.

Both Btrfs filesystems are scrubbed monthly. Docker images unused for seven
days are pruned weekly. Docker volumes are never pruned automatically.

## Tests

```bash
nix flake check
```

Two tests per host:

`<host>-services` boots the real configuration in a VM with disposable mounts
and checks that services start, databases answer, the package list is
installed, Home Manager activated, backups trim to five files, and the upgrade
guard blocks a dirty checkout.

`<host>-disks` runs the real disko layout against scratch disks, installs, and
boots from it. It checks each subvolume is mounted with the right options, the
labels and partition labels exist, and a Btrfs snapshot can be sent from the
SSD to the bulk disk.

Nothing runs these automatically yet. The upgrade builds unattended at 04:00 on
a Sunday, so running `nix flake check` before pushing is worth the wait.

## Diagnostics

```bash
journalctl -b -1 -p warning
journalctl -u hardware-inventory
journalctl -u nixos-upgrade
coredumpctl list
sar -q
sudo atop -r
sudo smartctl -a /dev/sdb
```
