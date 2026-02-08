# NixOS Port — Implementation Phases

Each phase is self-contained and must build/verify before proceeding to the next.

---

## Phase 1: Flake Scaffolding

**Goal:** Create `flake.nix` with cross-compilation support and an empty NixOS configuration that evaluates cleanly.

**Creates:**
- `flake.nix`

**Details:**
- Input: `nixpkgs` from `github:NixOS/nixpkgs/nixos-25.11`
- Cross-compilation: `localSystem = "x86_64-linux"`, `crossSystem = "aarch64-linux"`
- Also support native aarch64 builds
- Expose: `nixosConfigurations.gateway`, package outputs, image output
- Import packages from `pkgs/` via overlay (empty for now)

**Verify:** `nix flake check` and `nix eval .#nixosConfigurations.gateway.config.system.stateVersion`

**Status: DONE**

Files created:
- `flake.nix`
- `configurations/gateway.nix` (minimal stub)
- `flake.lock` (auto-generated, pinned nixpkgs `23d72da` 2026-02-07)

Verification ran:
```
$ nix flake show
├───nixosConfigurations
│   ├───gateway: nixos-configuration
│   └───gateway-native: nixos-configuration
└───overlays
    └───default: nixpkgs-overlay

$ nix eval .#nixosConfigurations.gateway.config.system.stateVersion
"25.11"
```

---

## Phase 2: Kernel

**Goal:** Build the patched NXP LS1046A kernel with device trees.

**Creates:**
- `pkgs/kernel/default.nix`
- `pkgs/kernel/defconfig` (copied from Yocto)
- `pkgs/kernel/patches/001-hwmon-ina2xx-Add-INA234-support.patch`
- `pkgs/kernel/patches/002-mono-gateway-ask-kernel_linux_6_12.patch`
- `pkgs/kernel/patches/003-fman-respect-ethernet-aliases.patch`
- `pkgs/kernel/dts/mono-gateway-dk.dts`
- `pkgs/kernel/dts/mono-gateway-dk-sdk.dts`
**Details (from Yocto recipe `linux-mono_6.12.bb`):**
- Source: `nxp-qoriq/linux` rev `df24f9428e38740256a410b983003a478e72a7c0` (branch `lf-6.12.y`)
- Version: `6.12.49`
- Use `linuxManualConfig` with `configfile = ./defconfig`
- Apply 3 patches in numeric order (NOT the legacy 999 patch)
- `postPatch` via `.overrideAttrs`: copy DTS files + register them in freescale/Makefile
- Key defconfig options: `CONFIG_FSL_SDK_DPAA_ETH`, `CONFIG_FSL_FMAN`, `CONFIG_CRYPTO_DEV_FSL_CAAM`, `CONFIG_XFRM_OFFLOAD`

**Source files to copy from:**
- `meta-mono-bsp/recipes-kernel/linux/files/defconfig`
- `meta-mono-bsp/recipes-kernel/linux/files/001-*.patch`
- `meta-mono-bsp/recipes-kernel/linux/files/002-*.patch`
- `meta-mono-bsp/recipes-kernel/linux/files/003-*.patch`
- `meta-mono-bsp/recipes-kernel/linux/files/mono-gateway-dk.dts`
- `meta-mono-bsp/recipes-kernel/linux/files/mono-gateway-dk-sdk.dts`

**Verify:** `nix build .#packages.aarch64-linux.kernel`

**Status: DONE**

Notes:
- `linuxManualConfig` doesn't accept `postPatch` directly — used `.overrideAttrs` instead
- DTS files must also be registered in `arch/arm64/boot/dts/freescale/Makefile` (append `dtb-$(CONFIG_ARCH_LAYERSCAPE)` entries)
- Skipped `mono-gateway-dk-usdpaa-xg-only.dts` (not needed)
- Source hash: `sha256-+cYjZ26Hx4tGR1tVz4p47TF4HG/9IS1tDnLIDDWsRFA=`

