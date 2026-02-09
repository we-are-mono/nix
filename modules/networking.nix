# Networking, firewall, SSH, NTP, IPsec, LLDP
{ config, lib, pkgs, ... }:

{
  networking.hostName = "gateway";
  networking.nftables.enable = true;  # native nftables (xt_LOG removed in 6.x kernel)

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;

    # 10GbE socket buffer tuning (defaults are too small)
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.core.rmem_default" = 1048576;
    "net.core.wmem_default" = 1048576;
  };

  # --- SSH (key-only, no password auth) ---
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "prohibit-password";
  services.openssh.settings.PasswordAuthentication = false;

  # --- NTP ---
  services.timesyncd.enable = true;

  # --- IPsec (uses kernel XFRM + CAAM hardware crypto offload) ---
  services.strongswan-swanctl.enable = true;

  # --- LLDP neighbor discovery ---
  services.lldpd.enable = true;
}
