# Networking every machine shares. Tailscale is in tailscale.nix. Which
# physical interface accepts SSH differs per machine, so hosts/<name> opens
# port 22 on its own NIC if it wants LAN access.
{
  networking.networkmanager.enable = true;

  # Split DNS: MagicDNS names (carbon, nukebyte) go to Tailscale, everything
  # else to the network's resolver. NetworkManager hands DNS to resolved.
  services.resolved.enable = true;

  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  networking.firewall = {
    enable = true;
    # Blocked connection attempts land in the kernel log:
    #   journalctl -k --grep 'refused connection'
    logRefusedConnections = true;
  };
}
