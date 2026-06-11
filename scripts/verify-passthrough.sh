#!/usr/bin/env bash
#
# verify-passthrough.sh — build-day sanity check for the Proxmox host.
#
# Run this ON THE PROXMOX HOST after `ansible-playbook site.yml` and a reboot,
# BEFORE you trust GPU passthrough or hand the box to anyone. It asserts the
# things that silently break a passthrough host:
#   - IOMMU is actually on and groups exist
#   - every NVIDIA GPU + its HDMI-audio function is bound to vfio-pci
#     (NOT nouveau/nvidia/snd_hda_intel)
#   - the ZFS ARC cap is applied
#   - NUT can talk to the UPS
#   - Tailscale is up
#
# Usage:
#   ./verify-passthrough.sh                 # expects ARC cap = 8 GiB
#   EXPECTED_ARC_BYTES=8589934592 ./verify-passthrough.sh
#
# Exit code is non-zero if ANY check fails.

set -u

EXPECTED_ARC_BYTES="${EXPECTED_ARC_BYTES:-8589934592}"

pass=0
fail=0

green() { printf '\033[32m  PASS\033[0m  %s\n' "$1"; pass=$((pass + 1)); }
red()   { printf '\033[31m  FAIL\033[0m  %s\n' "$1"; fail=$((fail + 1)); }
info()  { printf '\033[36m  ....\033[0m  %s\n' "$1"; }
hdr()   { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

# --- 1. IOMMU enabled and groups present -----------------------------------
hdr "IOMMU"
if dmesg 2>/dev/null | grep -qiE 'AMD-Vi|iommu.*enabled|DMAR.*enabled'; then
  green "IOMMU initialised (dmesg)"
else
  red "no IOMMU init line in dmesg (check amd_iommu=on iommu=pt + BIOS AMD-Vi)"
fi

group_count=$(find /sys/kernel/iommu_groups/ -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
if [ "$group_count" -gt 0 ]; then
  green "IOMMU groups present ($group_count groups)"
else
  red "no /sys/kernel/iommu_groups — IOMMU is OFF"
fi

# --- 2. Every NVIDIA function bound to vfio-pci -----------------------------
hdr "VFIO binding (all NVIDIA GPU + audio functions)"
# -d 10de: matches all NVIDIA-vendor devices (both the GPU and its audio fn).
nvidia_addrs=$(lspci -D -d 10de: 2>/dev/null | awk '{print $1}')
if [ -z "$nvidia_addrs" ]; then
  red "no NVIDIA devices found by lspci (-d 10de:) — cards not enumerated"
else
  for addr in $nvidia_addrs; do
    drv=$(lspci -nnks "$addr" 2>/dev/null | sed -n 's/.*Kernel driver in use: //p')
    name=$(lspci -nns "$addr" 2>/dev/null | sed "s/^$addr //")
    if [ "$drv" = "vfio-pci" ]; then
      green "$addr vfio-pci  [$name]"
    else
      red "$addr driver='${drv:-<none>}' (want vfio-pci)  [$name]"
    fi
  done
fi

# --- 3. Each NVIDIA function sits in a clean IOMMU group --------------------
# A passthrough GPU should not share an IOMMU group with unrelated devices.
hdr "IOMMU group isolation"
for addr in $nvidia_addrs; do
  grp=$(basename "$(readlink -f "/sys/bus/pci/devices/$addr/iommu_group" 2>/dev/null)" 2>/dev/null)
  if [ -z "$grp" ]; then
    red "$addr has no iommu_group"
    continue
  fi
  members=$(find "/sys/kernel/iommu_groups/$grp/devices" -maxdepth 1 -mindepth 1 2>/dev/null \
              | xargs -n1 basename 2>/dev/null)
  # Acceptable group members: only NVIDIA functions + the PCIe bridge they sit behind.
  dirty=0
  for m in $members; do
    mvendor=$(cat "/sys/bus/pci/devices/$m/vendor" 2>/dev/null)
    mclass=$(cat "/sys/bus/pci/devices/$m/class" 2>/dev/null)
    # 0x10de = NVIDIA; class 0x0604xx = PCI bridge (expected, harmless).
    if [ "$mvendor" = "0x10de" ] || printf '%s' "$mclass" | grep -qi '^0x0604'; then
      continue
    fi
    dirty=1
    info "group $grp also contains foreign device $m (vendor $mvendor class $mclass)"
  done
  if [ "$dirty" -eq 0 ]; then
    green "$addr in clean group $grp"
  else
    red "$addr group $grp shares with foreign devices (ACS/placement issue)"
  fi
done

# --- 4. ZFS ARC cap ---------------------------------------------------------
hdr "ZFS ARC cap"
arc_now=$(cat /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null || echo "")
if [ -z "$arc_now" ]; then
  red "zfs_arc_max not readable (is ZFS loaded?)"
elif [ "$arc_now" = "$EXPECTED_ARC_BYTES" ]; then
  green "zfs_arc_max = $arc_now bytes (matches expected)"
elif [ "$arc_now" = "0" ]; then
  red "zfs_arc_max = 0 (UNCAPPED — ARC can starve VM RAM)"
else
  red "zfs_arc_max = $arc_now bytes (expected $EXPECTED_ARC_BYTES)"
fi

# --- 5. apcupsd talks to the UPS --------------------------------------------
hdr "apcupsd / UPS"
if command -v apcaccess >/dev/null 2>&1; then
  ups_status=$(apcaccess -p STATUS 2>/dev/null | tr -d ' ')
  if [ -n "$ups_status" ]; then
    charge=$(apcaccess -p BCHARGE 2>/dev/null)
    green "UPS reachable (STATUS=$ups_status, BCHARGE=$charge)"
  else
    red "apcaccess returns empty STATUS (enable Modbus on the UPS LCD: Configuration > Modbus > Enabled)"
  fi
else
  red "apcaccess not installed (apcupsd role did not run?)"
fi

# --- 6. Tailscale up --------------------------------------------------------
hdr "Tailscale"
if command -v tailscale >/dev/null 2>&1; then
  if tailscale status >/dev/null 2>&1; then
    green "tailscale is up ($(tailscale ip -4 2>/dev/null | head -n1))"
  else
    red "tailscale installed but not connected (run: tailscale up --authkey ... --ssh)"
  fi
else
  red "tailscale not installed (tailscale role did not run?)"
fi

# --- Summary ----------------------------------------------------------------
hdr "Summary"
printf 'passed: %d   failed: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
