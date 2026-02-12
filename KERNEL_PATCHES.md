# Mono Gateway Kernel Patches Analysis

## Overview

The Mono Gateway uses a customized Linux kernel based on **NXP's Layerscape fork** of Linux 6.12.49, sourced from the `nxp-qoriq/linux` repository. Three patches are applied to this base kernel.

---

## Patch 1: INA234 Power Monitor Support

**File:** `001-hwmon-ina2xx-Add-INA234-support.patch`
**Size:** ~3 KB
**Complexity:** Low

### Purpose
Adds support for the Texas Instruments INA234 power monitor IC to the existing `ina2xx` hwmon driver.

### Technical Details
- The INA234 is a 12-bit power/current monitor similar to the INA226
- Key difference: Bus voltage LSB is 1.6mV (effective) vs 1.25mV for INA226
- Modifications to `drivers/hwmon/ina2xx.c`:
  - Adds `ina234` enum variant
  - Defines INA234-specific configuration (calibration, voltage LSB, etc.)
  - Enables critical alarm thresholds for voltage/current/power
  - Adds device tree and I2C ID table entries for `ti,ina234`

### Upstream Status
Marked as "Inappropriate [embedded specific]" - may not be submitted upstream, but the changes are clean and self-contained.

---

## Patch 2: NXP Advanced Switching Kit (ASK) Port

**File:** `002-mono-gateway-ask-kernel_linux_6_12.patch`
**Size:** ~750 KB (massive patch)
**Complexity:** Very High

### Purpose
Ports NXP's proprietary Advanced Switching Kit (ASK) modifications to Linux 6.12. The ASK provides hardware-accelerated packet processing for Layerscape SoCs using the DPAA (Data Path Acceleration Architecture).

### Major Components

#### 1. Device Tree Additions
- New DTS/DTSI files for LS1043A and LS1046A variants:
  - `fsl-ls1043a-dgw.dts`, `fsl-ls1043a-rgw.dts`
  - `fsl-ls1043a-w906x.dtsi`, `fsl-ls1046a-w906x.dtsi`
  - SDK variants with QMan/BMan portal configurations
- DMA coherency adjustments for DPAA operation
- Offline port (OH port) definitions for hardware packet processing

#### 2. SDK DPAA Ethernet Driver (`drivers/net/ethernet/freescale/sdk_dpaa/`)
- Enhanced packet processing with fast path support
- Buffer pool seeding and management
- Statistics collection from hardware offload engine
- Modifications to:
  - `dpaa_eth.c`, `dpaa_eth_common.c`, `dpaa_eth_sg.c`
  - `offline_port.c` - Offline port handling for hardware acceleration

#### 3. SDK FMan Driver (`drivers/net/ethernet/freescale/sdk_fman/`)
- Frame Manager enhancements for packet classification
- Extensive changes to Packet Classification Daemon (PCD):
  - `fm_cc.c` - Coarse Classification engine
  - `fm_ehash.c` - Extended hash table support (new file, ~2000 lines)
  - `fm_kg.c` - KeyGen modifications
  - `fm_manip.c` - Header manipulation
  - `fm_plcr.c` - Policer modifications
- MURAM (Multi-User RAM) management updates
- New ioctl interfaces for userspace control

#### 4. IPsec Hardware Offload (`net/xfrm/`)
- **New file:** `ipsec_flow.c` - Flow table for tracking offloaded IPsec sessions
- Modifications to `xfrm_input.c` and `xfrm_output.c`:
  - Submits packets to SEC (Security Engine) when SA is offloaded
  - Bypasses software encryption/decryption for offloaded flows
- Changes to `xfrm_state.c` and `xfrm_policy.c`:
  - Adds `offloaded` flag and `handle` to xfrm_state
  - State lookup by hardware handle
  - Notifier chain for SA add/delete events
- PF_KEY socket extensions (`net/key/af_key.c`):
  - Hardware offload negotiation in SA messages
  - New attributes for offload status

