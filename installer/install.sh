#!/usr/bin/env bash
#
# Partition, format and install one of the hosts in this repo onto bare metal.
#
#   sudo ./installer/install.sh --host carbon
#
# The disk layout is not written here. It comes from hosts/<host>/disks.nix,
# which disko turns into the partitioning commands, so the machine ends up with
# exactly the filesystems the running configuration expects to mount.

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
host=""

usage() {
  cat <<'USAGE'
Usage: sudo ./installer/install.sh --host <name>

Options:
  --host <name>   Host to install. Must match a directory under hosts/.
  -h, --help      Show this message.

This erases every disk listed in hosts/<name>/disks.nix.
USAGE
}

available_hosts() {
  find "$repo_root/hosts" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
}

while (($# > 0)); do
  case "$1" in
    --host)
      [[ $# -ge 2 ]] || {
        echo "--host needs a value." >&2
        exit 2
      }
      host="$2"
      shift 2
      ;;
    --host=*)
      host="${1#--host=}"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$host" ]]; then
  echo "No host given. Available hosts:" >&2
  available_hosts >&2
  exit 2
fi

if [[ ! -f "$repo_root/hosts/$host/disks.nix" ]]; then
  echo "hosts/$host/disks.nix does not exist. Available hosts:" >&2
  available_hosts >&2
  exit 2
fi

if ((EUID != 0)); then
  echo "Run this with sudo from the NixOS installer." >&2
  exit 1
fi

if ! grep -q '^ID=nixos$' /etc/os-release; then
  echo "Refusing to run: boot the NixOS installer first." >&2
  exit 1
fi

nix_flags=(--extra-experimental-features 'nix-command flakes')

# Installing from a clean Git checkout makes the system record the commit it
# was built from. The auto-upgrade guard on carbon needs that.
if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
  echo "The checkout at $repo_root has uncommitted changes." >&2
  echo "Commit or stash them first, so the installed system matches a commit on GitHub." >&2
  exit 1
fi
flake="$repo_root#$host"
config="$repo_root#nixosConfigurations.$host.config"

primary_user="$(nix "${nix_flags[@]}" eval --raw "$config.my.user")"
secure_boot="$(
  nix "${nix_flags[@]}" eval --raw "$config.my.secureBoot.enable" \
    --apply 'enabled: if enabled then "1" else "0"'
)"

# lanzaboote enrolls this machine's own Secure Boot keys on the first boot,
# which the firmware only accepts while it is in Setup Mode.
if [[ "$secure_boot" == 1 ]]; then
  setup_mode=0
  for var in /sys/firmware/efi/efivars/SetupMode-*; do
    [[ -e "$var" ]] || continue
    # Four bytes of attributes, then the one-byte value.
    setup_mode="$(od -An -t u1 -j 4 -N 1 "$var" | tr -d ' ')"
  done

  if [[ "$setup_mode" != 1 ]]; then
    cat >&2 <<'SETUP'
The firmware is not in Secure Boot Setup Mode, so the keys this machine
generates on its first boot cannot be enrolled.

In the BIOS (press F2 at power-on), go to Security > Secure Boot > Key
Management and clear the Secure Boot keys (on some firmware: delete the
Platform Key). Save, then boot this installer again. Do not pick an option
that also wipes the forbidden signature list (dbx).
SETUP
    read -r -p "Install anyway and enroll the keys later? [y/N] " answer
    [[ "$answer" == [yY] ]] || exit 1
  fi
fi

echo "Reading the disk layout from hosts/$host/disks.nix ..."
mapfile -t target_disks < <(
  nix "${nix_flags[@]}" eval --raw \
    "$config.disko.devices.disk" \
    --apply 'disks: builtins.concatStringsSep "\n" (map (d: d.device) (builtins.attrValues disks))'
  printf '\n'
)

for disk in "${target_disks[@]}"; do
  [[ -n "$disk" ]] || continue

  if [[ ! -b "$disk" ]]; then
    echo "Expected disk is missing: $disk" >&2
    exit 1
  fi

  if lsblk -nrpo MOUNTPOINT "$disk" | sed '/^[[:space:]]*$/d' | grep -q .; then
    echo "Refusing to erase a mounted disk: $disk" >&2
    exit 1
  fi
done

echo
echo "These disks will be completely erased:"
lsblk -d -o PATH,SIZE,MODEL,SERIAL "${target_disks[@]}"
echo

confirmation_phrase="ERASE ${host^^}"
read -r -p "Type '$confirmation_phrase' to continue: " typed
if [[ "$typed" != "$confirmation_phrase" ]]; then
  echo "Cancelled."
  exit 1
fi

# One script, generated from the same disks.nix the installed system mounts.
# It destroys the existing layout, formats (asking for the disk encryption
# passphrase where there is one), and mounts everything under /mnt.
echo "Building the disko script for $host ..."
disko_script="$(
  nix "${nix_flags[@]}" build --no-link --print-out-paths \
    "$config.system.build.diskoScript"
)"

echo "Partitioning and mounting ..."
"$disko_script"

# The checkout lives where `rebuild` (nh) looks for it.
checkout="/home/$primary_user/code/carbon-nix"
echo "Copying the repository to $checkout ..."
install -d -m 0755 "/mnt$checkout"
cp -a "$repo_root"/. "/mnt$checkout/"

# hardware.nix is committed rather than generated, because disko already owns
# the filesystems and the remaining hardware detection rarely changes. Compare
# them so a new machine's differences are not silently ignored.
generated_hardware="$(mktemp)"
nixos-generate-config --root /mnt --show-hardware-config >"$generated_hardware"
if ! diff -q \
  <(grep -oE '"[a-z0-9_]+"' "$repo_root/hosts/$host/hardware.nix" | sort -u) \
  <(grep -oE '"[a-z0-9_]+"' "$generated_hardware" | sort -u) >/dev/null; then
  echo
  echo "Note: the detected hardware differs from hosts/$host/hardware.nix."
  echo "Generated copy left at $checkout/hosts/$host/hardware-detected.nix"
  cp "$generated_hardware" "/mnt$checkout/hosts/$host/hardware-detected.nix"
fi
rm -f "$generated_hardware"

echo "Installing ..."
nixos-install --flake "$flake" --no-root-passwd

nixos-enter --root /mnt -c "chown -R $primary_user:users /home/$primary_user"
echo "Set the password for $primary_user (login screen and sudo):"
nixos-enter --root /mnt -c "passwd $primary_user"

echo
echo "Installed $host. Next steps: README.md, section \"After installing\"."
if [[ "$secure_boot" == 1 ]]; then
  cat <<'DONE'

This machine uses Secure Boot. On its first boot it generates its keys,
enrolls them and reboots once by itself. After that, enroll the TPM so the
disk unlocks without the passphrase (README.md, "Unlock the disk with the TPM").
DONE
fi
