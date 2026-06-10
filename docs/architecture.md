# Architecture — Point-Cloud / Multi-Tenant Proxmox Host

A single Threadripper PRO box runs Proxmox VE and serves four workloads at once.
Full design rationale: `docs/superpowers/specs/2026-06-08-pointcloud-main-provisioning-design.md`.

## Hardware (as built)

- **CPU:** AMD Threadripper PRO 9965WX, 24c/48t, sTR5 / WRX90
- **Board:** ASUS Pro WS WRX90E-SAGE SE (8-channel ECC, 128 PCIe5 lanes, 10GbE,
  ASPEED AST2600 BMC w/ onboard VGA + IPMI)
- **RAM:** 192 GB = 8×24 GB DDR5-6000 ECC RDIMM
- **GPUs:** RTX 5080 16 GB → Windows-main VM · RTX 3080 10 GB → Services VM
- **Storage:** 2×2 TB Samsung 9100 PRO PCIe5 (ZFS mirror) + 1×4 TB Gen4 M.2 (scratch)
- **PSU / cooling / case:** Corsair HX1500i · Noctua NH-U14S TR5-SP6 · Corsair 9000D
- **UPS:** APC Smart-UPS SMT1500C (1500 VA / 1000 W)
- **Edge:** MikroTik RB5009UPr+S+IN (see `network-topology.md`)
- **Backup box (separate):** recased workstation, 64 GB, 3×16 TB RAIDZ1, RTX 5070 Ti

## The four VMs

```
Proxmox VE host (9965WX / 192GB / 5080 + 3080)
 |
 |-- Windows-main  5080 passthrough · Trion + point cloud + gaming · Sunshine host
 |                 ~136-140GB LOCKED · ballooning OFF · ~12-14 cores (float)
 |
 |-- Linux compile NixOS · NO GPU · ballooning ON (16 floor / 150 max)
 |                 4-6 cores pinned · Penn's remote SSH kernel-build box
 |
 |-- Services      3080 passthrough (NVENC) · Linux · ~16GB · 2 cores · Jellyfin + thin DBs
 |
 |-- DayZ          Windows · no GPU · ~8GB · 2-3 cores · Deer Isle + Expansion
 |
 |-- Host          BMC/IPMI console (no GPU consumed) · ~2 cores · ZFS ARC capped ~8GB
```

## Resource model

**CPU (24c/48t)** — pin at core granularity, keep SMT siblings inside one VM,
keep each VM's cores contiguous within a CCD:
- Host ~2 · Linux compile 4-6 (pinned) · Services ~2 · DayZ 2-3 · Windows-main
  the remaining ~12-14, allowed to float onto idle cores via CPU shares.

**RAM (192 GB)** — budgeted for all four VMs:
- Host + ZFS ARC ~10 GB (`zfs_arc_max` ~8 GB so ARC never fights the VMs)
- Windows-main ~136-140 GB, **locked** (passthrough needs locked RAM)
- Services ~16 GB (locked — 3080 passed through)
- DayZ ~8 GB
- Linux compile: balloon 16 → 150 GB
- All four running ≈ 188 GB committed, ~4 GB slack.

## The key constraint: locked RAM until power-off

GPU passthrough pins the VM's RAM for DMA, so it **cannot balloon**. Windows-main's
~138 GB is only returned to the pool when that VM is **powered off** — NOT when:
- the friend closes Moonlight or powers off his mini PC (VM still runs), or
- Windows is idle/asleep (still running, still locked).

So the Linux compile VM only grows past its ~16-24 GB floor when Penn explicitly
powers Windows off. Hugepages are therefore **on-demand, not boot-reserved** —
boot-reserving them would permanently fence that RAM and defeat the reclaim.

## Two operating modes

- **Co-resident (default):** Windows up 24/7, Linux at floor. Covers most kernel
  builds (`-j` parallelism is CPU-bound, not RAM-bound).
- **Big-Linux (occasional):** Penn powers Windows off remotely; Linux balloons to
  ~150 GB for huge tmpfs builds / CXL research. Restore with `qm start`.

## GPU passthrough

- IOMMU on; blacklist nouveau/nvidia on the host; bind vfio-pci **by device-ID**
  (5080 and 3080 differ, so binding is unambiguous). Pass **both functions**
  (GPU + HDMI-audio) of each card.
- Host console via BMC/IPMI VGA → no discrete GPU consumed by the host.
- Verify each card sits in a **clean IOMMU group** before trusting passthrough
  (`scripts/verify-passthrough.sh`).

## Access paths

- **Friend (gaming):** Sunshine on Windows-main (5080 NVENC) → Moonlight on the
  in-room mini PC, wired, same VLAN (sub-ms). See `network-topology.md`.
- **Penn (remote):** Tailscale → SSH/mosh to the Linux compile VM; IPMI over
  Tailscale for out-of-band recovery; Jellyfin bitrate-capped to the 50 Mbps up.

## IaC layout

- `ansible/` — host config OpenTofu can't manage: VFIO binding, ZFS ARC, NUT,
  Tailscale. Run `ansible-playbook site.yml`.
- `opentofu/` — VM lifecycle via `bpg/proxmox` (definitions added after host
  bring-up). State + `*.tfvars` are gitignored (secrets).
