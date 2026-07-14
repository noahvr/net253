# 2026-07-09 16:57:25 by RouterOS 7.22.3
# software id = RX81-NAI6
#
# model = CRS310-1G-5S-4S+
# serial number = HJY0AQ3FZFW
/interface bridge
add comment="main bridge - enable vlan-filtering at end" name=bridge1 \
    vlan-filtering=yes
/interface ethernet
set [ find default-name=ether1 ] comment="MGMT access VLAN4"
set [ find default-name=sfp-sfpplus1 ] comment="Hyla - access VLAN6"
set [ find default-name=sfp-sfpplus2 ] comment=SPARE
set [ find default-name=sfp-sfpplus3 ] comment="OLT4 - trunk 2,3,4,6,999"
set [ find default-name=sfp-sfpplus4 ] comment=\
    "KPUD transport - tagged 838 only"
set [ find default-name=sfp1 ] comment="trunk 4,6"
set [ find default-name=sfp2 ] comment="trunk 4,6"
set [ find default-name=sfp3 ] comment="trunk 4,6"
set [ find default-name=sfp4 ] comment="trunk 4,6"
set [ find default-name=sfp5 ] comment="trunk 4,6"
/interface wireguard
add comment="mgmt tunnel to verify.net253.net - key pinned for resetability" \
    listen-port=13231 mtu=1420 name=wg-mgmt
/interface vlan
add interface=bridge1 name=vlan2-TheWalk vlan-id=2
add interface=bridge1 name=vlan3-IRA vlan-id=3
add interface=bridge1 name=vlan4-MGMT vlan-id=4
add interface=bridge1 name=vlan6-Commercial vlan-id=6
add interface=bridge1 name=vlan838-KPUD vlan-id=838
add interface=bridge1 name=vlan999-Null vlan-id=999
/interface list
add comment="management plane access" name=MGMT
/ip pool
add name=pool-TheWalk ranges=208.87.163.130-208.87.163.191
add name=pool-IRA ranges=208.87.163.66-208.87.163.126
add name=pool-MGMT ranges=192.168.253.10-192.168.253.63
add name=pool-Commercial ranges=208.87.163.194-208.87.163.212
/ip dhcp-server
add address-pool=pool-TheWalk interface=vlan2-TheWalk lease-time=10h name=\
    dhcp-TheWalk
add address-pool=pool-IRA interface=vlan3-IRA lease-time=10h name=dhcp-IRA
add address-pool=pool-MGMT interface=vlan4-MGMT lease-time=4h name=dhcp-MGMT
add address-pool=pool-Commercial interface=vlan6-Commercial lease-time=1d \
    name=dhcp-Commercial
/interface bridge port
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether1 pvid=4
add bridge=bridge1 frame-types=admit-only-vlan-tagged interface=sfp1
add bridge=bridge1 frame-types=admit-only-vlan-tagged interface=sfp2
add bridge=bridge1 frame-types=admit-only-vlan-tagged interface=sfp3
add bridge=bridge1 frame-types=admit-only-vlan-tagged interface=sfp4
add bridge=bridge1 frame-types=admit-only-vlan-tagged interface=sfp5
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=sfp-sfpplus1 pvid=6
add bridge=bridge1 frame-types=admit-only-vlan-tagged interface=sfp-sfpplus3
add bridge=bridge1 frame-types=admit-only-vlan-tagged interface=sfp-sfpplus4
/ip neighbor discovery-settings
set discover-interface-list=MGMT
/interface bridge vlan
add bridge=bridge1 tagged=bridge1,sfp-sfpplus3 vlan-ids=2
add bridge=bridge1 tagged=bridge1,sfp-sfpplus3 vlan-ids=3
add bridge=bridge1 tagged=bridge1,sfp1,sfp2,sfp3,sfp4,sfp5,sfp-sfpplus3 \
    untagged=ether1 vlan-ids=4
add bridge=bridge1 tagged=bridge1,sfp1,sfp2,sfp3,sfp4,sfp5,sfp-sfpplus3 \
    untagged=sfp-sfpplus1 vlan-ids=6
add bridge=bridge1 tagged=bridge1,sfp-sfpplus4 vlan-ids=838
add bridge=bridge1 tagged=bridge1,sfp-sfpplus3 vlan-ids=999
/interface ethernet switch
set 0 l3-hw-offloading=yes
/interface list member
add interface=vlan4-MGMT list=MGMT
add interface=wg-mgmt list=MGMT
/interface wireguard peers
add allowed-address=10.254.0.0/24 client-allowed-address=::/0 comment=\
    "net253 hub router" endpoint-address=verify.net253.net endpoint-port=\
    51822 interface=wg-mgmt name=peer1 persistent-keepalive=25s public-key=\
    "iTLoK+9l/uOSdFZSzNqIQ5LUkmblUlPZQFuIxBF+2lQ="
