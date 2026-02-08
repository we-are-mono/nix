{ config, lib, pkgs, ... }:

{
  # --- Boot ---
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.loader.grub.enable = false;
  boot.kernelPackages = pkgs.linuxPackagesFor pkgs.mono-gateway-kernel;
  boot.kernelParams = [
    "console=ttyS0,115200"
    "earlycon=uart8250,mmio,0x21c0500"
  ];

  # Embedded board: all boot-critical drivers are built-in, no default x86 modules
  boot.initrd.includeDefaultModules = false;
  boot.initrd.availableKernelModules = [ ];

  # Grow root filesystem to fill eMMC partition on first boot
  boot.initrd.extraUtilsCommands = ''
    copy_bin_and_libs ${pkgs.e2fsprogs}/sbin/resize2fs
  '';
  boot.initrd.postMountCommands = ''
    resize2fs /dev/mmcblk0p1 || true
  '';

  # Explicit DTB for extlinux.conf FDT entry
  hardware.deviceTree.name = "freescale/mono-gateway-dk-sdk.dtb";

  # --- Filesystems ---
  fileSystems."/" = {
    device = "/dev/mmcblk0p1";
    fsType = "ext4";
  };

  # --- Serial console ---
  systemd.services."serial-getty@ttyS0".enable = true;

  # --- Networking ---
  networking.hostName = "gateway";

  # --- SSH ---
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "yes";
  services.openssh.settings.PermitEmptyPasswords = "yes";

  # --- Users ---
  users.users.root.initialHashedPassword = "";

  # --- Out-of-tree kernel modules ---
  boot.extraModulePackages = [
    pkgs.mono-gateway-sfp-led
    pkgs.mono-gateway-lp5812-driver
    pkgs.mono-gateway-auto-bridge
    pkgs.mono-gateway-cdx
    pkgs.mono-gateway-fci
  ];

  # --- ASK fast path module loading ---
  # auto_bridge has no dependencies, load early
  boot.kernelModules = [ "auto_bridge" ];

  # CDX and FCI loaded via systemd for proper ordering and retry.
  # CDX calls dpa_app as a usermode helper, which needs /etc/*.xml config files
  # to be present (created by environment.etc / systemd-tmpfiles).
  systemd.services.load-ask-modules = {
    description = "Load ASK Fast Path Kernel Modules (CDX + FCI)";
    after = [ "systemd-tmpfiles-setup.service" ];
    wants = [ "systemd-tmpfiles-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    before = [ "cmm.service" ];
    unitConfig.ConditionPathIsDirectory = "/sys/bus/fsl-mc";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = [
        "${pkgs.kmod}/bin/modprobe cdx"
        "${pkgs.kmod}/bin/modprobe fci"
      ];
    };
  };

  # --- Userspace packages ---
  environment.systemPackages = [
    pkgs.mono-gateway-fmc
    pkgs.mono-gateway-status-led
    pkgs.lm_sensors
    pkgs.mono-gateway-dpa-app
    pkgs.mono-gateway-cmm
  ];

  # --- CMM fast path daemon ---
  systemd.services.cmm = {
    description = "CMM Connection Management Module for ASK Fast Path";
    after = [ "network.target" "load-ask-modules.service" ];
    wants = [ "load-ask-modules.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/dev/cdx_ctrl";
    serviceConfig = {
      Type = "forking";
      ExecStartPre = "-/bin/sh -c 'test -e /sys/class/vwd/vwd0/vwd_fast_path_enable && echo 1 > /sys/class/vwd/vwd0/vwd_fast_path_enable'";
      ExecStart = "${pkgs.mono-gateway-cmm}/bin/cmm -f /etc/config/fastforward -n 131072";
      ExecStopPost = "-/bin/sh -c 'test -e /sys/class/vwd/vwd0/vwd_fast_path_enable && echo 0 > /sys/class/vwd/vwd0/vwd_fast_path_enable'";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # --- DPA-App config files (dpa_app expects these at /etc/) ---
  environment.etc."cdx_cfg.xml".source = "${pkgs.mono-gateway-dpa-app}/etc/cdx_cfg.xml";
  environment.etc."cdx_pcd.xml".source = "${pkgs.mono-gateway-dpa-app}/etc/cdx_pcd.xml";
  environment.etc."cdx_sp.xml".source = "${pkgs.mono-gateway-dpa-app}/etc/cdx_sp.xml";

  # --- FMC PDL config (dpa_app expects at /etc/fmc/config/) ---
  environment.etc."fmc/config/hxs_pdl_v3.xml".source = "${pkgs.mono-gateway-fmc}/etc/fmc/config/hxs_pdl_v3.xml";

  # --- CMM fastforward config ---
  environment.etc."config/fastforward".source = ../pkgs/cmm/fastforward;

  # --- Fancontrol ---
  hardware.fancontrol.enable = true;
  hardware.fancontrol.config = builtins.readFile ../pkgs/fancontrol/fancontrol.conf;

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