#### 5. Fast Path Infrastructure
- **Kconfig:** New `CONFIG_CPE_FAST_PATH` option
- **sk_buff extensions** (`include/linux/skbuff.h`):
  - `qosmark` - 64-bit QoS marking
  - `ipsec_offload` - Flag for offloaded packets
  - `iif_index`, `underlying_iif` - Interface tracking
  - `expt_pkt`, `abm_ff` - Fast path flags
- **net_device extensions** (`include/linux/netdevice.h`):
  - `wifi_offload_dev` - Pointer for WiFi offload
  - Modified `dev_queue_xmit()` to intercept offloaded WiFi+IPsec packets

#### 6. Netfilter Extensions
- **New files:**
  - `comcerto_fp_netfilter.c` - Fast path netfilter hooks
  - `xt_qosmark.c` - QoS mark target
  - `xt_qosconnmark.c` - QoS connection mark handling
- **Connection tracking** (`nf_conntrack_core.c`, `nf_conntrack_netlink.c`):
  - `comcerto_fp_info` structure per connection
  - Permanent connection support for offloaded flows
  - Extended netlink attributes for fast path info
  - DPI (Deep Packet Inspection) allow/mark functions

#### 7. Bridge Layer Modifications
- **Notifier chain** for FDB (Forwarding Database) updates
- Port down events for fast path synchronization
- VLAN handling enhancements
- Files modified: `br.c`, `br_fdb.c`, `br_forward.c`, `br_input.c`, `br_vlan.c`

#### 8. IPv6 Tunnel Extensions
- 4RD (IPv4 Residual Deployment) tunnel support
- Post-fragmentation handling for 4-over-6 tunnels
- NPT (Network Prefix Translation) enhancements

#### 9. QBMan Driver Updates (`drivers/staging/fsl_qbman/`)
- Queue Manager high-level API modifications
- Configuration updates for SDK compatibility

#### 10. Other Changes
- PPP/PPPoE modifications for fast path integration
- USB network driver updates
- TCP delayed ACK tuning (`CONFIG_COMCERTO_TCP_DELACK_MIN`)
- Wireless extensions enabled by default

### Upstream Status
Marked as "Inappropriate [NXP vendor kernel modifications]" - these are proprietary NXP extensions that will never be upstreamed.

---

## Patch 3: FMan Interface Registration Order

**File:** `003-fman-respect-ethernet-aliases.patch`
**Size:** ~4 KB
**Complexity:** Medium

### Purpose
Fixes a race condition where ethernet interfaces get unpredictable ifindex values because the SDK DPAA driver registers interfaces in probe order rather than device tree alias order.

### Technical Details
- **Problem:** `eth0` might get ifindex 3 while `eth2` gets ifindex 2
- **Solution:**
  1. Defers `register_netdev()` calls until all devices have probed
  2. Collects pending interfaces in a list
  3. Sorts by device tree ethernet alias at `late_initcall`
  4. Registers in sorted order
- Uses `of_alias_get_id()` to set interface names based on DT aliases
- Defers sysfs initialization to prevent warnings

### Upstream Status
Marked as "Inappropriate [NXP SDK driver]" - specific to the out-of-tree SDK DPAA driver.

---

## Basic Functionality vs Hardware Acceleration

**Important distinction:** The NXP ASK patches are for **hardware acceleration**, not basic ethernet functionality.

### What Works WITHOUT the SDK Patches

The mainline Linux kernel includes a standard DPAA driver (`fsl_dpaa`) that provides full ethernet functionality:

```
# Example from OpenWrt running mainline drivers on LS1046A:
root@OpenWrt:~# ethtool --driver eth0
driver: fsl_dpa          # <-- Mainline driver, NOT sdk_dpaa
version: 6.12.66

root@OpenWrt:~# ifconfig eth0
eth0      Link encap:Ethernet  HWaddr E8:F6:D7:00:12:58
          UP BROADCAST RUNNING MULTICAST  MTU:1500
          RX packets:7608  TX packets:168
```

