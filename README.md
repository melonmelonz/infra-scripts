# infra-scripts

IaC for the point-cloud / multi-tenant Proxmox host.

- `ansible/` — Proxmox HOST config (VFIO passthrough, ZFS tuning, NUT/UPS, Tailscale).
- `opentofu/` — VM lifecycle (bpg/proxmox). Filled after host bring-up.
- `docs/` — architecture, network topology, build-day runbook, recovery, printable build guide.
- `scripts/verify-passthrough.sh` — run ON the host after Ansible to confirm everything took.

Current state: **Proxmox VE 9.2 is installed on the server.** Next step is the
bootstrap below, then the Ansible playbook runs from Penn's laptop.

---

## Bootstrap walkthrough (for the person at the server)

You don't need to know Linux. You'll plug in two cables, log in, type
five short lines, and send a photo of the output back. ~10 minutes.

Network is already set up: the MikroTik router has VLANs configured and
the server gets the management network (10.10.10.x) on its port.

### Step 0 — Cables

1. Server's 10G network port -> MikroTik port **ether8**
   (the server has TWO identical 10G ports — if Step 2 fails, try the other one)
2. Home router LAN port -> MikroTik port **ether1** (this is the internet feed)

### Step 1 — Log in

Plug a monitor + keyboard into the server. Log in as `root` with the
password set during install.

### Step 2 — Fix the network (type these, Enter after each)

Type carefully — straight quotes, exact spacing inside the quotes:

```bash
sed -i 's|address .*|address 10.10.10.10/24|; s|gateway .*|gateway 10.10.10.1|' /etc/network/interfaces
sed -i '/bridge-fd/a\ bridge-vlan-aware yes\n bridge-vids 2-4094' /etc/network/interfaces
ifreload -a
ping -c 2 10.10.10.1 && ping -c 2 1.1.1.1
```

You want to see replies from BOTH pings:
- `10.10.10.1` replying = server can reach the router. If not: check the
  ether8 cable, or try the server's other 10G port.
- `1.1.1.1` replying = internet works. If not: check the ether1 cable.

### Step 3 — Run the bootstrap (one line)

```bash
curl -fsSL https://raw.githubusercontent.com/melonmelonz/infra-scripts/main/scripts/host-bootstrap.sh | bash
```

This installs Penn's SSH key and prints a hardware report ending in
`BOOTSTRAP DONE`.

### Step 4 — Send the output back

Photo of everything from `=== IP ===` down.

If `=== IOMMU ===` printed nothing: reboot into BIOS, check **SVM** and
**IOMMU** are Enabled (Advanced > CPU / AMD CBS), then redo Step 3.

### Step 5 — Remote access (one more line, then you're done)

```bash
curl -fsSL https://raw.githubusercontent.com/melonmelonz/infra-scripts/main/scripts/host-phase2.sh | bash
```

It prints a **login link** (`https://login.tailscale.com/...`). Send a
photo of the link to Penn and **wait** — when he clicks it, the script
finishes on its own and prints `PHASE 2 DONE`. Photo that final output
too. That's everything — you can walk away from the server.

## Reinstall as ZFS RAID1 (decided 2026-06-11)

The first install landed on LVM/one drive. We want mirrored ZFS across both
2TB NVMes so a dead drive never needs a site visit. For the person at the
server:

1. Plug the Proxmox USB stick back in. Type `reboot`, then tap **F8**
   while it restarts and pick the USB stick from the boot menu.
2. Choose **Install Proxmox VE (Graphical)**. Click **Agree**.
3. On the *Target Harddisk* screen click **Options**:
   - Filesystem: **zfs (RAID1)**
   - Harddisk 0 and Harddisk 1 must both say **Samsung ... 9100 PRO** (the
     two 1.8T drives). Any other slot: **— do not use —**. Click OK, Next.
4. Country/keyboard: whatever's right. Password: **same one as before**.
   Email: anything.
5. *Management Network* screen:
   - Interface: same network card as last time (the cabled 10G port)
   - Hostname: `sietch.mdtek.com`
   - IP: `10.10.10.10/24`  Gateway: `10.10.10.1`  DNS: `10.10.10.1`
6. Install. When it reboots, pull the USB stick out.
7. Log back in as root and redo **Step 2, Step 3, and Step 5** above
   (same lines — they're safe to repeat). Photo the outputs as before.

## After bootstrap (from the control machine)

1. Put the server IP in `ansible/inventory.ini` (replace `REPLACE_WITH_HOST_IP`).
2. Put the GPU PCI IDs (the `[10de:xxxx]` values from `=== GPUs ===`, GPU
   **and** its audio function) in `vfio_pci_ids` in `ansible/group_vars/all.yml`.
3. Run the playbook:
   ```bash
   cd ansible && ansible-playbook site.yml
   ```
4. Reboot the host, then on the host run:
   ```bash
   scripts/verify-passthrough.sh
   ```
   All checks must PASS before building the Windows VM.

## Build-day discovery reference

- GPU + audio PCI IDs:   `lspci -nn | grep -iE 'nvidia|audio'`
- Disk by-id for ZFS:    `ls -l /dev/disk/by-id/`
- NIC name:              `ip -br link`

Put values in `ansible/group_vars/all.yml` and `opentofu/terraform.tfvars`.
