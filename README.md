# carbon-nix

NixOS configuration for my machines, in one repo with one `flake.lock`.

| Host       | What it is                                    | Notes                                                    |
| ---------- | --------------------------------------------- | -------------------------------------------------------- |
| `carbon`   | Headless AMD box, 240 GB SSD + 1 TB HDD       | Always on. T3 Code server, Minecraft bots, Beszel hub.   |
| `nukebyte` | ASUS TUF A15 (FA506IC) laptop, usually docked | Hyprland, Secure Boot, TPM-unlocked encrypted disk       |

## Layout

```
flake.nix            Inputs, and one nixosConfiguration per host
hosts/<name>/        Everything true of exactly one machine: disks, hardware, switches
modules/core/        Every machine: nix, user, shell, network, Tailscale, logs, boot
modules/dev.nix      Compilers, runtimes, coding agents, Docker, nix-ld
modules/desktop/     Hyprland or KDE Plasma, audio, Bluetooth, apps, Steam
modules/services/    T3 Code, Minecraft bots
home/dev24k/         Home Manager: links dotfiles into place
packages/            Packages built here: t3code, vite-plus, minecraft-console-client
installer/           Bare-metal install script
tests/               VM tests, run by nix flake check
```

Every host imports all of `modules/`. Anything outside `core/` stays off until
the host switches it on in `hosts/<name>/default.nix`:

```nix
my = {
  dev.enable = true;
  desktop.enable = true;
  t3code.server.enable = true;
};
```

So a module only ever affects the machines that ask for it, and that file is
the one place to see what a machine runs.

The rule that keeps this honest: a disk serial, an interface name, a hostname
or a monitor layout goes in `hosts/<name>/`. If a file in `modules/` mentions
carbon or nukebyte, it is in the wrong place.

