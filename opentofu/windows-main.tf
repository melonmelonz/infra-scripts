# windows-main (VM 100) — friend's daily driver: Trion/point-cloud work +
# gaming, RTX 5080 passthrough, streamed to the mini PC via Sunshine/Moonlight.
#
# Install media (3 CD-ROMs: win11, virtio-win, UNATTEND) is attached with
# `qm set` during provisioning and detached afterwards — ephemeral media is
# deliberately NOT part of the desired state (see ignore_changes).
#
# The system disk starts on sata0 so the unattended install needs no storage
# driver; it is flipped to virtio-scsi after the virtio drivers are in.
# The GPU hostpci entry is likewise added post-install.

resource "proxmox_virtual_environment_vm" "windows_main" {
  name      = "windows-main"
  node_name = var.pve_node
  vm_id     = 100

  machine = "q35"
  bios    = "ovmf"
  on_boot = true
  started = false # started/stopped manually during provisioning

  cpu {
    cores   = 16
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 131072 # 128 GiB — locked once the GPU is attached anyway
  }

  efi_disk {
    datastore_id      = "local-zfs"
    type              = "4m"
    pre_enrolled_keys = true
  }

  tpm_state {
    datastore_id = "local-zfs"
    version      = "v2.0"
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = "local-zfs"
    interface    = "sata0"
    size         = 512
    discard      = "on"
    file_format  = "raw"
  }

  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = 30 # gaming/streaming VLAN — same L2 as the Moonlight mini PC
  }

  operating_system {
    type = "win11"
  }

  agent {
    enabled = true
    timeout = "5m"
  }

  lifecycle {
    ignore_changes = [cdrom, started, hostpci, disk]
  }
}