All ethernet ports work correctly with the mainline driver:
- Link detection and negotiation
- Full duplex gigabit/10G operation
- Standard Linux networking stack
- VLANs, bridging, routing, NAT, firewall

### What the SDK Patches ADD (Hardware Acceleration)

The NXP ASK patches enable **offloading** work from the CPU to dedicated hardware engines:

| Feature | Without SDK | With SDK (ASK) |
|---------|-------------|----------------|
| Ethernet TX/RX | CPU handles all packets | CPU handles all packets |
| IPsec encrypt/decrypt | CPU (software crypto) | SEC engine (hardware crypto) |
| Known flow forwarding | CPU processes each packet | FMan forwards in hardware |
| Connection tracking | CPU per-packet lookup | Hardware flow cache |
| QoS marking | CPU applies marks | Hardware applies marks |
| Throughput ceiling | ~2-3 Gbps (CPU bound) | ~10+ Gbps (line rate) |
| CPU usage under load | High | Low |

### When You Need the SDK Patches

- **High-throughput routing** (multi-gigabit WAN)
- **IPsec VPN at line rate** (hardware crypto offload)
- **Low-latency forwarding** (bypass kernel stack)
- **Power efficiency** (CPU can idle while hardware forwards)

### When Mainline is Sufficient

- **Development/testing** with moderate traffic
- **Simple routing** under ~1-2 Gbps
- **Easier kernel updates** and security patches
- **Broader community support**

---

## Upgrade Assessment: Moving to Latest Stable Kernel

### Current State
- Base: NXP fork of Linux 6.12.49 (`nxp-qoriq/linux`)
- This is NOT mainline Linux - it's NXP's vendor kernel with their out-of-tree drivers

### Feasibility Analysis

#### Patch 1 (INA234): Easy to Port
- Self-contained hwmon driver change
- Clean implementation following existing patterns
- **May already be upstream** - worth checking mainline status
- If not upstream, would apply with minor fuzz adjustments

#### Patch 2 (ASK): Major Challenge
This patch cannot be directly applied to mainline Linux because:

1. **Depends on NXP out-of-tree drivers:**
   - `sdk_dpaa` - SDK version of DPAA ethernet driver
   - `sdk_fman` - SDK version of Frame Manager driver
   - `fsl_qbman` staging driver modifications
   - These drivers are NOT in mainline Linux

2. **Touches core kernel subsystems:**
   - `sk_buff` structure (ABI concerns)
   - `net_device` structure (ABI concerns)
   - `nf_conn` structure (netfilter)
   - `xfrm_state` structure (IPsec)
   - Bridge layer core files

3. **Adds new Kconfig options:**
   - `CONFIG_CPE_FAST_PATH`
   - `CONFIG_INET_IPSEC_OFFLOAD`
   - `CONFIG_INET6_IPSEC_OFFLOAD`
   - `CONFIG_CPE_4RD_TUNNEL`
   - `CONFIG_COMCERTO_TCP_DELACK_MIN`

4. **Would require:**
   - First porting NXP's SDK drivers to the new kernel version
   - Updating for any API changes in networking core
   - Resolving conflicts with mainline netfilter changes
   - Testing all hardware offload paths

#### Patch 3 (Interface Order): Depends on Patch 2
- Only relevant with the SDK DPAA driver
- Cannot be used without the NXP driver infrastructure

### Recommended Approach

**Option A: Stay on NXP Fork (Recommended)**
1. Wait for NXP to release updated SDK based on newer kernel
2. Re-port the small custom modifications (INA234, interface ordering)
3. Benefit from NXP's testing and validation

