# NixOS for Mono Gateway Development Kit

> **EXPERIMENTAL** — This is a work-in-progress port from Yocto to NixOS. Things will break. Not suitable for production use.

NixOS flake for the Mono Gateway DK, a custom SBC based on the NXP LS1046A (4x Cortex-A72, 8 GB ECC DDR4, 32 GB eMMC, 3x 1GbE + 2x 10GbE SFP+).

## Prerequisites

- x86_64 Linux host with [Nix](https://nixos.org/download/) installed (flakes enabled)
- ~30 GB disk space for cross-compilation

## Building

```bash
# Full rootfs image (ext4, cross-compiled from x86_64)
nix build .#packages.aarch64-linux.rootfsImage -L

# Individual packages
nix build .#packages.aarch64-linux.kernel
nix build .#packages.aarch64-linux.fmlib
nix build .#packages.aarch64-linux.fmc
nix build .#packages.aarch64-linux.sfp-led
nix build .#packages.aarch64-linux.lp5812-driver
nix build .#packages.aarch64-linux.status-led
nix build .#packages.aarch64-linux.libcli
nix build .#packages.aarch64-linux.auto-bridge
nix build .#packages.aarch64-linux.cdx
nix build .#packages.aarch64-linux.fci
nix build .#packages.aarch64-linux.libfci
nix build .#packages.aarch64-linux.cmm
nix build .#packages.aarch64-linux.dpa-app
```

## Flashing

The rootfs image goes on eMMC partition 1. Firmware partitions (RCW, ATF, U-Boot, FMan microcode) at offsets 0-10 MB are separate and managed by the existing Yocto build. In Recovery linux, run these:

```bash
ip link set eth0 up; ip addr add 10.0.0.199/24 dev eth0; ip route add default via 10.0.0.1 dev eth0 # modify iface and ip
curl -O http://ip-of-your-build-server:8000/result
dd if=result of=/dev/mmcblk0p1 bs=1M
reboot
```

## U-Boot Setup (one-time)

NixOS uses extlinux.conf for boot, replacing the hardcoded Yocto boot paths:

```
setenv scriptaddr 0x80000000
setenv bootcmd 'sysboot mmc 0:1 ext2 ${scriptaddr} /boot/extlinux/extlinux.conf'
saveenv
```

## What's Included

| Component | Description |
|-----------|-------------|
| Kernel | NXP LS1046A patched kernel (6.12.49) with ASK/DPAA/CAAM/FMan support |
| FMlib | Frame Manager userspace library (static) |
| FMC | Frame Manager Configuration tool — loads PCD/PDL rules into FMan hardware |
| sfp-led | Kernel module for SFP transceiver LED monitoring |
| lp5812-driver | Kernel module for TI LP5812 LED matrix controller |
| status-led | Boot/online status LED control script |
| fancontrol | Fan speed control via lm_sensors + custom config for EMC2305 |
| libcli | Cisco-like command-line interface library |
| auto-bridge | Kernel module for ASK auto-bridge fast path |
| CDX | Control Data Exchange kernel module (calls dpa_app at init) |
| FCI | Fast path Control Interface kernel module |
| libfci | FCI userspace library |
| CMM | Connection Manager Module daemon for ASK fast path |
| dpa-app | DPA App for FMan offload management (called by CDX) |

## Architecture

```
flake.nix                  # Entry point, overlay, NixOS configs
configurations/gateway.nix # NixOS system configuration
image/default.nix          # ext4 rootfs image builder
pkgs/
  kernel/                  # Patched NXP kernel + DTS + defconfig
    sdk-headers.nix        # FMan SDK driver headers (from patched kernel source)
  fmlib/                   # Frame Manager library
  fmc/                     # Frame Manager Configuration tool
  sfp-led/                 # SFP LED kernel module
  lp5812-driver/           # LP5812 LED kernel module
  status-led/              # Status LED script
  fancontrol/              # Fancontrol config (uses nixpkgs lm_sensors)
  libcli/                  # Cisco-like CLI library
  auto-bridge/             # Auto-bridge kernel module
  cdx/                     # CDX kernel module (ASK fast path core)
  fci/                     # FCI kernel module (depends on CDX)
  libfci/                  # FCI userspace library
  cmm/                     # CMM daemon + patched lib{nfnetlink,netfilter_conntrack} patches
  dpa-app/                 # DPA App + XML configs
```

Cross-compilation is the default: builds on x86_64, targets aarch64. A `gateway-native` NixOS configuration is also available for on-device builds.

## eMMC Layout

The 32 GB eMMC is split into a 32 MB firmware region and a single ext4 rootfs partition. NixOS only touches the rootfs partition — firmware is flashed separately via the Yocto build.

```
Offset      Size    Contents
────────────────────────────────────────────────
0x000000    512 B   MBR (partition table)
0x001000    ~1 MB   RCW + BL2 (starts at 4 KB for eMMC)
0x100000    2 MB    ATF FIP (BL31 + U-Boot)
0x300000    1 MB    U-Boot environment
0x400000    1 MB    FMan microcode (ASK — do NOT overwrite)
0x500000    1 MB    Device tree (DTB)
0xA00000    ~22 MB  Recovery kernel + initramfs
────────────────────────────────────────────────
0x2000000   ~32 GB  ext4 rootfs partition (/dev/mmcblk0p1)
            (sector 65536 = 32 MB offset)
```

**Warning:** `dd if=image of=/dev/mmcblk0p1` writes to the rootfs partition (safe). `dd if=image of=/dev/mmcblk0` writes to the raw device starting at offset 0 — this will destroy firmware and brick the board.

## Boot Flow

```
RCW -> ATF (BL2/BL31) -> U-Boot -> extlinux.conf -> kernel + initrd -> NixOS
```

Standard NixOS boot with generation switching and rollback support.

## ASK Fast Path Stack

```
                    ┌─────────────┐
                    │   U-Boot    │ loads FMan microcode
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │   Kernel    │ ASK-patched DPAA/FMan drivers
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
        ┌─────▼──────┐ ┌───▼───┐ ┌─────▼─────┐
        │ auto_bridge│ │  CDX  │ │    FCI    │  kernel modules
        └────────────┘ └───┬───┘ └───────────┘
                           │
                     ┌─────▼─────┐
                     │  dpa_app  │  usermode helper (called by CDX)
                     └───────────┘
                     ┌───────────┐
                     │    CMM    │  connection manager daemon
                     └───────────┘
```
