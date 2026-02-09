{ config, lib, pkgs, ... }:

{
  imports = [
    ../modules/hardware.nix
    ../modules/networking.nix
    ../modules/ask-offload.nix
  ];

  # --- ASK fast path ---
  mono-gateway.ask.enable = true;

  # --- Users ---
  users.users.root.initialHashedPassword = "";  # empty password for serial console (physical access = trusted)
  users.users.root.openssh.authorizedKeys.keys = [
    # Managed manually on the device (~/.ssh/authorized_keys)
  ];

  # --- Userspace packages ---
  environment.systemPackages = with pkgs; [
    mono-gateway-status-led
    lm_sensors
    htop
    vim
    xterm  # provides 'resize' for serial console auto-sizing
    tcpdump
    ethtool
    conntrack-tools
    iperf3
    mtr
  ];

  # --- Nix ---
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # --- Minimization ---
  documentation.enable = false;

  # --- First-boot Nix store registration ---
  boot.postBootCommands = ''
    if [ -f /nix-path-registration ]; then
      ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration
      touch /etc/NIXOS
      rm -f /nix-path-registration
    fi
  '';

  system.stateVersion = "25.11";
}
