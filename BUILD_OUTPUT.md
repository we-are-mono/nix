# Build Output Summary

This document describes what the `flake.nix` builds for the Mono Gateway.

## Image Overview

| Property | Value |
|----------|-------|
| **Image Format** | ext4 filesystem |
| **Image Size** | 2.0 GB |
| **Usable Space** | ~1.4 GB populated |
| **Volume Name** | `NIXOS_ROOT` |
| **NixOS Version** | 25.11 |
| **Store Packages** | ~550 paths |

## Kernel

| Property | Value |
|----------|-------|
| **Version** | 6.12.49 |
| **Source** | NXP fork (`nxp-qoriq/linux`) |
| **Architecture** | ARM64 (aarch64) |
| **Image Size** | 17 MB (uncompressed) |
| **Initrd Size** | 9.6 MB |

### Applied Patches

See [KERNEL_PATCHES.md](KERNEL_PATCHES.md) for detailed analysis.

1. **INA234 Power Monitor** - Adds hwmon support for TI INA234
2. **NXP ASK Port** - Hardware acceleration for DPAA/FMan/IPsec offload
3. **FMan Interface Ordering** - Predictable ethernet interface naming

### Device Trees

Both standard and SDK (hardware offload) variants are built:

```
mono-gateway-dk.dtb      # Standard kernel drivers
mono-gateway-dk-sdk.dtb  # SDK with QMan/BMan portals (default)
```

Plus all NXP reference board DTBs:
- `fsl-ls1046a-rdb.dtb`, `fsl-ls1046a-rdb-sdk.dtb`
- `fsl-ls1046a-frwy.dtb`, `fsl-ls1046a-qds.dtb`
- And others for LS1043A/LS1046A variants

## Boot Configuration

The image uses extlinux for boot (U-Boot compatible):

```
/boot/
├── extlinux/
│   └── extlinux.conf        # Boot menu configuration
└── nixos/
    ├── *-Image              # Kernel image
    ├── *-initrd             # Initial ramdisk
    └── *-dtbs/              # Device tree blobs
        └── freescale/
            ├── mono-gateway-dk.dtb
            └── mono-gateway-dk-sdk.dtb
```

### Kernel Command Line

```
console=ttyS0,115200 earlycon=uart8250,mmio,0x21c0500 loglevel=4 lsm=landlock,yama,bpf
```

## Custom Packages

All Mono Gateway-specific packages are cross-compiled for aarch64:

### Kernel Modules

| Package | Version | Description |
|---------|---------|-------------|
| `sfp-led` | 1.0 | SFP transceiver LED monitoring |
| `lp5812-driver` | 1.0 | TI LP5812 LED matrix controller |
| `auto-bridge` | 6.02.0 | ASK auto-bridge fast path module |
| `cdx` | 5.03.1 | Control Data Exchange (ASK core) |
| `fci` | 9.00.12 | Fast path Control Interface |

### Userspace

| Package | Version | Description |
|---------|---------|-------------|
| `fmlib` | - | Frame Manager library (static) |
| `fmc` | 2.2.0 | Frame Manager Configuration tool |
| `libfci` | 9.00.12 | FCI userspace library |
| `libcli` | 1.10.0 | Cisco-like CLI library |
| `cmm` | 17.03.1 | Connection Manager Module daemon |
| `dpa-app` | 4.03.0 | DPA App for FMan offload |
| `status-led` | 1.0 | Boot/online status LED script |

## System Services

### ASK Fast Path Stack

```
                    Boot
                      │
                      ▼
        ┌─────────────────────────┐
        │ load-ask-modules.service│  Loads cdx + fci kernel modules
        │ (oneshot)               │  Condition: /sys/bus/fsl-mc exists
        └────────────┬────────────┘
                     │
                     ▼
        ┌─────────────────────────┐
        │     cmm.service         │  Connection Manager daemon
        │ (forking, auto-restart) │  Condition: /dev/cdx_ctrl exists
        └─────────────────────────┘
                     │
                     ▼
          CMM manages fast path
          connection offloading
```

### Other Services

| Service | Description |
|---------|-------------|
| `sshd.service` | OpenSSH server |
| `dhcpcd.service` | DHCP client |
| `nftables.service` | Firewall |
| `fancontrol.service` | EMC2305 fan control |
| `strongswan-swanctl.service` | IPsec VPN |
| `lldpd.service` | Link Layer Discovery Protocol |

## Filesystem Layout

```
/
├── boot/
│   ├── extlinux/extlinux.conf
│   └── nixos/                    # Kernel, initrd, DTBs
├── nix/
│   └── store/                    # All packages (~550 paths)
├── etc -> /nix/store/...         # Symlink to generated config
├── bin -> /nix/store/...         # Symlink to system binaries
└── nix-path-registration         # Package registration for nix-daemon
```

## Building

```bash
# Full rootfs image (cross-compiled from x86_64)
nix build .#packages.aarch64-linux.rootfsImage -L

# Output: ./result -> /nix/store/...-ext4-fs.img-aarch64-unknown-linux-gnu
```

## Inspecting the Image

```bash
# Mount read-only
sudo mkdir -p /mnt/mono-rootfs
sudo mount -o loop,ro result /mnt/mono-rootfs

# Explore
ls /mnt/mono-rootfs/boot/nixos/
cat /mnt/mono-rootfs/boot/extlinux/extlinux.conf
ls /mnt/mono-rootfs/nix/store/ | wc -l

# Unmount
sudo umount /mnt/mono-rootfs
```

## Flashing

See [README.md](README.md#flashing) for flashing instructions. The image goes on eMMC partition 1 (`/dev/mmcblk0p1`).