/ip address
add address=10.254.0.3/24 comment="WireGuard mgmt" interface=wg-mgmt network=\
    10.254.0.0
add address=208.87.163.129/26 interface=vlan2-TheWalk network=208.87.163.128
add address=208.87.163.65/26 interface=vlan3-IRA network=208.87.163.64
add address=192.168.253.1/24 interface=vlan4-MGMT network=192.168.253.0
add address=208.87.163.193/27 interface=vlan6-Commercial network=\
    208.87.163.192
add address=23.140.108.246/30 interface=vlan838-KPUD network=23.140.108.244
add address=192.168.222.1/24 interface=vlan999-Null network=192.168.222.0
/ip dhcp-server lease
add address=208.87.163.217 comment=284-BIMA mac-address=24:5A:4C:87:66:D2 \
    server=dhcp-Commercial
add address=208.87.163.218 comment=350-Xpats mac-address=74:4D:28:B7:43:C0 \
    server=dhcp-Commercial
add address=208.87.163.220 comment=355-Hyla mac-address=70:A7:41:7D:56:9D \
    server=dhcp-Commercial
add address=208.87.163.221 comment=425-STE-200-InterPack mac-address=\
    70:A7:41:6C:C7:DB server=dhcp-Commercial
add address=208.87.163.222 comment=435-STE-250-Banzai mac-address=\
    70:A7:41:7D:49:89 server=dhcp-Commercial
/system script
add dont-require-permissions=no name=backup-nightly-export owner=admin \
    policy=ftp,read,write,policy,test,sensitive source="\r\
    \n    /export file=\"nightly\"\r\
    \n    :log info \"Nightly config export written: nightly.rsc\"\r\
    \n"
add dont-require-permissions=no name=backup-weekly-binary owner=admin policy=\
    ftp,read,write,policy,test,sensitive source="\r\
    \n    /system backup save name=\"weekly\" password=\"CHANGE-ME-STRONG-PASS\
    WORD\"\r\
    \n    :log info \"Weekly binary backup written: weekly.backup\"\r\
    \n"
/ip dhcp-server network
add address=192.168.253.0/24 comment="MGMT VLAN4" dns-server=8.8.8.8,1.1.1.1 \
    gateway=192.168.253.1
add address=208.87.163.64/26 comment="IRA VLAN3" dns-server=8.8.8.8,1.1.1.1 \
    gateway=208.87.163.65
add address=208.87.163.128/26 comment="The Walk VLAN2" dns-server=\
    8.8.8.8,1.1.1.1 gateway=208.87.163.129
add address=208.87.163.192/27 comment="Commercial VLAN6" dns-server=\
    8.8.8.8,1.1.1.1 gateway=208.87.163.193
/ip dns
set servers=8.8.8.8,1.1.1.1
/ip firewall filter
add action=accept chain=input comment="accept established/related/untracked" \
    connection-state=established,related,untracked
add action=drop chain=input comment="drop invalid" connection-state=invalid
add action=accept chain=input comment="allow ICMP (rate-limited)" limit=\
    50,10:packet protocol=icmp
add action=accept chain=input comment=\
    "DHCP server requests from customer/mgmt VLANs" dst-port=67 protocol=udp
add action=accept chain=input comment="full mgmt access from VLAN4" \
    in-interface-list=MGMT
add action=drop chain=input comment="drop all other input"
/ip route
add comment="KPUD transport" dst-address=0.0.0.0/0 gateway=23.140.108.245
/ip service
set ftp disabled=yes
set ssh address=192.168.253.0/24,10.99.0.1/32
set telnet disabled=yes
set www disabled=no
set winbox address=192.168.253.0/24,10.99.0.1/32
set api disabled=yes
set api-ssl disabled=yes
/ip ssh
set strong-crypto=yes
/system clock
set time-zone-name=America/Los_Angeles
/system identity
set name=355-edge
/system logging
set 0 disabled=yes
add topics=info,!wireguard
/system routerboard settings
set enter-setup-on=delete-key
add interval=1w name=sched-weekly-binary on-event=\
    "/system script run backup-weekly-binary" policy=\
    ftp,read,write,policy,test,sensitive start-date=2026-07-12 start-time=\
    03:15:00
/tool bandwidth-server
set enabled=no
/tool mac-server
set allowed-interface-list=MGMT
/tool mac-server mac-winbox
set allowed-interface-list=MGMT
/tool mac-server ping
set enabled=no