Configuration files for programs (fish, starship, git, Hyprland) live in the
[dotfiles](https://github.com/devchaudhary24k/dotfiles) repo. This repo links
fish, starship and git into place through Home Manager; the rest, which you
edit often, are linked by the dotfiles repo's own `dots link` so they stay
writable.

## Everyday changes

Edit, apply, commit, push:

```bash
rebuild                          # nh os switch: builds, shows what changed, switches
git commit -am "Add the thing"
git push
```

`rebuild` builds whichever machine you are on. To change the other one from
here:

```bash
nixos-rebuild switch --flake .#carbon --target-host carbon --sudo
```

To try something without keeping it, `nh os test` switches until the next
reboot. Every rebuild is also a boot menu entry, so a broken change is undone
by picking the previous entry at boot.

### Updating packages

Packages only change when `flake.lock` does:

```bash
nix flake update                  # everything
nix flake update dotfiles         # after pushing to the dotfiles repo
./packages/t3code/update.sh       # newest T3 Code nightly (--stable for releases)
rebuild
```

The OS follows the `nixos-26.05` release branch, which keeps receiving
security fixes. A new release comes out every May and November; moving to it
means changing `nixos-26.05` (and Home Manager's `release-26.05`) in
`flake.nix`. Claude Code and Codex come from `nixos-unstable` so they stay
current between releases.

### Where packages go

| Kind                                   | File                                      |
| -------------------------------------- | ----------------------------------------- |
| Command line tool for every machine    | `modules/core/packages.nix`               |
| Development tool                       | `modules/dev.nix`                         |
| Desktop app                            | `modules/desktop/default.nix`             |
| Unfree package (Chrome, Steam, ...)    | also add its name to `my.unfree`          |
| Not in nixpkgs                         | a new directory in `packages/`            |

A downloaded binary that is not from Nix fails with `No such file or
directory` because NixOS has no `/lib`. `programs.nix-ld` in `modules/dev.nix`
fixes that for most of them; when one still fails on a missing `.so`, add the
library to its list.

## Carbon deploys itself

Every night at 04:00 carbon builds `github:devchaudhary24k/carbon-nix` (the
`main` branch) and switches to it. It never reads a local checkout, so **a
change reaches carbon once it is pushed to main**, and a change only rebuilt
by hand would be reverted.

A guard stops that revert: it refuses to switch while carbon runs a system
built from uncommitted changes or from a commit that is not on `main`. Check
it by hand with `auto-upgrade-guard`, and read why it refused with
`journalctl -u nixos-upgrade`.

Nukebyte does not deploy itself; it changes when you run `rebuild`.

## Logs

Everything stays on the machine. `modules/core/logging.nix` lists every
command; the ones you will use most:

```bash
sysreport                         # one-page summary: failures, errors, disks, temps, traffic
journalctl -b -p warning          # warnings and errors since boot
journalctl -b -1 -p err           # errors from the previous boot
sar -n DEV                        # network traffic per interface today, every 5 minutes
atop -r                           # replay per-process CPU and memory history
vnstat -d                         # data used per day
```

Beszel shows both machines on one dashboard at http://carbon:8090.

## Tailscale

`modules/core/tailscale.nix` sets up Tailscale SSH, Taildrop, and on carbon
an exit node and a route to the home LAN. Day to day:

```bash
ssh carbon                        # Tailscale SSH, no keys needed
tailscale file cp photo.jpg carbon:   # Taildrop; lands in ~/Downloads/Taildrop
tailscale set --exit-node=carbon  # send all traffic through home (public Wi-Fi)
tailscale set --exit-node=        # stop
tailscale serve 3000              # https://<machine>.<tailnet>.ts.net for your devices
tailscale funnel 3000             # the same, on the public internet
```

Every port on each machine is open to your own tailnet devices and nothing
else, so dev servers are reachable as `http://carbon:<port>`.

## T3 Code

Carbon runs the T3 Code server as a user service (`systemctl --user status
t3code`) on port 3773. Nukebyte has the desktop app, which runs its own local
server and can also connect to carbon's. Both come from
`packages/t3code/sources.json`, so they are always the same version. Update
with `./packages/t3code/update.sh`, not `t3 update`.

## Installing

Boot the NixOS installer from USB, connect to the network, then:

```bash
git clone https://github.com/devchaudhary24k/carbon-nix
cd carbon-nix
sudo ./installer/install.sh --host <carbon|nukebyte>
```

The script reads the disks from `hosts/<host>/disks.nix`, refuses to touch a
mounted disk, prints what it is about to erase, and requires the phrase
`ERASE <HOST>`. disko partitions and formats, `nixos-install` runs, and you
set your login password. The repo ends up in `~/code/carbon-nix`.

### Before reinstalling carbon

Both disks are wiped, including the 1 TB HDD (it changes from Btrfs to
ext4). Copy off first:

- `~/code` and anything else in your home directory you want to keep
- `~/.t3` (T3 Code threads and settings) and `~/.claude`, `~/.codex`
- `/opt/mcc/accounts` (bot logins and session tokens)
- anything on `/srv/bulk` you want to keep

Restore `/opt/mcc/accounts` and `~/.t3` after the install, before starting
the bots and the T3 service.

### Before installing nukebyte

1. Copy off anything from Windows; the whole drive is erased.
2. In the BIOS (F2 at power-on), under Security > Secure Boot > Key
   Management, clear the Secure Boot keys so the firmware is in Setup Mode.
   Do not pick an option that also wipes the forbidden signature list (dbx).
3. Run the installer. It asks for a disk passphrase; this is temporary
   until the TPM is enrolled, but keep it until then.

### After installing

On every machine:

```bash
sudo tailscale up                 # log in once; the settings are applied automatically
```

Then, in the Tailscale admin console:

- approve carbon's exit node and subnet route (Machines > carbon > Edit route
  settings), and turn off key expiry for carbon so it never drops off;
- under Access controls, change the SSH rule's `"action": "check"` to
  `"accept"` if the browser re-login every 12 hours for `ssh carbon` gets in
  the way.

Beszel: open http://carbon:8090, create the admin account, click "Add
system", copy the public key into `my.monitoring.hubKey` in
`modules/core/monitoring.nix`, push, and rebuild both machines. Then add each
machine in the dialog by its Tailscale name, port 45876.

On nukebyte, limit the battery to 80% since it lives on the charger:

```bash
asusctl battery limit 80
```

### Unlock the disk with the TPM (nukebyte)

The first boot generates Secure Boot keys, enrolls them and reboots once by
itself. Check it worked:

```bash
bootctl status | grep "Secure Boot"   # Secure Boot: enabled (user)
```

Then let the TPM unlock the disk, but only when Secure Boot is on and the
keys are yours (PCR 7). Create a recovery key at the same time and store it
in your password manager:

```bash
sudo systemd-cryptenroll /dev/nvme0n1p2 --recovery-key
sudo systemd-cryptenroll /dev/nvme0n1p2 --tpm2-device=auto --tpm2-pcrs=7
```

Reboot; the disk unlocks with no prompt. Once that works, remove the
install-time passphrase so only the TPM and the recovery key remain:

```bash
sudo systemd-cryptenroll /dev/nvme0n1p2 --wipe-slot=password
```

If Secure Boot is ever turned off or the keys change, the TPM refuses and boot
asks for the recovery key. Re-enroll with the second command above.

### First login on nukebyte

ly, a text login screen, starts Hyprland. Hyprland's config comes from the
dotfiles repo; link it once, and from then on editing `~/.config/hypr`
edits the repo:

```bash
git clone https://github.com/devchaudhary24k/dotfiles ~/code/dotfiles
~/code/dotfiles/bin/dots link hypr waybar uwsm
hyprctl reload
```

Super+Return opens a terminal and Super+D the launcher; the rest of the keys
are in `hyprland.lua`. Monitor rules are in `monitors/nukebyte.lua` there;
`hyprctl monitors` shows each monitor's name.

To go back to KDE Plasma, set `my.desktop.plasma.enable = true;` in
`hosts/nukebyte/default.nix` and rebuild. With both on, SDDM replaces ly and
offers both sessions.

Check the GPU bus IDs in `hosts/nukebyte/hardware.nix` against
`lspci -D | grep -E 'VGA|3D'`. For games, set Steam's launch option to
`nvidia-offload gamemoderun %command%`.

## Adding a machine

1. `mkdir hosts/<name>` with `default.nix`, `hardware.nix` and `disks.nix`.
2. Set `networking.hostName` and switch on the `my.*` features it needs.
3. Add one line to `hosts` in `flake.nix`.

That gives you `nixosConfigurations.<name>` and its VM test.

## Tests

```bash
nix flake check
```

`<host>-services` boots each host's configuration in a VM and checks that its
services come up: Tailscale settings, Docker, the T3 server answering,
Beszel, Home Manager links, the upgrade guard, the desktop sessions.
`carbon-disks` partitions scratch disks with carbon's real layout, installs,
and boots from them.
