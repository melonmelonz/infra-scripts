# 2026-06-10 19:39:10 by RouterOS 7.23.1
# software id = 9KVD-IXUB
#
# model = RB5009UPr+S+
# serial number = HK40AH9K236
/interface bridge
add admin-mac=04:F4:1C:81:E1:00 auto-mac=no comment=defconf name=bridge \
    vlan-filtering=yes
/interface ethernet
set [ find default-name=ether1 ] l2mtu=1514
set [ find default-name=ether2 ] l2mtu=1514
set [ find default-name=ether3 ] l2mtu=1514
set [ find default-name=ether4 ] l2mtu=1514
set [ find default-name=ether5 ] l2mtu=1514
set [ find default-name=ether6 ] l2mtu=1514
set [ find default-name=ether7 ] l2mtu=1514
set [ find default-name=ether8 ] l2mtu=1514
set [ find default-name=sfp-sfpplus1 ] l2mtu=1514
/interface vlan
add interface=bridge name=vlan10-mgmt vlan-id=10
add interface=bridge name=vlan20-servers vlan-id=20
add interface=bridge name=vlan30-gaming vlan-id=30
add interface=bridge name=vlan40-trusted vlan-id=40
/interface list
add comment=defconf name=WAN
add comment=defconf name=LAN
/ip pool
add name=pool-mgmt ranges=10.10.10.100-10.10.10.200
add name=pool-servers ranges=10.10.20.100-10.10.20.200
add name=pool-gaming ranges=10.10.30.100-10.10.30.200
add name=pool-trusted ranges=10.10.40.100-10.10.40.200
/ip dhcp-server
add address-pool=pool-mgmt interface=vlan10-mgmt name=dhcp-mgmt
add address-pool=pool-servers interface=vlan20-servers name=dhcp-servers
add address-pool=pool-gaming interface=vlan30-gaming name=dhcp-gaming
add address-pool=pool-trusted interface=vlan40-trusted name=dhcp-trusted
/disk settings
set auto-media-interface=bridge auto-media-sharing=yes auto-smb-sharing=yes
/interface bridge port
add bridge=bridge comment="mini PC (gaming)" interface=ether2 pvid=30
add bridge=bridge comment="backup box (servers)" interface=ether3 pvid=20
add bridge=bridge comment="BMC/IPMI (mgmt)" interface=ether4 pvid=10
add bridge=bridge comment=trusted interface=ether5 pvid=40
add bridge=bridge comment=trusted interface=ether6 pvid=40
add bridge=bridge comment=trusted interface=ether7 pvid=40
add bridge=bridge comment=trusted interface=ether8 pvid=40
add bridge=bridge comment="trunk to PVE host" interface=sfp-sfpplus1
/ip neighbor discovery-settings
set discover-interface-list=LAN
/interface bridge vlan
add bridge=bridge tagged=bridge,sfp-sfpplus1 untagged=ether4 vlan-ids=10
add bridge=bridge tagged=bridge,sfp-sfpplus1 untagged=ether3 vlan-ids=20
add bridge=bridge tagged=bridge,sfp-sfpplus1 untagged=ether2 vlan-ids=30
add bridge=bridge tagged=bridge,sfp-sfpplus1 untagged=\
    ether5,ether6,ether7,ether8 vlan-ids=40
/interface list member
add comment=defconf interface=bridge list=LAN
add comment=defconf interface=ether1 list=WAN
add interface=vlan10-mgmt list=LAN
add interface=vlan20-servers list=LAN
add interface=vlan30-gaming list=LAN
add interface=vlan40-trusted list=LAN
/ip address
add address=10.10.10.1/24 interface=vlan10-mgmt network=10.10.10.0
add address=10.10.20.1/24 interface=vlan20-servers network=10.10.20.0
add address=10.10.30.1/24 interface=vlan30-gaming network=10.10.30.0
add address=10.10.40.1/24 interface=vlan40-trusted network=10.10.40.0
/ip dhcp-client
# Interface not active
add comment=defconf interface=ether1 name=client1
/ip dhcp-server network
add address=10.10.10.0/24 dns-server=10.10.10.1 gateway=10.10.10.1
add address=10.10.20.0/24 dns-server=10.10.20.1 gateway=10.10.20.1
add address=10.10.30.0/24 dns-server=10.10.30.1 gateway=10.10.30.1
add address=10.10.40.0/24 dns-server=10.10.40.1 gateway=10.10.40.1
add address=192.168.88.0/24 comment=defconf dns-server=192.168.88.1 gateway=\
    192.168.88.1
/ip dns
set allow-remote-requests=yes servers=1.1.1.1,9.9.9.9
/ip dns static
add address=192.168.88.1 comment=defconf name=router.lan type=A
/ip firewall filter
add action=accept chain=input comment=\
    "defconf: accept established,related,untracked" connection-state=\
    established,related,untracked
add action=drop chain=input comment="defconf: drop invalid" connection-state=\
    invalid
add action=accept chain=input comment="defconf: accept ICMP" protocol=icmp
add action=accept chain=input comment=\
    "defconf: accept to local loopback (for CAPsMAN)" dst-address=127.0.0.1
add action=accept chain=input comment="mgmt -> router" in-interface=\
    vlan10-mgmt
add action=accept chain=input comment="trusted -> router mgmt" dst-port=\
    22,80,8291 in-interface=vlan40-trusted protocol=tcp
add action=accept chain=input comment="LAN DNS udp" dst-port=53 \
    in-interface-list=LAN protocol=udp
add action=accept chain=input comment="LAN DNS tcp" dst-port=53 \
    in-interface-list=LAN protocol=tcp