Verification ran:
```
$ nix build .#packages.aarch64-linux.kernel
$ ls result/dtbs/freescale/ | grep mono
mono-gateway-dk.dtb
mono-gateway-dk-sdk.dtb
$ file result/Image
result/Image: Linux kernel ARM64 boot executable Image, little-endian, 4K pages
```

---

## Phase 3: Basic Rootfs Image

**Goal:** Generate a minimal bootable ext4 rootfs for eMMC, using the custom kernel from Phase 2. Flash to board and verify it boots with SSH access.

**Creates/modifies:**
- `configurations/gateway.nix` (expand minimal stub into bootable config)
- `image/default.nix` (ext4 image builder)

**Details:**
- Use the custom NXP kernel from Phase 2 via `boot.kernelPackages`
- `boot.loader.generic-extlinux-compatible.enable = true`
- `boot.kernelParams = [ "console=ttyS0,115200" ]`
- Serial console on `ttyS0`
- SSH enabled, empty root password for initial bring-up
- Minimal embedded profile (no docs, no fonts)
- ext4 rootfs image for eMMC partition (firmware partitions are separate/pre-existing)
- `system.stateVersion = "25.11"`

**Verify:** `nix build .#packages.aarch64-linux.rootfsImage` then flash and boot on board

**Status: DONE**

Notes:
- Used standard NixOS boot flow (extlinux.conf + initrd) instead of Yocto's hardcoded U-Boot paths
- Requires one-time U-Boot env change: `setenv scriptaddr 0x80000000; setenv bootcmd 'sysboot mmc 0:1 ext2 ${scriptaddr} /boot/extlinux/extlinux.conf'; saveenv`
- U-Boot `sysboot` accepts `ext2` (not `ext4`) as fs type — reads ext4 fine; `scriptaddr` must be set explicitly
- Defconfig expanded from minimal (404 lines) to full .config (5671 lines) on patched kernel tree to satisfy NixOS systemd assertions
- Added `CONFIG_AUTOFS_FS=y` and `CONFIG_CRYPTO_USER_API_HASH=y` (required by NixOS systemd)
- `boot.initrd.includeDefaultModules = false` — embedded board has all boot drivers built-in
- `hardware.deviceTree.name = "freescale/mono-gateway-dk-sdk.dtb"` — explicit FDT entry in extlinux.conf
- Image builder uses `make-ext4-fs.nix` + `populateCmd` from `generic-extlinux-compatible` (same pattern as `sd-image.nix`)

Files created/modified:
- `configurations/gateway.nix` (expanded to full bootable config)
- `image/default.nix` (new — ext4 image builder module)
- `flake.nix` (import image module, expose rootfsImage)
- `pkgs/kernel/defconfig` (expanded to full .config with NixOS-required options)

Verification ran:
```
$ nix build .#packages.aarch64-linux.rootfsImage
$ ls -lh result
-r--r--r-- 1 root root 2.0G Jan  1  1970 result
$ file result
result: Linux rev 1.0 ext4 filesystem data, UUID=44444444-4444-4444-8888-888888888888, volume name "NIXOS_ROOT" (extents) (64bit) (large files) (huge files)
```

---

## Phase 4: FMlib

**Goal:** Build the Frame Manager userspace library (static `libfm-arm.a` + headers).

**Creates:**
- `pkgs/fmlib/default.nix`
- `pkgs/fmlib/01-mono-ask-extensions.patch` (copied from Yocto)

**Details (from Yocto recipe `fmlib_git.bb`):**
- Source: `nxp-qoriq/fmlib` rev `7a58ecaf0d90d71d6b78d3ac7998282a472c4394`
- Apply `01-mono-ask-extensions.patch` (180 lines, ASK support)
- Depends on kernel headers (`KERNEL_SRC` pointed at kernel `dev` output)
- CFLAGS: `-fmacro-prefix-map` and `-fdebug-prefix-map` to avoid build path embedding
- Build: `make libfm-arm.a`
- Install: `make install-libfm-arm` → `$out/lib/libfm-arm.a` + `$out/include/fmd/`
- Remove `$out/usr/src` (kernel headers leak)

**Source files to copy from:**
- `meta-mono-bsp/recipes-support/fmlib/files/01-mono-ask-extensions.patch`

