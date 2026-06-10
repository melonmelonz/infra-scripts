# Recovery & Resilience

How this box survives power loss, disk failure, and a hung host — and how to get
data back. This is a remote, mostly-unattended machine, so out-of-band access and
graceful shutdown are not optional.

## Out-of-band access (when the OS is unreachable)

- **BMC/IPMI (ASPEED AST2600)** gives a remote KVM + power control independent of
  the host OS and the discrete GPUs. It is the lifeline if GPU passthrough
  blackholes the console or a boot goes wrong.
- IPMI is on **VLAN10 (mgmt)** and reachable over **Tailscale**, so Penn can power-
  cycle or watch POST remotely without a port-forward.
- If a VM reboot wedges a GPU (rare; NVIDIA usually FLR-resets fine), a **host
  reboot** clears it — recoverable via IPMI.

## Power loss — UPS + NUT

- The host runs **NUT** (`usbhid-ups`) against the **APC SMT1500C** over USB.
- On low battery, `upsmon` runs `SHUTDOWNCMD "/sbin/poweroff"` → Proxmox shuts down
  the VMs and host **gracefully**. This is shutdown headroom, **not** ride-through:
  the 1000 W UPS is sized to land safely, not to keep dual-GPU + 24-core running.
- Verify after setup: `upsc apc` shows `battery.charge` / `ups.status`, and a
  simulated power-loss test actually triggers shutdown. (`verify-passthrough.sh`
  checks the UPS link.)
- Note: locked-RAM VMs (Windows-main, Services) take longer to flush — keep the
  shutdown timers generous enough to power them down cleanly.

## Disk failure — ZFS

- **Root + authoritative data** live on the **2×2 TB Gen5 ZFS mirror** — survives
  one drive death. The friend's real Trion projects and point clouds belong here,
  **never** on scratch.
- The **4 TB Gen4 M.2 is scratch** (point-cloud working set): no redundancy,
  transient only. Losing it loses nothing authoritative.
- Replace a failed mirror drive:
  ```bash
  zpool status                              # identify the DEGRADED disk
  zpool replace rpool <old-id> <new-id>     # by /dev/disk/by-id
  zpool status                              # watch resilver to completion
  ```
- Run periodic scrubs (Proxmox installs a monthly scrub timer by default):
  ```bash
  zpool scrub rpool
  zpool status rpool
  ```
- ARC is capped (~8 GB) so it never starves the locked/ballooning VM RAM.

## Backups — 3-2-1

- **Primary:** Proxmox Backup Server on the **64 GB / 3×16 TB RAIDZ1** box, kept on
  the **local LAN** so the initial/bulk backup runs at local/10G speed. A full
  120 GB `zfs send` over the 50 Mbps uplink is ~5.5 h — impractical, so bulk stays
  local.
- **Offsite:** physical **cold-drive rotation** — `zfs send | zstd` to a bare drive
  via USB dock, stored offsite. Only **small incrementals** should ever cross the
  WAN.
- Restore drill: periodically restore one VM from PBS to confirm the chain works
  before you need it for real.

## What "Windows not running" means (for Big-Linux reclaim)

The Linux compile VM only gets RAM back when Windows-main is **powered off**, not
idle/asleep and not when the friend closes Moonlight. To reclaim safely:
1. Over SSH/IPMI, confirm no active Sunshine session.
2. `qm shutdown <winvm>` (graceful).
3. Run the big job — Linux balloons up automatically.
4. `qm start <winvm>` to restore the friend's machine before he needs it.

## Quick reference

| Symptom | First move |
|---------|-----------|
| Host unreachable over SSH/Tailscale | IPMI remote KVM (mgmt VLAN / Tailscale) |
| VM won't start, GPU "in use" | Host reboot via IPMI clears a wedged GPU |
| Drive DEGRADED in `zpool status` | `zpool replace` by-id, watch resilver |
| Power blip | NUT handles it; check `upsc apc` afterwards |
| Lost scratch disk | Nothing authoritative there — recreate working set |
| Need a file back | Restore from PBS (LAN) or the offsite cold drive |
