{lib, ...}: {
  name = "mono-gateway-smoke";
  globalTimeout = 900;

  nodes.gateway = {lib, ...}: {
    imports = [../configurations/gateway.nix];

    # QEMU supplies its own device tree and PL011 console. The board earlycon
    # address and first-boot eMMC resize are only meaningful on real hardware.
    hardware.deviceTree.name = lib.mkForce null;
    boot.kernelParams = lib.mkForce [];
    boot.initrd.includeDefaultModules = lib.mkOverride 5 false;
    boot.initrd.availableKernelModules = lib.mkForce [];
    boot.initrd.kernelModules = lib.mkForce [];
    services.timesyncd.enable = lib.mkForce true;
    users.users.root.initialHashedPassword = lib.mkForce null;

    # Keep the hardware-only unit available for inspection without repeatedly
    # trying to control QEMU's unrelated hwmon devices.
    systemd.services.fancontrol.wantedBy = lib.mkForce [];

    # Keep the ARM guest store separate from the x86 host store.
    virtualisation.useNixStoreImage = true;
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
    virtualisation.graphics = false;
    virtualisation.qemu.virtioKeyboard = false;
  };

  testScript = ''
    gateway.start()
    gateway.wait_for_unit("multi-user.target", timeout=300)

    with subtest("boots the production architecture and kernel"):
        gateway.succeed("test $(uname -m) = aarch64")
        gateway.succeed("test $(uname -r) = 6.12.49")

    with subtest("starts portable gateway services"):
        gateway.wait_for_unit("sshd.service")
        gateway.wait_for_unit("nftables.service")
        gateway.wait_for_unit("strongswan-swanctl.service")
        gateway.wait_for_unit("lldpd.service")

    with subtest("applies network tuning"):
        gateway.succeed("test $(sysctl -n net.ipv4.ip_forward) = 1")
        gateway.succeed("test $(sysctl -n net.netfilter.nf_conntrack_max) = 131072")
        gateway.succeed("test $(sysctl -n net.core.rmem_max) = 16777216")

    with subtest("installs ASK programs and configuration"):
        gateway.succeed("test -x /run/current-system/sw/bin/fmc")
        gateway.succeed("test -x /run/current-system/sw/bin/dpa_app")
        gateway.succeed("test -x /run/current-system/sw/bin/cmm")
        gateway.succeed("test -e /etc/cdx_cfg.xml")
        gateway.succeed("test -e /etc/fmc/config/hxs_pdl_v3.xml")
        gateway.succeed("test -e /etc/config/fastforward")

    with subtest("gates hardware-only ASK services"):
        gateway.succeed("test $(systemctl show load-ask-modules.service -P ConditionResult) = no")
        gateway.succeed("test $(systemctl show cmm.service -P ConditionResult) = no")
  '';
}
