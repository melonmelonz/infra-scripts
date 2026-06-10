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

You don't need to know Linux for this. You'll log in, paste one block of
text, and send the output back. ~5 minutes.

### Step 1 — Get a shell on the server

Easiest: plug a monitor + keyboard into the server and log in as
`root` with the password set during install.

Or, from a browser on the same network: go to `https://<server-ip>:8006`
(accept the certificate warning), log in as `root`, click the server name
in the left sidebar (`pve01`), then click **Shell** at the top right.

### Step 2 — Check the network

Paste this and press Enter:

```bash
ip -4 addr show vmbr0; ip route | head -2; ping -c 2 1.1.1.1
```

You want to see two ping replies. **Also note the IP address shown** (the
`inet` line, e.g. `inet 10.0.0.50/24`) — Penn needs it, and it must be on
the same network as his laptop (`10.0.0.x`).

If the IP is on the wrong network (e.g. `192.168.100.x` while everything
else in the house is `10.0.0.x`):

```bash
nano /etc/network/interfaces
```

Find the `iface vmbr0` block and change the `address` line to a free IP on
the right network (e.g. `address 10.0.0.50/24`) and the `gateway` line to
the router (e.g. `gateway 10.0.0.1`). Save with Ctrl+O Enter, exit with
Ctrl+X, then:

```bash
sed -i "s/^\([0-9.]*\)\(\s*pve01\)/10.0.0.50\2/" /etc/hosts
ifreload -a
ping -c 2 1.1.1.1
```

(If you used a different IP than `10.0.0.50`, use that in the `sed` line.)

### Step 3 — Paste the bootstrap block

This adds Penn's SSH key (so he can finish setup remotely) and prints the
hardware info he needs. Paste the WHOLE block at once:

```bash
mkdir -p /root/.ssh && chmod 700 /root/.ssh
echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA6znTfAPIcKX9TYD2UQBWQqJL1paLev6gSzKGB/IoRV lushfund@protonmail.ch' >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
echo '=== IP ==='; ip -4 addr show vmbr0 | grep inet
echo '=== GPUs ==='; lspci -nn -d 10de:
echo '=== IOMMU ==='; dmesg | grep -iE 'iommu|amd-vi' | head -5
echo '=== DISKS ==='; ls -l /dev/disk/by-id/ | grep -v part
echo '=== BOOTSTRAP DONE ==='
```

### Step 4 — Send the output back

Copy everything from `=== IP ===` down and send it to Penn (a photo of the
screen is fine). That's it — everything else happens remotely.

If `=== IOMMU ===` printed nothing: reboot into BIOS and check that
**SVM** and **IOMMU** are Enabled (Advanced > CPU / AMD CBS), then redo
Step 3.

---

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
