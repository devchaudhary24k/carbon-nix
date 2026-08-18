#!/usr/bin/env bash

set -euo pipefail

# Stable disk IDs captured from carbon. Never replace these with /dev/sda or
# /dev/sdb: those names can swap between boots.
carbon_ssd="/dev/disk/by-id/ata-WD_Green_2.5_240GB_251587803145"
carbon_hdd="/dev/disk/by-id/ata-ST1000DM010-2EP102_ZN1MPLB5"
carbon_ssd_efi="${carbon_ssd}-part1"
carbon_ssd_root="${carbon_ssd}-part2"
carbon_hdd_data="${carbon_hdd}-part1"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo from the NixOS installer."
  exit 1
fi

if ! grep -q '^ID=nixos$' /etc/os-release; then
  echo "Refusing to run: boot the NixOS installer first."
  exit 1
fi

for carbon_disk in "$carbon_ssd" "$carbon_hdd"; do
  if [[ ! -b "$carbon_disk" ]]; then
    echo "Expected disk is missing: $carbon_disk"
    exit 1
  fi

  if lsblk -nrpo MOUNTPOINT "$carbon_disk" \
    | sed '/^[[:space:]]*$/d' \
    | grep -q .; then
    echo "Refusing to erase a mounted disk: $carbon_disk"
    exit 1
  fi
done

echo "The following two disks will be completely erased:"
lsblk -d -o PATH,SIZE,MODEL,SERIAL "$carbon_ssd" "$carbon_hdd"
echo
read -r -p 'Type ERASE CARBON SSD AND HDD to continue: ' carbon_confirmation

if [[ "$carbon_confirmation" != "ERASE CARBON SSD AND HDD" ]]; then
  echo "Cancelled."
  exit 1
fi

wipefs --all --force "$carbon_ssd"
wipefs --all --force "$carbon_hdd"

parted --script "$carbon_ssd" -- \
  mklabel gpt \
  mkpart ESP fat32 1MiB 1025MiB \
  set 1 esp on \
  mkpart nixos btrfs 1025MiB 100%

parted --script "$carbon_hdd" -- \
  mklabel gpt \
  mkpart bulk btrfs 1MiB 100%

partprobe "$carbon_ssd" "$carbon_hdd"
udevadm settle

mkfs.fat -F 32 -n CARBONBOOT "$carbon_ssd_efi"
mkfs.btrfs -f -L carbon-root "$carbon_ssd_root"
mkfs.btrfs -f -L carbon-bulk "$carbon_hdd_data"

mount -o subvolid=5 "$carbon_ssd_root" /mnt
for carbon_subvolume in root home nix log docker swap; do
  btrfs subvolume create "/mnt/$carbon_subvolume"
done
umount /mnt

carbon_mount_options="compress=zstd:3,noatime"
mount -o "$carbon_mount_options,subvol=root" "$carbon_ssd_root" /mnt

mkdir -p \
  /mnt/boot \
  /mnt/home \
  /mnt/nix \
  /mnt/swap \
  /mnt/var/log \
  /mnt/var/lib/docker

mount -o "$carbon_mount_options,subvol=home" "$carbon_ssd_root" /mnt/home
mount -o "$carbon_mount_options,subvol=nix" "$carbon_ssd_root" /mnt/nix
mount -o "$carbon_mount_options,subvol=log" "$carbon_ssd_root" /mnt/var/log
mount -o "$carbon_mount_options,subvol=docker" "$carbon_ssd_root" /mnt/var/lib/docker
mount -o "$carbon_mount_options,subvol=swap" "$carbon_ssd_root" /mnt/swap
mount "$carbon_ssd_efi" /mnt/boot

carbon_repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p /mnt/etc/nixos
cp -a "$carbon_repo_dir"/. /mnt/etc/nixos/

nixos-generate-config --root /mnt --show-hardware-config \
  > /mnt/etc/nixos/hosts/carbon/hardware-configuration.nix

nixos-install --flake path:/mnt/etc/nixos#carbon --no-root-passwd
nixos-enter --root /mnt -c 'passwd dev24k'

echo
echo "Installation complete. Reboot, then run: sudo tailscale up --ssh=false"
