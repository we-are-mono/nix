# Board-specific hardware configuration for Mono Gateway DK (LS1046A)
# Boot, kernel, DTB, eMMC tuning, serial console, fancontrol, watchdog
{
  config,
  lib,
  pkgs,
  ...
}: {
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
  boot.initrd.availableKernelModules = [];
  boot.initrd.systemd.tpm2.enable = false;
  # systemd 260 otherwise carries this active oneshot across switch-root,
  # preventing stage 2 from applying the real-root sysctl configuration.
  boot.initrd.systemd.services.systemd-sysctl.serviceConfig.RemainAfterExit = false;

  # Grow root filesystem to fill eMMC partition on first boot
  boot.initrd.systemd.extraBin.resize2fs = "${pkgs.e2fsprogs}/bin/resize2fs";
  boot.initrd.systemd.services.resize-root = {
    description = "Grow the root filesystem to fill the eMMC partition";
    wantedBy = ["initrd-root-fs.target"];
    after = ["sysroot.mount"];
    before = ["initrd-root-fs.target"];
    unitConfig.ConditionPathExists = "/dev/mmcblk0p1";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/bin/resize2fs /dev/mmcblk0p1";
    };
  };

  # Explicit DTB for extlinux.conf FDT entry
  hardware.deviceTree.name = "freescale/mono-gateway-dk-sdk.dtb";

  # --- Filesystems ---
  fileSystems."/" = {
    device = "/dev/mmcblk0p1";
    fsType = "ext4";
    options = [
      "noatime" # no access-time writes — biggest single win for eMMC
      "commit=60" # flush journal every 60s instead of 5s — coalesces writes
    ];
  };

  # --- Serial console ---
  systemd.services."serial-getty@ttyS0" = {
    enable = true;
    serviceConfig.ExecStart = [
      "" # clear the default
      "@${pkgs.util-linux}/sbin/agetty agetty --autologin root --noclear 115200 ttyS0 vt100"
    ];
  };

  # Auto-detect terminal size on serial console
  programs.bash.loginShellInit = ''
    [ "$TERM" != "dumb" ] && eval "$(resize)" 2>/dev/null
  '';

  # --- eMMC wear reduction ---
  boot.kernel.sysctl = {
    "vm.dirty_writeback_centisecs" = 6000;
    "vm.dirty_expire_centisecs" = 6000;
  };

  services.fstrim.enable = true;

  # Journal: volatile only (RAM) to avoid eMMC writes
  services.journald.extraConfig = ''
    Storage=volatile
    RuntimeMaxUse=50M
  '';

  # --- Fancontrol (EMC2305) ---
  hardware.fancontrol.enable = true;
  hardware.fancontrol.config = builtins.readFile ../pkgs/fancontrol/fancontrol.conf;

  # --- Out-of-tree hardware kernel modules ---
  boot.extraModulePackages = [
    pkgs.mono-gateway-sfp-led
    pkgs.mono-gateway-lp5812-driver
  ];

  # --- Watchdog ---
  systemd.settings.Manager.RuntimeWatchdogSec = "30s";
  systemd.settings.Manager.RebootWatchdogSec = "60s";
}
