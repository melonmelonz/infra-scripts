# infra-scripts

IaC for the point-cloud / multi-tenant Proxmox host.
See spec: docs/superpowers/specs/2026-06-08-pointcloud-main-provisioning-design.md

- `ansible/` — Proxmox HOST config (VFIO, ZFS, NUT, Tailscale).
- `opentofu/` — VM lifecycle (bpg/proxmox). Filled after host bring-up.

## Build-day discovery (fill these before applying)
- GPU + audio PCI IDs:   `lspci -nn | grep -iE 'nvidia|audio'`
- Disk by-id for ZFS:    `ls -l /dev/disk/by-id/`
- NIC name:              `ip -br link`
Put values in `ansible/group_vars/all.yml` and `opentofu/terraform.tfvars`.
