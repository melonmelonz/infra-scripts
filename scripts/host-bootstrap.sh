#!/bin/bash
# host-bootstrap.sh — run ON the Proxmox host, as root, AFTER network is up.
#   curl -fsSL https://raw.githubusercontent.com/melonmelonz/infra-scripts/main/scripts/host-bootstrap.sh | bash
# Installs Penn's SSH key and prints the hardware discovery report.
set -u

mkdir -p /root/.ssh && chmod 700 /root/.ssh
KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA6znTfAPIcKX9TYD2UQBWQqJL1paLev6gSzKGB/IoRV lushfund@protonmail.ch'
grep -qF "$KEY" /root/.ssh/authorized_keys 2>/dev/null || echo "$KEY" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
echo "SSH key installed."

# Fix /etc/hosts to match the new mgmt IP (pveproxy needs this)
H=$(hostname)
sed -i "s/^[0-9][0-9.]*\([[:space:]].*$H\)/10.10.10.10\1/" /etc/hosts
echo "/etc/hosts updated:"
grep "$H" /etc/hosts

echo '=== IP ==='
ip -4 addr show vmbr0 | grep inet
echo '=== GPUs ==='
lspci -nn -d 10de:
echo '=== IOMMU ==='
dmesg | grep -iE 'iommu|amd-vi' | head -5
echo '=== DISKS ==='
ls -l /dev/disk/by-id/ | grep -v part
echo '=== BOOTSTRAP DONE — tell Penn ==='