**Verify:** `nix build .#packages.aarch64-linux.fmlib`

**Status: DONE**

Notes:
- `KERNEL_SRC` must point to `.../source` (not `.../build`) — FMan UAPI headers live at `source/include/uapi/linux/fmd/`
- Used custom `installPhase` instead of `installFlags` — stdenv appends a default `install` target that doesn't exist in fmlib's Makefile
- `DESTDIR` must be set via shell `$out` in `installPhase`, not `$(out)` in `installFlags` (Nix escapes it)
- Removed `$out/usr/src` to avoid kernel header leak

Verification ran:
```
$ nix build .#packages.aarch64-linux.fmlib
$ file result/lib/libfm-arm.a
result/lib/libfm-arm.a: current ar archive
$ ls result/include/fmd/Peripherals/
fm_ext.h  fm_mac_ext.h  fm_pcd_ext.h  fm_port_ext.h  fm_vsp_ext.h  ...
```

---

## Phase 5: FMC

**Goal:** Build the Frame Manager Configuration tool (binary + config files).

**Creates:**
- `pkgs/fmc/default.nix`
- `pkgs/fmc/01-mono-ask-extensions.patch` (copied from Yocto)

**Details (from Yocto recipe `fmc_git.bb`):**
- Source: `nxp-qoriq/fmc` rev `5b9f4b16a864e9dfa58cdcc860be278a7f66ac18`
- **Pre-patch:** convert CRLF→LF in `source/*.cpp source/*.h source/spa/*.c source/spa/*.h`
- Apply `01-mono-ask-extensions.patch` (254 lines)
- Dependencies: `fmlib`, `libxml2`, `tclap`
- Build flags: `FMD_USPACE_HEADER_PATH`, `FMD_USPACE_LIB_PATH`, `LIBXML2_HEADER_PATH`, `TCLAP_HEADER_PATH`, `MACHINE=ls1046`
- Build: `make -C source` (**NO parallel make** — `enableParallelBuilding = false`)
- Install: `fmc` binary → `$out/bin/`, config files → `$out/etc/fmc/config/`, `libfmc.a` → `$out/lib/`, `fmc.h` → `$out/include/fmc/`

**Source files to copy from:**
- `meta-mono-bsp/recipes-support/fmc/files/01-mono-ask-extensions.patch`

**Verify:** `nix build .#packages.aarch64-linux.fmc`

**Status: DONE**

Notes:
- CRLF→LF conversion in `prePatch` (upstream has Windows line endings) — required before patch can apply
- `enableParallelBuilding = false` — FMC has build dependency issues with parallel make
- Custom `installPhase` (same pattern as fmlib — no `install` target in Makefile)
- Source hash: `sha256-hGxQJ4pDkqN/P7cONivcNn9t6p7l1af8SoEPVBYiPFk=`

Verification ran:
```
$ nix build .#packages.aarch64-linux.fmc
$ file result/bin/fmc
result/bin/fmc: ELF 64-bit LSB pie executable, ARM aarch64, version 1 (GNU/Linux)
$ ls result/etc/fmc/config/
cfgdata.xsd  hxs_pdl_v3.xml  netpcd.xsd
$ ls result/lib/ result/include/fmc/
result/include/fmc/: fmc.h
result/lib/: libfmc.a
```

---

## Phase 6: Hardware Utilities

**Goal:** Package board-specific utilities (fancontrol, out-of-tree kernel modules, LED control).

**Creates:**
- `pkgs/fancontrol/default.nix` + `fancontrol.conf`
- `pkgs/sfp-led/default.nix` + sources
- `pkgs/lp5812-driver/default.nix` + sources
- `pkgs/status-led/default.nix` + script

### 6a. fancontrol
- Source: `github:lm-sensors/lm-sensors` rev `1667b850a1ce38151dae17156276f981be6fb557`
- Build: `make user` — produces `sensors`, `fancontrol`, `libsensors.so`
- Copy `fancontrol.conf` from `meta-mono-bsp/recipes-support/fancontrol/files/`