**Option B: Attempt Mainline Port (High Effort)**
1. Use mainline's `dpaa` and `fman` drivers instead of SDK versions
2. **Lose hardware acceleration features** - mainline drivers don't support:
   - IPsec offload to SEC engine
   - Fast path packet forwarding
   - QoS marking offload
   - WiFi offload integration
3. Only keep INA234 patch
4. Rewrite interface ordering for mainline `dpaa_eth` driver if needed

**Option C: Hybrid Approach**
1. Start with newer NXP kernel release (if available)
2. Backport security fixes from mainline
3. Maintain custom patches with each NXP update

### Kernel Version Considerations

| Aspect | NXP Fork (Current) | Mainline |
|--------|-------------------|----------|
| Hardware accel | Full support | Limited/None |
| Security updates | Delayed | Immediate |
| Community support | NXP only | Broad |
| Maintenance burden | Medium | High |
| Feature parity | Full | Partial |

---

## Performance Analysis: Mainline Driver on LS1046A

This section documents expected performance when running the **mainline `fsl_dpaa` driver** (without NXP SDK patches) on the Mono Gateway hardware.

### Hardware Specifications

| Component | Specification |
|-----------|--------------|
| CPU | 4x Cortex-A72 @ 1.8 GHz |
| RAM | 8 GB DDR4 ECC |
| Crypto | ARMv8 extensions (AES, PMULL, SHA1, SHA2) |
| Ethernet | 3x 1GbE + 2x 10GbE SFP+ via FMan |
| Architecture | Per-CPU QMan/BMan portals |

### Throughput Expectations

The CPU must process every packet in software without hardware fast path:

| Packet Size | Packets/sec @ 10 Gbps | CPU cycles @ 1.8 GHz/pkt | Realistic Throughput |
|-------------|----------------------|--------------------------|---------------------|
| 64 bytes | 14.88 Mpps | ~120 cycles | 1-2 Gbps |
| 512 bytes | 2.35 Mpps | ~765 cycles | 3-5 Gbps |
| 1500 bytes | 812 Kpps | ~2,200 cycles | 5-8 Gbps |

| Scenario | Expected Throughput |
|----------|---------------------|
| Large packets (1500 MTU), simple routing | 5-8 Gbps |
| Mixed traffic, NAT + firewall | 2-4 Gbps |
| Small packets (64-byte stress test) | 1-2 Gbps |
| IPsec (ARMv8 crypto, CPU-based) | 1-3 Gbps |

**Conclusion:** Line-rate 10GbE is not achievable with software routing. Multi-gigabit (5-8 Gbps with large packets) is realistic.

### Mainline fsl_dpaa Driver Capabilities

Research into the mainline `fsl_dpaa` driver reveals the following capabilities:

#### XDP Support: YES

The mainline driver **fully supports XDP** (eXpress Data Path):

- Declared capabilities: `NETDEV_XDP_ACT_BASIC`, `NETDEV_XDP_ACT_REDIRECT`, `NETDEV_XDP_ACT_NDO_XMIT`
- Proper XDP RX queue registration via `xdp_rxq_info_reg()`
- 256-byte aligned frame headroom for XDP access (due to FMan erratum A050385 workaround)

XDP can bypass the kernel networking stack for simple forwarding decisions, potentially improving throughput for specific use cases.

```bash
# Check XDP support
ethtool -i eth0 | grep -i xdp

# Load XDP program
ip link set eth0 xdp obj xdp_prog.o sec xdp
```

#### IRQ Affinity: LIMITED

**QMan portal bindings are hardcoded at initialization.** This is a hardware architecture constraint:

- Each CPU has a dedicated QMan portal (hardware queue manager)
- Portal-to-CPU mapping is established at boot, not runtime configurable
- Standard `/proc/irq/*/smp_affinity` changes are **not effective** for QMan portal interrupts
- Newer kernels support `qportals=` and `bportals=` boot arguments for static configuration

