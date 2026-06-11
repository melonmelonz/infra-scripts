#!/bin/bash
# host-phase2.sh — run ON the Proxmox host, as root, AFTER host-bootstrap.sh.
#   curl -fsSL https://raw.githubusercontent.com/melonmelonz/infra-scripts/main/scripts/host-phase2.sh | bash
# Fixes the Proxmox apt repos (enterprise -> no-subscription) and installs
# Tailscale so Penn can reach the server remotely. Safe to run repeatedly.
# After this, the person at the server is DONE.
set -u

fail() {
  echo
  echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
  echo "!!! PROBLEM: $1"
  echo '!!! Photo this WHOLE screen and send it to Penn.'
  echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
  exit 1
}

main() {
  export DEBIAN_FRONTEND=noninteractive

  [ "$(id -u)" = "0" ] || fail "not running as root — log in as root and rerun"

  # --- 0. Sanity: internet + DNS ---------------------------------------
  if ! curl -fsS --max-time 15 -o /dev/null https://pkgs.tailscale.com; then
    ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1 \
      && fail "internet works but DNS does not — check ether1 cable / home router" \
      || fail "no internet — check the cable from MikroTik ether1 to the home router"
  fi

  # --- 1. Fix Proxmox repos (enterprise needs a paid subscription) ------
  # Disable every enterprise repo file (deb822 .sources and legacy .list).
  for f in /etc/apt/sources.list.d/pve-enterprise.sources \
           /etc/apt/sources.list.d/pve-enterprise.list \
           /etc/apt/sources.list.d/ceph.sources \
           /etc/apt/sources.list.d/ceph.list; do
    if [ -f "$f" ] && grep -q 'enterprise.proxmox.com' "$f" 2>/dev/null; then
      mv "$f" "$f.disabled"
      echo "Disabled paid repo: $f"
    fi
  done
  # Catch any other file still pointing at the enterprise server.
  grep -rl 'enterprise.proxmox.com' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null \
    | grep -v '\.disabled$' | while read -r f; do
        sed -i -e 's|^\(deb .*enterprise.proxmox.com\)|# \1|' \
               -e 's|^\(URIs:.*enterprise.proxmox.com.*\)|\1\nEnabled: no|' "$f"
        echo "Disabled enterprise repo entries in: $f"
      done

  # Add the free no-subscription repo (idempotent).
  . /etc/os-release
  CODENAME="${VERSION_CODENAME:-trixie}"
  if [ ! -f /etc/apt/sources.list.d/pve-no-subscription.sources ]; then
    cat > /etc/apt/sources.list.d/pve-no-subscription.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: ${CODENAME}
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    echo "Added free Proxmox repo (pve-no-subscription)."
  fi

  # --- 2. Install Tailscale --------------------------------------------
  if command -v tailscale >/dev/null 2>&1; then
    echo "Tailscale already installed, skipping install."
  else
    echo "Installing Tailscale (takes a minute or two)..."
    curl -fsSL "https://pkgs.tailscale.com/stable/debian/${CODENAME}.noarmor.gpg" \
      -o /usr/share/keyrings/tailscale-archive-keyring.gpg \
      || fail "could not download the Tailscale signing key"
    curl -fsSL "https://pkgs.tailscale.com/stable/debian/${CODENAME}.tailscale-keyring.list" \
      -o /etc/apt/sources.list.d/tailscale.list \
      || fail "could not download the Tailscale repo list"
    # Don't abort on update warnings; install is the real test.
    apt-get update </dev/null || echo "(some repo warnings above — continuing)"
    apt-get install -y tailscale </dev/null \
      || fail "apt could not install tailscale"
  fi

  command -v tailscale >/dev/null 2>&1 || fail "tailscale still missing after install"

  systemctl enable --now tailscaled || fail "could not start the tailscaled service"
  # Give the daemon a moment to come up.
  for i in 1 2 3 4 5 6 7 8 9 10; do
    tailscale status >/dev/null 2>&1 && break
    [ "$(tailscale status 2>&1 | grep -c 'Logged out\|NeedsLogin\|stopped')" -gt 0 ] && break
    sleep 1
  done

  # --- 3. Connect (or confirm we already are) ---------------------------
  if IP=$(tailscale ip -4 2>/dev/null) && [ -n "$IP" ]; then
    echo
    echo "Already connected to Tailscale."
  else
    echo
    echo "============================================================"
    echo "  A LOGIN LINK (https://login.tailscale.com/...) WILL"
    echo "  APPEAR BELOW. Send a photo of it to Penn, then WAIT"
    echo "  here — do NOT press anything or turn anything off."
    echo "  When Penn clicks the link, this finishes by itself."
    echo "============================================================"
    echo
    tailscale up --accept-dns=false \
      || fail "tailscale could not connect — try running this script again"
    IP=$(tailscale ip -4 2>/dev/null)
  fi

  echo
  echo '=== TAILSCALE IP (photo this too) ==='
  echo "${IP:-$(tailscale ip -4)}"
  echo '=== PHASE 2 DONE — you are finished! ==='
}

main
