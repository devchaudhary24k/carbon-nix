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
  cat <<'EOF'
Usage: sudo ./installer/install.sh --host <name>

Options:
  --host <name>   Host to install. Must match a directory under hosts/.
  -h, --help      Show this message.

This erases every disk listed in hosts/<name>/disks.nix.
EOF
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
flake="path:$repo_root#$host"

echo "Reading the disk layout from hosts/$host/disks.nix ..."
mapfile -t target_disks < <(
  nix "${nix_flags[@]}" eval --raw \
    "$flake.config.disko.devices.disk" \
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
# It destroys the existing layout, formats, and mounts everything under /mnt.
echo "Building the disko script for $host ..."
disko_script="$(
  nix "${nix_flags[@]}" build --no-link --print-out-paths \
    "$flake.config.system.build.diskoScript"
)"

echo "Partitioning and mounting ..."
"$disko_script"

echo "Copying the configuration to /mnt/etc/nixos ..."
install -d -m 0755 /mnt/etc/nixos
cp -a "$repo_root"/. /mnt/etc/nixos/

# hardware.nix is committed rather than generated, because disko already owns
# the filesystems and the remaining hardware detection rarely changes. Compare
# them so a new machine's differences are not silently ignored.
generated_hardware="$(mktemp)"
nixos-generate-config --root /mnt --show-hardware-config > "$generated_hardware"
if ! diff -q \
  <(grep -oE '"[a-z0-9_]+"' "/mnt/etc/nixos/hosts/$host/hardware.nix" | sort -u) \
  <(grep -oE '"[a-z0-9_]+"' "$generated_hardware" | sort -u) >/dev/null; then
  echo
  echo "Note: the detected hardware differs from hosts/$host/hardware.nix."
  echo "Generated copy left at /mnt/etc/nixos/hosts/$host/hardware-detected.nix"
  cp "$generated_hardware" "/mnt/etc/nixos/hosts/$host/hardware-detected.nix"
fi
rm -f "$generated_hardware"

echo "Installing ..."
nixos-install --flake "path:/mnt/etc/nixos#$host" --no-root-passwd

primary_user="$(
  nix "${nix_flags[@]}" eval --raw "$flake.config.machine.primaryUser"
)"
nixos-enter --root /mnt -c "passwd $primary_user"

cat <<EOF

Installed $host. Next:
  1. Reboot.
  2. sudo tailscale up --ssh=false
  3. sudo /etc/nixos/installer/setup-monitoring.sh
EOF
