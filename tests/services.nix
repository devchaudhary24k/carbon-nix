# Boots a host's real configuration in a VM and checks that the services it
# claims to run actually come up.
#
# Disks are the one thing this cannot test: the qemu-vm module replaces
# fileSystems wholesale with its own scratch disk. tests/disks.nix covers
# carbon's layout separately.
{
  inputs,
  name,
  pkgs,
  sharedModules,
}:

pkgs.testers.runNixOSTest {
  name = "${name}-services";

  # By default each node reuses the caller's package set and nixpkgs.config
  # becomes read-only. The hosts set overlays and an unfree list, so the node
  # has to evaluate its own.
  node.pkgsReadOnly = false;

  # The same way flake.nix passes it, so modules can use it in `imports`.
  node.specialArgs = { inherit inputs; };

  nodes.machine =
    { lib, ... }:
    {
      imports = sharedModules ++ [ ../hosts/${name} ];

      virtualisation = {
        cores = 2;
        diskSize = 8192;
        graphics = false;
        memorySize = 4096;
      };

      # The qemu-vm module boots its own way, with its own disk.
      my.secureBoot.enable = lib.mkForce false;
      boot.initrd.luks.devices = lib.mkForce { };
      boot.loader.systemd-boot.enable = lib.mkForce false;
      boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
      swapDevices = lib.mkForce [ ];

      # The upgrade service and its guard stay defined so the test can run
      # the guard, but the timer is unhooked: a VM booting with a stale clock
      # would otherwise start a real upgrade.
      systemd.timers.nixos-upgrade.wantedBy = lib.mkForce [ ];

      # The bots need real account directories and a real Minecraft server.
      # Define the units so their configuration can be checked, but never let
      # them start.
      systemd.targets.mcc.wantedBy = lib.mkForce [ ];

      # Meaningful on physical hardware, not in QEMU.
      hardware.rasdaemon.enable = lib.mkForce false;
      services.fwupd.enable = lib.mkForce false;
      services.smartd.enable = lib.mkForce false;
    };

  testScript =
    { nodes, ... }:
    let
      config = nodes.machine;
      user = config.my.user;
      enabled = cond: if cond then "True" else "False";
      # The sessions the login screen offers. Only exists with a desktop.
      sessionsDir =
        if config.my.desktop.enable then
          "${config.services.displayManager.sessionData.desktops}/share/wayland-sessions"
        else
          "";
    in
    ''
      user = "${user}"
      dev = ${enabled config.my.dev.enable}
      desktop = ${enabled config.my.desktop.enable}
      hyprland = ${enabled (config.my.desktop.enable && config.my.desktop.hyprland.enable)}
      t3_server = ${enabled config.my.t3code.server.enable}
      t3_desktop = ${enabled config.my.t3code.desktop.enable}
      hub = ${enabled config.my.monitoring.hub.enable}
      mcc = ${enabled config.services.minecraft-mcc.enable}
      auto_upgrade = ${enabled config.my.autoUpgrade.enable}

      def user_unit_active(unit):
          machine.wait_until_succeeds(
              f"systemctl --machine={user}@.host --user is-active --quiet {unit}",
              timeout=90,
          )

      machine.start()
      machine.wait_for_unit("multi-user.target")

      with subtest("core services"):
          for unit in [
              "sshd.service",
              "tailscaled.service",
              "NetworkManager.service",
              "systemd-resolved.service",
              "vnstat.service",
              "home-manager-" + user + ".service",
          ]:
              machine.wait_for_unit(unit)

      with subtest("tailscale settings were applied"):
          # tailscaled-set.service is a one-shot that runs `tailscale set` and
          # exits, so check its effect rather than its state.
          machine.wait_until_succeeds("tailscale debug prefs | grep -q 'RunSSH.*true'", timeout=60)
          prefs = machine.succeed("tailscale debug prefs")
          assert '"RunSSH": true' in prefs, prefs
          assert f'"OperatorUser": "{user}"' in prefs, prefs

      with subtest("logging tools"):
          machine.succeed("sysreport")
          for command in ["sar", "atop", "vnstat", "smartctl", "coredumpctl"]:
              machine.succeed(f"command -v {command}")
          machine.succeed("journalctl -u hardware-inventory | grep -F 'hardware inventory'")

      with subtest("home manager and dotfiles"):
          machine.succeed(f"test -e /home/{user}/.config/fish/config.fish")
          machine.succeed(f"test -e /home/{user}/.config/starship.toml")
          machine.succeed(f"grep -q 'ssh-ed25519' /etc/ssh/authorized_keys.d/{user}")

      if dev:
          with subtest("development tools"):
              machine.wait_for_unit("docker.service")
              machine.succeed("docker info >/dev/null")
              for command in [
                  "claude", "codex", "bun", "node", "pnpm", "uv", "ruff",
                  "gcc", "just", "lazydocker", "chromium",
              ]:
                  machine.succeed(f"command -v {command}")
              machine.succeed("vp --version")
              machine.succeed("test -e /lib64/ld-linux-x86-64.so.2")

      if t3_server:
          with subtest("T3 Code server runs as a user service"):
              user_unit_active("t3code.service")
              machine.wait_until_succeeds(
                  "curl -fsS -o /dev/null http://127.0.0.1:3773/", timeout=90
              )
              machine.succeed("t3 --version")

      if t3_desktop:
          with subtest("T3 Code desktop app is installed"):
              machine.succeed("command -v t3code-desktop")
              machine.succeed("test -e /run/current-system/sw/share/applications/t3code.desktop")

      if hub:
          with subtest("Beszel hub answers"):
              machine.wait_for_unit("beszel-hub.service")
              machine.wait_until_succeeds(
                  "curl -fsS -o /dev/null http://127.0.0.1:8090/", timeout=60
              )

      if auto_upgrade:
          with subtest("the upgrade guard refuses a system it cannot trace to main"):
              # The VM has no network, and a locally built test system is
              # either dirty or unpushed. Either way the guard must refuse.
              machine.succeed("command -v auto-upgrade-guard")
              machine.fail("auto-upgrade-guard")

      if mcc:
          with subtest("minecraft bots are configured but not running"):
              # Ports are assigned in account-name order from basePort 33331,
              # so kartik is the fourth.
              machine.succeed(
                  "systemctl cat mcc-kartik.service "
                  "| grep -F 'ChatBot.McpServer.Transport.Port=33334'"
              )
              machine.fail("systemctl is-active --quiet mcc-kartik.service")
              machine.succeed("mcc list | grep -x kartik")

      if desktop:
          with subtest("KDE Plasma and apps are installed"):
              machine.wait_for_unit("display-manager.service")
              machine.succeed("systemctl cat display-manager.service | grep -q sddm")
              sessions = machine.succeed("ls ${sessionsDir}")
              assert "plasma.desktop" in sessions, f"no Plasma session: {sessions}"
              for command in ["plasmashell", "dolphin", "ghostty", "steam", "firefox"]:
                  machine.succeed(f"command -v {command}")

      if hyprland:
          with subtest("Hyprland is offered next to Plasma"):
              assert "hyprland-uwsm.desktop" in sessions, f"no Hyprland session: {sessions}"
              for command in ["Hyprland", "hyprlock", "waybar"]:
                  machine.succeed(f"command -v {command}")
              machine.succeed(f"test -e /home/{user}/.config/hypr/hyprland.lua")
              machine.succeed(f"test -e /home/{user}/.config/uwsm/env-hyprland")
              machine.succeed(f"test -e /home/{user}/.config/waybar/config.jsonc")
      elif desktop:
          with subtest("Hyprland stays off"):
              assert "hyprland" not in sessions, f"Hyprland session present: {sessions}"
              machine.fail("command -v Hyprland")
              machine.fail(f"test -e /home/{user}/.config/hypr")
    '';
}