**Workaround options:**
- Configure portal exclusion at boot time (prevent specific CPUs from owning portals)
- Use `isolcpus` for non-networking workloads, but networking interrupts stay on their assigned cores
- RSS provides implicit multi-core distribution

#### Available Tuning Options

| Feature | Support | Details |
|---------|---------|---------|
| **NAPI** | Yes | Per-CPU NAPI instances, `dpaa_eth_poll()` |
| **RSS** | Yes | 128 RX queues, round-robin distribution |
| **Traffic Classes** | Yes | 4 priority levels via `mqprio` qdisc |
| **Checksum Offload** | Yes | RX/TX for TCP/UDP (always enabled) |
| **IRQ Coalescing** | Limited | No explicit ethtool parameters documented |
| **XDP** | Yes | Full support including redirect |

#### Tuning Commands

```bash
# RSS configuration
ethtool -N eth0 rx-flow-hash tcp4 sdfn    # Enable RSS for TCP
ethtool -K eth0 rx-hashing on              # Enable hash reporting

# Traffic classes (4 priority levels)
tc qdisc add dev eth0 root handle 1: \
  mqprio num_tc 4 map 0 0 0 0 1 1 1 1 2 2 2 2 3 3 3 3 hw 1

# NAPI busy polling (reduce latency)
echo 50 > /sys/class/net/eth0/napi_defer_hard_irqs
echo 200000 > /sys/class/net/eth0/gro_flush_timeout

# Check RX queue distribution
cat /sys/class/net/eth0/queues/rx-*/rps_cpus
```

#### CPU Isolation Strategy

Given the QMan portal architecture, the recommended approach is:

```bash
# Boot parameters (in extlinux.conf or kernel cmdline)
# Do NOT isolate cores 0-3 from networking - they own the QMan portals
# Instead, pin non-networking tasks away from networking cores

# Example: Use CPU0-1 for networking, CPU2-3 for applications
taskset -c 2,3 <application>

# Or use cgroups for workload isolation
echo "2-3" > /sys/fs/cgroup/cpuset/apps/cpuset.cpus
```

**Important:** Unlike traditional NICs where you can move interrupts to isolated cores, the DPAA architecture binds each portal to a specific CPU. You work *with* this architecture, not against it.

### Comparison: Mainline vs SDK Driver

| Capability | Mainline `fsl_dpaa` | SDK `sdk_dpaa` |
|------------|---------------------|----------------|
| Basic ethernet | Yes | Yes |
| XDP | Yes | Unknown |
| Hardware fast path | No | Yes |
| IPsec to SEC engine | No | Yes |
| IRQ affinity | Fixed portals | Fixed portals |
| RSS | Yes (128 queues) | Yes |
| Line-rate 10GbE | No | Yes (fast path) |
| Kernel version flexibility | High | Low (NXP fork only) |

---

## Summary

The Mono Gateway kernel is heavily customized for NXP Layerscape hardware acceleration. The ASK patch alone is ~23,000 lines touching 100+ files across networking, crypto, and driver subsystems.

**Key takeaway:** Basic ethernet works fine with mainline Linux (as demonstrated by OpenWrt). The NXP SDK patches add hardware acceleration for high-performance scenarios—they're not required for the network interfaces to function.

**Decision framework:**
- Need 10G line-rate IPsec or multi-gigabit routing? → Use NXP SDK kernel with patches
- Just need working ethernet for development/testing? → Mainline kernel works fine
- Want easier security updates? → Consider mainline with acceptance of lower throughput ceiling
- Want XDP for programmable fast path? → Mainline driver supports it

**Performance reality check:** The mainline `fsl_dpaa` driver supports XDP and can achieve 5-8 Gbps with large packets, but QMan portal IRQ affinity is hardware-fixed at boot. Traditional interrupt pinning strategies don't apply—work with the per-CPU portal architecture instead.

The recommended production path is to track NXP's kernel releases and maintain minimal custom patches (INA234 support and any board-specific fixes).
