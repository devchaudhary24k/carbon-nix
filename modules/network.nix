# Remote access policy. Which physical interface is reachable differs per
# machine, so hosts/<name> opens ports on its own NIC.
{
  programs.ssh.startAgent = true;

  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  networking.firewall = {
    enable = true;
    logRefusedConnections = false;
    interfaces.tailscale0.allowedTCPPorts = [ 22 ];
  };
}