### 6b. sfp-led (out-of-tree kernel module)
- Copy `sfp-led.c`, `Makefile` from `meta-mono-bsp/recipes-kernel/sfp-led/files/`
- Build against our custom kernel

### 6c. lp5812-driver (out-of-tree kernel module)
- Copy `leds-lp5812.c`, `leds-lp5812.h`, `Makefile` from `meta-mono-bsp/recipes-kernel/lp5812-driver/files/`
- Build against our custom kernel

### 6d. status-led (shell script)
- Copy `status-led.sh` from `meta-mono-bsp/recipes-support/status-led/files/`
- Install to `$out/bin/`

**Source files to copy from:**
- `meta-mono-bsp/recipes-support/fancontrol/files/fancontrol.conf`
- `meta-mono-bsp/recipes-kernel/sfp-led/files/sfp-led.c`, `Makefile`
- `meta-mono-bsp/recipes-kernel/lp5812-driver/files/leds-lp5812.c`, `leds-lp5812.h`, `Makefile`
- `meta-mono-bsp/recipes-support/status-led/files/status-led.sh`

**Verify:** `nix build .#packages.aarch64-linux.{sfp-led,lp5812-driver,status-led}`

**Status: DONE**

Notes:
- **fancontrol**: Uses nixpkgs' `lm_sensors` + custom `fancontrol.conf` (no custom build needed). Config file kept in `pkgs/fancontrol/fancontrol.conf` for NixOS module use in Phase 7
- **sfp-led / lp5812-driver**: Out-of-tree kernel modules built with custom `buildPhase` — do NOT use `kernel.makeFlags` (contains kernel-build-specific flags like `O=$(buildRoot)` that break out-of-tree builds). Use `make -C ${kernel.dev}/.../build M=$PWD ARCH=arm64 CROSS_COMPILE=... modules`
- **status-led**: Simple shell script, `dontUnpack = true` since src is a single file

Verification ran:
```
$ nix build .#packages.aarch64-linux.sfp-led
$ file result/lib/modules/6.12.49/extra/sfp-led.ko
result/.../sfp-led.ko: ELF 64-bit LSB relocatable, ARM aarch64

$ nix build .#packages.aarch64-linux.lp5812-driver
$ file result/lib/modules/6.12.49/extra/leds-lp5812.ko
result/.../leds-lp5812.ko: ELF 64-bit LSB relocatable, ARM aarch64

$ nix build .#packages.aarch64-linux.status-led
$ ls result/bin/
status-led.sh
```

---

## Phase 7: ASK Fast Path Stack

**Goal:** Build and integrate the full ASK (Acceleration Software Kit) fast path stack — kernel modules, userspace libraries, and daemons for hardware-accelerated packet processing on the LS1046A DPAA engine.

**Source:** ASK repo `github:we-are-mono/ASK` rev `cac8275e43251e17afaeec2cc1b8384303b20df0`

**Creates:**
- `pkgs/libcli/default.nix` — Cisco-like CLI library (from `github:dparrish/libcli`)
- `pkgs/auto-bridge/default.nix` + source files — auto_bridge kernel module
- `pkgs/cdx/default.nix` — CDX (Control Data Exchange) kernel module
- `pkgs/fci/default.nix` — FCI kernel module (depends on CDX Module.symvers)
- `pkgs/libfci/default.nix` — FCI userspace library (autotools)
- `pkgs/cmm/default.nix` — CMM daemon + libcmm (autotools, parallel make disabled)
- `pkgs/cmm/fastforward` — CMM traffic exclusion config
- `pkgs/cmm/01-nxp-ask-comcerto-fp-extensions.patch` — patches libnetfilter_conntrack
- `pkgs/cmm/01-nxp-ask-nonblocking-heap-buffer.patch` — patches libnfnetlink
- `pkgs/dpa-app/default.nix` — DPA App for FMan offload management
- `pkgs/dpa-app/cdx_cfg.xml` — Mono Gateway DK port mapping config
- `pkgs/kernel/sdk-headers.nix` — extracts FMan SDK driver headers from patched kernel source

### Key challenges solved

