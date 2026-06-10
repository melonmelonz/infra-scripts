# Network Topology — Point-Cloud / Multi-Tenant Server

Edge device: **MikroTik RB5009UPr+S+IN** (quad-core ARM64, RouterOS v7).
Firewall + inter-VLAN routing + NAT all run **on the MikroTik** — no separate
pfSense box (see "Why no pfSense" at the end).

## Physical wiring

```
                 ISP (50 up / 1000 down)
                          |
                    ether1 (2.5G, WAN, DHCP client)
                          |
                 +------------------------+
                 |   MikroTik RB5009       |
                 |   firewall + router     |
                 +------------------------+
   sfp-sfpplus1 (10G) ||   | ether2  ether3  ether4   ether5-8
   TRUNK, all VLANs tagged  |  |        |       |          |
            ||              | (V30)   (V20)   (V10)      (V40)
            ||           mini PC   backup    host       spare /
            ||          (Moonlight) box     BMC/IPMI    clients /
            ||                                            switch
   +-------------------+
   |  Proxmox host     |  vmbr0 = VLAN-aware bridge on the 10G NIC.
   |  9965WX / 192GB   |  Each VM's vNIC is tagged into its VLAN:
   |                   |    Windows-main VM  -> VLAN30 (gaming)
   |  Windows-main VM  |    Services VM      -> VLAN20 (servers)
   |  Services VM      |    DayZ VM          -> VLAN20 (servers)
   |  DayZ VM          |    Linux compile VM -> VLAN10 (mgmt) or VLAN40
   |  Linux compile VM |    Host mgmt IP     -> VLAN10 (mgmt)
   +-------------------+
```

Why these choices:
- **Host on the 10G SFP+ trunk.** All four VMs ride one tagged link; the WAN is
  only 50/1000 so it stays on the 2.5G `ether1`. The SFP+ is the LAN-side 10G.
- **Mini PC + Windows-main VM both on VLAN30.** Same broadcast domain =
  Moonlight auto-discovery (mDNS) works AND the latency-critical stream is
  **L2 hardware-switched** — it never hits the router CPU. Sub-ms.
- **BMC/IPMI on VLAN10 (mgmt), its own access port.** Out-of-band recovery lives
  on the locked-down segment.

## VLAN plan

| VLAN | Name    | Subnet          | Gateway      | Members |
|------|---------|-----------------|--------------|---------|
| 10   | mgmt    | 10.10.10.0/24   | 10.10.10.1   | MikroTik, PVE host mgmt, BMC/IPMI, PBS, Linux compile VM |
| 20   | servers | 10.10.20.0/24   | 10.10.20.1   | Services VM (Jellyfin/DBs), DayZ VM, backup box |
| 30   | gaming  | 10.10.30.0/24   | 10.10.30.1   | Windows-main VM, friend's mini PC |
| 40   | trusted | 10.10.40.0/24   | 10.10.40.1   | Penn's laptop, workstations, spare ports |

Port -> VLAN map (access ports are untagged/pvid; trunk is tagged):

| Port          | Role               | VLAN |
|---------------|--------------------|------|
| ether1        | WAN (DHCP client)  | —    |
| sfp-sfpplus1  | Trunk to PVE host  | 10,20,30,40 tagged |
| ether2        | Mini PC (Moonlight)| 30 untagged |
| ether3        | Backup / ZFS box   | 20 untagged |
| ether4        | Host BMC / IPMI    | 10 untagged |
| ether5–ether8 | Spare / clients    | 40 untagged |

## Firewall policy (summary)

Default-drop on the `forward` chain; everything internal is denied unless listed:

- **Any VLAN -> Internet:** allowed (masquerade out `ether1`).
- **mgmt (10) -> all internal:** allowed (admin segment).
- **trusted (40) -> all internal:** allowed.
- **gaming (30) -> servers (20):** Jellyfin only (TCP 8096/8920). Nothing else.
- **gaming/servers -> mgmt (10):** denied. A compromised DayZ box cannot reach
  IPMI or the hypervisor mgmt IP.
- **WAN -> DayZ VM:** UDP 2302–2306 + 27016 only, via dst-nat. Nothing else
  inbound from the internet.
- **Jellyfin / RDP / DayZ admin:** never WAN-exposed — reach via Tailscale (your
  50 Mbps up gates remote Jellyfin anyway; transcode down).

---

## RouterOS v7 config (apply on the RB5009)