add action=accept chain=input comment="LAN DHCP" dst-port=67 \
    in-interface-list=LAN protocol=udp
add action=accept chain=forward comment="defconf: accept in ipsec policy" \
    ipsec-policy=in,ipsec
add action=accept chain=forward comment="defconf: accept out ipsec policy" \
    ipsec-policy=out,ipsec
add action=fasttrack-connection chain=forward comment="defconf: fasttrack" \
    connection-state=established,related
add action=accept chain=forward comment=\
    "defconf: accept established,related, untracked" connection-state=\
    established,related,untracked
add action=drop chain=forward comment="defconf: drop invalid" \
    connection-state=invalid
add action=drop chain=forward comment=\
    "defconf: drop all from WAN not DSTNATed" connection-nat-state=!dstnat \
    connection-state=new in-interface-list=WAN
add action=drop chain=input comment=\
    "drop everything else to router (incl WAN)"
add action=accept chain=forward comment="allow dst-nat (DayZ)" \
    connection-nat-state=dstnat connection-state=new
add action=accept chain=forward comment=LAN->WAN in-interface-list=LAN \
    out-interface-list=WAN
add action=accept chain=forward comment="mgmt -> all" in-interface=\
    vlan10-mgmt
add action=accept chain=forward comment="trusted -> all" in-interface=\
    vlan40-trusted
add action=accept chain=forward comment="gaming -> Jellyfin" dst-address=\
    10.10.20.0/24 dst-port=8096,8920 in-interface=vlan30-gaming protocol=tcp
add action=drop chain=forward comment="drop remaining inter-VLAN"
/ip firewall nat
add action=masquerade chain=srcnat comment="defconf: masquerade" \
    ipsec-policy=out,none out-interface-list=WAN
add action=dst-nat chain=dstnat comment="DayZ game" dst-port=2302-2306 \
    in-interface-list=WAN protocol=udp to-addresses=10.10.20.10
add action=dst-nat chain=dstnat comment="DayZ Steam query" dst-port=27016 \
    in-interface-list=WAN protocol=udp to-addresses=10.10.20.10
/ip service
set ftp disabled=yes
set telnet disabled=yes
set api disabled=yes
set api-ssl disabled=yes
/ipv6 firewall address-list
add address=::/128 comment="defconf: unspecified address" list=bad_ipv6
add address=::1/128 comment="defconf: lo" list=bad_ipv6
add address=fec0::/10 comment="defconf: site-local" list=bad_ipv6
add address=::ffff:0.0.0.0/96 comment="defconf: ipv4-mapped" list=bad_ipv6
add address=::/96 comment="defconf: ipv4 compat" list=bad_ipv6
add address=100::/64 comment="defconf: discard only " list=bad_ipv6
add address=2001:db8::/32 comment="defconf: documentation" list=bad_ipv6
add address=2001:10::/28 comment="defconf: ORCHID" list=bad_ipv6
add address=3ffe::/16 comment="defconf: 6bone" list=bad_ipv6
/ipv6 firewall filter
add action=accept chain=input comment=\
    "defconf: accept established,related,untracked" connection-state=\
    established,related,untracked
add action=drop chain=input comment="defconf: drop invalid" connection-state=\
    invalid
add action=accept chain=input comment="defconf: accept ICMPv6" protocol=\
    icmpv6
add action=accept chain=input comment="defconf: accept UDP traceroute" \
    dst-port=33434-33534 protocol=udp
add action=accept chain=input comment=\
    "defconf: accept DHCPv6-Client prefix delegation." dst-port=546 protocol=\
    udp src-address=fe80::/10
add action=accept chain=input comment="defconf: accept IKE" dst-port=500,4500 \
    protocol=udp
add action=accept chain=input comment="defconf: accept ipsec AH" protocol=\
    ipsec-ah
add action=accept chain=input comment="defconf: accept ipsec ESP" protocol=\
    ipsec-esp
add action=accept chain=input comment=\
    "defconf: accept all that matches ipsec policy" ipsec-policy=in,ipsec
add action=drop chain=input comment=\
    "defconf: drop everything else not coming from LAN" in-interface-list=\
    !LAN
add action=fasttrack-connection chain=forward comment="defconf: fasttrack6" \
    connection-state=established,related
add action=accept chain=forward comment=\
    "defconf: accept established,related,untracked" connection-state=\
    established,related,untracked
add action=drop chain=forward comment="defconf: drop invalid" \
    connection-state=invalid
add action=drop chain=forward comment=\
    "defconf: drop packets with bad src ipv6" src-address-list=bad_ipv6
add action=drop chain=forward comment=\
    "defconf: drop packets with bad dst ipv6" dst-address-list=bad_ipv6
add action=drop chain=forward comment="defconf: rfc4890 drop hop-limit=1" \
    hop-limit=equal:1 protocol=icmpv6
add action=accept chain=forward comment="defconf: accept ICMPv6" protocol=\
    icmpv6
add action=accept chain=forward comment="defconf: accept HIP" protocol=139
add action=accept chain=forward comment="defconf: accept IKE" dst-port=\
    500,4500 protocol=udp
add action=accept chain=forward comment="defconf: accept ipsec AH" protocol=\
    ipsec-ah
add action=accept chain=forward comment="defconf: accept ipsec ESP" protocol=\
    ipsec-esp
add action=accept chain=forward comment=\
    "defconf: accept all that matches ipsec policy" ipsec-policy=in,ipsec
add action=drop chain=forward comment=\
    "defconf: drop everything else not coming from LAN" in-interface-list=\
    !LAN
/system clock
set time-zone-name=America/New_York
/tool mac-server
set allowed-interface-list=LAN
/tool mac-server mac-winbox
set allowed-interface-list=LAN
