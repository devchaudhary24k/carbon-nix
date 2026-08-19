# carbon-nix

NixOS configuration for the headless `carbon` development machine.

## Install

The guarded installer script uses carbon's stable disk IDs. It erases both the
240 GB SSD and 1 TB HDD only after checking that it is running from a NixOS
installer and requiring an exact confirmation phrase.

```bash
git clone https://github.com/devchaudhary24k/carbon-nix
cd carbon-nix
sudo ./install.sh
```

The intended disk layout is:

- **240 GB WD Green SSD:** Btrfs label `carbon-root`, with `root`, `home`,
  `nix`, `log`, `docker`, and `swap` subvolumes.
- **1 TB Seagate HDD:** Btrfs label `carbon-bulk`, mounted at `/srv/bulk`.

Formatting the HDD destroys its current ext4 contents. Copy off anything you
need first. Btrfs is required there because Btrfs snapshots cannot be sent to
an ext4 filesystem.

The script creates and mounts the SSD subvolumes, formats the HDD, generates
the real hardware configuration, installs the flake, and asks for `dev24k`'s
password. The equivalent manual final steps are:

```bash
sudo mkdir -p /mnt/etc
sudo git clone https://github.com/devchaudhary24k/carbon-nix \
  /mnt/etc/nixos

sudo nixos-generate-config --root /mnt

sudo cp \
  /mnt/etc/nixos/hardware-configuration.nix \
  /mnt/etc/nixos/hosts/carbon/hardware-configuration.nix

cd /mnt/etc/nixos
sudo nix --extra-experimental-features 'nix-command flakes' flake lock
sudo nixos-install --flake path:/mnt/etc/nixos#carbon
sudo nixos-enter --root /mnt -c 'passwd dev24k'
```

Reboot, then join Tailscale without enabling Tailscale SSH:

```bash
sudo tailscale up --ssh=false
```

## Normal changes

Edit files in `/etc/nixos`, commit them, then apply:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#carbon
```

Install language versions per user/project instead of globally:

```bash
fnm install --lts
rustup default stable
uv python install
```

The first `nvim` run installs LazyVim plugins. Fish, Git, and Starship settings
are linked from `devchaudhary24k/dotfiles`.

Snapshots run daily. The SSD keeps 3 daily snapshots of root and home;
incremental copies on the HDD keep 14 daily, 8 weekly, and 6 monthly snapshots.
`/nix`, logs, Docker data, and swap are separate subvolumes and are deliberately
not snapshotted. Database dumps still run weekly on the HDD.
Each PostgreSQL, MariaDB, and Valkey service retains its five newest backups.
PostgreSQL 18 includes pgvector; enable it inside each application database with
`CREATE EXTENSION vector;`.

## Diagnostics

```bash
journalctl -b -1 -p warning
journalctl -u hardware-inventory
coredumpctl list
sar -q
sudo atop -r
sudo smartctl -a /dev/sda
```

Automatic updates run weekly from
`github:devchaudhary24k/carbon-nix#carbon`, so create and push that public
repository before relying on the timer. It never reboots automatically.