- **SDK headers stripped by nixpkgs**: nixpkgs removes `drivers/` from kernel dev output (~50MB savings). Created `sdk-headers.nix` that fetches kernel source, applies the ASK kernel patch, and extracts only the driver headers CDX needs.
- **CDX ncsw_config.mk**: CDX Makefile `include`s `ncsw_config.mk` from `$(srctree)/drivers/...`. Replaced with direct `ccflags-y` entries via `substituteInPlace`.
- **Patched dependencies**: CMM requires patched `libnfnetlink` (nonblocking mode) AND patched `libnetfilter_conntrack` (Comcerto FP extensions). Used `.override` to swap `libnfnetlink` inside `libnetfilter_conntrack`, then `.overrideAttrs` for patches.
- **CDX calls dpa_app**: CDX kernel module calls `/usr/bin/dpa_app` via `call_usermodehelper`. Patched to Nix store path via `substituteInPlace`. Broke resulting circular dependency by having dpa-app get `cdx_ioctl.h` from ASK source tree instead of CDX build output.
- **dpa_app config files**: dpa_app expects XML configs at `/etc/cdx_cfg.xml` etc. Added `environment.etc` entries in gateway.nix.
- **Module load ordering**: CDX must load after `/etc/*.xml` symlinks exist. Moved CDX/FCI from `boot.kernelModules` to a dedicated `load-ask-modules.service` that runs after `systemd-tmpfiles-setup.service`.
- **Fancontrol**: Added `hardware.fancontrol.enable` with custom config for EMC2305 fan controller.

### NixOS integration (gateway.nix)

- `boot.extraModulePackages`: auto-bridge, cdx, fci (+ existing sfp-led, lp5812-driver)
- `boot.kernelModules`: auto_bridge (no userspace deps, loads early)
- `systemd.services.load-ask-modules`: loads cdx + fci after tmpfiles setup
- `systemd.services.cmm`: CMM daemon with forking type, restart-on-failure
- `environment.etc`: cdx_cfg.xml, cdx_pcd.xml, cdx_sp.xml, fmc/config/hxs_pdl_v3.xml, config/fastforward
- `environment.systemPackages`: dpa-app, cmm (+ existing fmc, status-led, lm_sensors)

**Verify:** `nix build .#packages.aarch64-linux.rootfsImage` — flash to board, verify CDX/FCI/CMM load

**Status: DONE**

Notes:
- ASK source hash: `sha256-ChkYZLjM5yMt9S1Tib4BesaeTOC803zIMXoeUTduYEw=`
- libcli source hash: `sha256-xGAJytBGJl/+gz0S3xMhd/UJlF7iOJuP3DYNMuVpCmY=`
- All 7 packages cross-compile from x86_64 → aarch64
- `autoreconfHook` runs before `preConfigure` — automake README files must be created in `postUnpack`
- CDX and CMM generate static `version.h` in `preBuild` (no .git dir for `git describe`)

Verification ran:
```
$ nix build .#packages.aarch64-linux.libcli .#packages.aarch64-linux.auto-bridge \
  .#packages.aarch64-linux.cdx .#packages.aarch64-linux.fci .#packages.aarch64-linux.libfci \
  .#packages.aarch64-linux.cmm .#packages.aarch64-linux.dpa-app
(all build successfully)

$ nix build .#packages.aarch64-linux.rootfsImage
$ ls -lh result
result: 1.9G ext4 image
```

---

## Dependency Chain

```
Phase 1 (flake) → Phase 2 (kernel) → Phase 3 (rootfs image — boot test on board)
                                    ↘ Phase 4 (fmlib) → Phase 5 (fmc) → dpa-app
                                    ↘ Phase 6 (hw utils)
                                    ↘ Phase 7 (ASK stack):
                                        sdk-headers ──→ cdx ──→ fci
                                        libcli ────────→ cmm, dpa-app
                                        auto-bridge ──→ cmm (header)
                                        libfci ───────→ cmm
                                        patched libnfnetlink → patched libnetfilter_conntrack → cmm
                                        dpa-app ──────→ cdx (path substitution)
```