> **Apply safely.** Connect via Winbox (MAC-level, survives IP changes) or the
> serial console. Enter everything EXCEPT the final `vlan-filtering=yes` line,
> verify you still have access, then enable filtering last — turning it on with a
> wrong tagged/untagged map is the classic way to lock yourself out.

```routeros
# ===========================================================================
# 0. FIRST: update RouterOS + routerboard firmware (do in Winbox, then reboot)
#    /system package update check-for-updates
#    /system package update download   ; (reboot)
#    /system routerboard upgrade        ; (reboot)
#    Set a strong admin password and disable unused services:
#    /user set admin password=STRONG
#    /ip service disable telnet,ftp,www,api-ssl
# ===========================================================================

# --- Interface lists (used by the firewall) --------------------------------
/interface list add name=WAN
/interface list add name=LAN

# --- Bridge (VLAN-aware). Leave filtering OFF until the very end. -----------
/interface bridge
add name=bridge vlan-filtering=no comment="LAN bridge"

# --- Bridge ports. pvid = untagged VLAN for each access port. ---------------
/interface bridge port
add bridge=bridge interface=sfp-sfpplus1 comment="trunk to PVE host"
add bridge=bridge interface=ether2 pvid=30 comment="mini PC (gaming)"
add bridge=bridge interface=ether3 pvid=20 comment="backup box (servers)"
add bridge=bridge interface=ether4 pvid=10 comment="BMC/IPMI (mgmt)"
add bridge=bridge interface=ether5 pvid=40 comment="trusted"
add bridge=bridge interface=ether6 pvid=40 comment="trusted"
add bridge=bridge interface=ether7 pvid=40 comment="trusted"
add bridge=bridge interface=ether8 pvid=40 comment="trusted"

# --- VLAN membership: trunk + bridge tagged; access ports untagged ----------
/interface bridge vlan
add bridge=bridge vlan-ids=10 tagged=bridge,sfp-sfpplus1 untagged=ether4
add bridge=bridge vlan-ids=20 tagged=bridge,sfp-sfpplus1 untagged=ether3
add bridge=bridge vlan-ids=30 tagged=bridge,sfp-sfpplus1 untagged=ether2
add bridge=bridge vlan-ids=40 tagged=bridge,sfp-sfpplus1 untagged=ether5,ether6,ether7,ether8

# --- L3 VLAN interfaces on the bridge (the per-VLAN gateways) ---------------
/interface vlan
add interface=bridge name=vlan10-mgmt    vlan-id=10
add interface=bridge name=vlan20-servers vlan-id=20
add interface=bridge name=vlan30-gaming  vlan-id=30
add interface=bridge name=vlan40-trusted vlan-id=40

# --- Gateway addresses ------------------------------------------------------
/ip address
add address=10.10.10.1/24 interface=vlan10-mgmt
add address=10.10.20.1/24 interface=vlan20-servers
add address=10.10.30.1/24 interface=vlan30-gaming
add address=10.10.40.1/24 interface=vlan40-trusted

# --- Interface-list membership ---------------------------------------------
/interface list member
add list=WAN interface=ether1
add list=LAN interface=vlan10-mgmt
add list=LAN interface=vlan20-servers
add list=LAN interface=vlan30-gaming
add list=LAN interface=vlan40-trusted

# --- WAN: DHCP client from the ISP -----------------------------------------
/ip dhcp-client
add interface=ether1 use-peer-dns=yes add-default-route=yes comment="WAN"

# --- DHCP server per VLAN ---------------------------------------------------
/ip pool
add name=pool-mgmt    ranges=10.10.10.100-10.10.10.200
add name=pool-servers ranges=10.10.20.100-10.10.20.200
add name=pool-gaming  ranges=10.10.30.100-10.10.30.200
add name=pool-trusted ranges=10.10.40.100-10.10.40.200

/ip dhcp-server
add name=dhcp-mgmt    interface=vlan10-mgmt    address-pool=pool-mgmt
add name=dhcp-servers interface=vlan20-servers address-pool=pool-servers
add name=dhcp-gaming  interface=vlan30-gaming  address-pool=pool-gaming
add name=dhcp-trusted interface=vlan40-trusted address-pool=pool-trusted

/ip dhcp-server network
add address=10.10.10.0/24 gateway=10.10.10.1 dns-server=10.10.10.1
add address=10.10.20.0/24 gateway=10.10.20.1 dns-server=10.10.20.1
add address=10.10.30.0/24 gateway=10.10.30.1 dns-server=10.10.30.1
add address=10.10.40.0/24 gateway=10.10.40.1 dns-server=10.10.40.1

# --- DNS resolver ----------------------------------------------------------
/ip dns set allow-remote-requests=yes servers=1.1.1.1,9.9.9.9

# --- NAT: masquerade LAN to WAN; dst-nat DayZ ------------------------------
/ip firewall nat
add chain=srcnat out-interface-list=WAN action=masquerade comment="LAN->WAN"
# DayZ server VM (servers VLAN). Adjust the to-addresses to the DayZ VM IP.
add chain=dstnat in-interface-list=WAN protocol=udp dst-port=2302-2306 \
    action=dst-nat to-addresses=10.10.20.10 comment="DayZ game"
add chain=dstnat in-interface-list=WAN protocol=udp dst-port=27016 \
    action=dst-nat to-addresses=10.10.20.10 comment="DayZ Steam query"

# --- Firewall: INPUT (traffic to the router itself) ------------------------
/ip firewall filter
add chain=input action=accept connection-state=established,related
add chain=input action=drop  connection-state=invalid
add chain=input action=accept protocol=icmp comment="ping"
# mgmt VLAN fully manages the router (Winbox/SSH/API/DNS/DHCP)
add chain=input in-interface=vlan10-mgmt action=accept comment="mgmt -> router"
# other LANs only need DHCP + DNS from the router
add chain=input in-interface-list=LAN protocol=udp dst-port=53 action=accept
add chain=input in-interface-list=LAN protocol=tcp dst-port=53 action=accept
add chain=input in-interface-list=LAN protocol=udp dst-port=67 action=accept comment="DHCP"
add chain=input action=drop comment="drop everything else to router (incl WAN)"

# --- Firewall: FORWARD (traffic through the router) ------------------------
add chain=forward action=accept connection-state=established,related
add chain=forward action=drop  connection-state=invalid
# allow inbound DayZ that was dst-nat'd above
add chain=forward connection-nat-state=dstnat connection-state=new \
    action=accept comment="allow DayZ dst-nat"
# any VLAN may reach the internet
add chain=forward in-interface-list=LAN out-interface-list=WAN action=accept comment="LAN->WAN"
# admin + trusted may reach all internal segments
add chain=forward in-interface=vlan10-mgmt    action=accept comment="mgmt -> all"
add chain=forward in-interface=vlan40-trusted action=accept comment="trusted -> all"
# gaming may reach Jellyfin on servers, nothing else internal
add chain=forward in-interface=vlan30-gaming dst-address=10.10.20.0/24 \
    protocol=tcp dst-port=8096,8920 action=accept comment="gaming -> Jellyfin"
# default: drop all other inter-VLAN traffic
add chain=forward action=drop comment="drop remaining inter-VLAN"

# ===========================================================================
# FINAL STEP — turn on VLAN filtering (do this LAST, after verifying access):
/interface bridge set bridge vlan-filtering=yes
# ===========================================================================
```

