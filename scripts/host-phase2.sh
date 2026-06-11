#!/bin/bash
# host-phase2.sh — run ON the Proxmox host, as root, AFTER host-bootstrap.sh.
#   curl -fsSL https://raw.githubusercontent.com/melonmelonz/infra-scripts/main/scripts/host-phase2.sh | bash
# Installs Tailscale so Penn can reach the server remotely. After this, the
# person at the server is DONE — everything else happens over the network.
set -u

if command -v tailscale >/dev/null 2>&1; then
  echo "Tailscale already installed, skipping install."
else
  echo "Installing Tailscale (takes a minute or two)..."
  curl -fsSL https://tailscale.com/install.sh | sh
fi

systemctl enable --now tailscaled

echo
echo "============================================================"
echo "  A LOGIN LINK (https://login.tailscale.com/...) WILL"
echo "  APPEAR BELOW. Send a photo of it to Penn, then WAIT"
echo "  here — do NOT press anything or turn anything off."
echo "  When Penn clicks the link, this finishes by itself."
echo "============================================================"
echo
tailscale up --accept-dns=false

echo
echo '=== TAILSCALE IP (photo this too) ==='
tailscale ip -4
echo '=== PHASE 2 DONE — you are finished! ==='
