# Networking, firewall, SSH, NTP
{ config, lib, pkgs, ... }:

{
  networking.hostName = "gateway";
  networking.nftables.enable = true;  # native nftables (xt_LOG removed in 6.x kernel)

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
  };

  # --- SSH (key-only, no password auth) ---
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "prohibit-password";
  services.openssh.settings.PasswordAuthentication = false;

  # --- NTP ---
  services.timesyncd.enable = true;
}