## After applying — verify

On the MikroTik:
```routeros
/interface bridge vlan print        # confirm tagged/untagged map
/ip address print                   # four gateways present
/ip dhcp-server lease print         # clients getting leases in the right subnet
/ip firewall filter print stats     # watch the drop counters
```

End-to-end checks:
- Mini PC (ether2) gets a `10.10.30.x` lease and Moonlight discovers the Windows
  VM automatically.
- A device on `trusted` can open Jellyfin; a device forced onto `gaming` can ONLY
  hit Jellyfin's ports on the servers subnet, nothing else.
- From the WAN side, only the DayZ UDP ports answer; IPMI/Jellyfin/RDP do not.

## Why no pfSense

The RB5009 is a quad-core ARM64 running RouterOS — a full stateful firewall and
router. At a 50/1000 WAN and this LAN size, firewall load is negligible and it
does everything pfSense would here (VLANs, stateful rules, NAT, dst-nat). A
separate pfSense box would add another machine to power (the APC is already at
1000 W headroom under dual-GPU + 24-core), need its own 10G NICs to not bottleneck
the trunk, and add a failure point. The only reason to add OPNsense/pfSense would
be Suricata-style IDS/DPI — overkill here, and RouterOS can do basic IDS if ever
wanted. Decision: firewall on the MikroTik.
