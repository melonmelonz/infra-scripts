# Build-Day Runbook

Order of operations to bring the host up from bare hardware. Mirrors spec §15.
Don't skip the IPMI test in step A — it's your lifeline if passthrough blackholes
the console.

## A. Firmware / BIOS
- Enable **IOMMU / AMD-Vi**, **SR-IOV / ACS** (as available), **Above-4G
  decoding**, **Resizable BAR**.
- Configure the **BMC/IPMI network** and **confirm remote KVM works** before you
  rely on it. Verify IPMI is actually populated on the SE board variant.
- Set sane 24/7 fan curves.

## B. Install Proxmox VE 8.x
- Root on the **ZFS mirror** (2×2 TB Gen5). Leave the 4 TB M.2 as scratch.
- Update packages. (ARC cap is applied by Ansible in step C.)
- Use a current 8.x kernel — the 5080 is Blackwell and needs recent PCIe
  enumeration.

## C. Host prep via Ansible (this repo)
1. **Discovery** — collect the hardware-specific values:
   ```bash
   lspci -nn | grep -iE 'nvidia|audio'   # -> vfio_pci_ids (GPU + audio fn of EACH card)
   ip -br link                            # -> NIC name
   ls -l /dev/disk/by-id/                 # -> disks if needed
   ```
2. Fill `ansible/group_vars/all.yml` (`vfio_pci_ids`) and the host IP in
   `ansible/inventory.ini`.
3. Run the play (pass secrets at runtime, never commit them):
   ```bash
   cd ansible
   ansible-playbook site.yml \
     -e "tailscale_authkey=tskey-XXXX nut_monitor_password=SOMETHING"
   ```
   This sets the kernel cmdline via **`proxmox-boot-tool`** (ZFS root uses
   systemd-boot, not grub), binds vfio-pci, blacklists the GPU drivers, caps ARC,
   installs NUT, and brings up Tailscale.
4. **Reboot.**
5. **Verify** (run on the host):
   ```bash
   ./scripts/verify-passthrough.sh
   ```
   Every GPU + audio function must show `vfio-pci`, each in a clean IOMMU group,
   ARC capped, NUT talking to the UPS, Tailscale up. Do not proceed until green.

## D. Networking
- See `network-topology.md`: bring up the MikroTik VLANs/firewall, wire the host
  10G into the SFP+ trunk, make `vmbr0` VLAN-aware.
- Confirm Tailscale reach (including IPMI over Tailscale).

## E. VMs (OpenTofu once host is sane; a manual first pass is fine)
- **Windows-main:** 5080 (+audio) passthrough, ~136-140 GB, **ballooning OFF**,
  virtio disk/net (load virtio drivers during install), ~12-14 cores pinned.
  Install Trion (+ USB license dongle passthrough if needed), enable auto-login,
  install Sunshine, add a dummy HDMI display, pair Moonlight from the mini PC.
- **Services (Linux):** 3080 (+audio) passthrough, ~16 GB; Jellyfin (NVENC) + thin
  DBs. Expose only via Tailscale.
- **DayZ (Windows):** no GPU, ~8 GB, 2-3 cores; SteamCMD server + CF +
  DayZ-Expansion + Deer Isle. Players reach it via Tailscale or the scoped
  WAN dst-nat in `network-topology.md`.
- **Linux compile:** NixOS, no GPU, ballooning ON (16/150), 4-6 cores pinned;
  SSH; pinned RFL toolchain via flake.

## F. Resilience
- Configure NUT against the APC and **test a simulated power-loss shutdown**.
- Stand up Proxmox Backup Server on the RAIDZ1 box; run a first VM backup; seed an
  offsite cold drive. (See `recovery.md`.)

## G. Validation
- **Friend:** full Moonlight session at target res/latency; Trion launches; a real
  point-cloud job runs.
- **Penn:** SSH compile from outside via Tailscale; Jellyfin stream within the
  uplink cap; trigger **Big-Linux mode** once (power Windows off, confirm Linux
  balloons up, then `qm start` Windows).

## Open items to confirm
1. **Trion under virtualization** — does it need a USB license dongle? If so, pass
   the USB device to Windows-main. [HIGH RISK — verify before relying on the VM]
2. IPMI/BMC populated on the SE board.
3. RAIDZ1 backup box is LAN-local (else bulk backup over 50 Mbps up isn't viable).
4. IOMMU groups isolate the 5080 and 3080 cleanly.
5. CXL enablement on the 9965WX + WRX90E firmware (keep a PCIe5 x16 slot free).
6. Both Gen5 NVMe have adequate heatsinking for 24/7.
