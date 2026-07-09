# mkt-site-b -- rendered from templates/router.rsc.j2, do not hand-edit.
# Managed by mikrotik-fleet. To change this router: edit sites.yaml or this
# template, open a PR, review the rendered diff, then redeploy. Winbox/CLI
# changes made directly on the box will be erased by the next deploy -- that
# is intentional (see docs/PLAN.md section 2).
#
# Role: base   RouterOS target: 7.16
#
# NOT YET LAB-VALIDATED. Boot this against a CHR in the lab before trusting
# it against real hardware -- see docs/lab-testing.md. RouterOS command
# syntax varies across 7.x point releases; confirm against site.routeros_version.

/system identity set name="mkt-site-b"

# --- Logging ---
/system logging action set [find name=memory] disk-lines-per-file=1000
/system logging add topics=info,warning,error,critical action=memory

# --- NTP client (overlay-only; do not sync to public NTP over WAN) ---
/system ntp client set enabled=yes
/system ntp client servers add address=10.99.0.1

# --- WAN ---
/ip dhcp-client add interface=ether1 disabled=no add-default-route=yes

# --- LAN bridge + VLANs ---
/interface bridge add name=bridge-lan
/interface bridge port add bridge=bridge-lan interface=ether2
/interface bridge port add bridge=bridge-lan interface=ether3
/interface vlan add name=vlan10-mgmt vlan-id=10 interface=bridge-lan
/ip address add address=10.253.11.1/24 interface=vlan10-mgmt
/interface vlan add name=vlan20-users vlan-id=20 interface=bridge-lan
/ip address add address=10.253.21.1/24 interface=vlan20-users

# --- Loopback ---
/interface bridge add name=lo comment="loopback, never bridged to a real port"
/ip address add address=10.253.0.2/32 interface=lo

# --- SNMP ---
/snmp set enabled=yes contact="noc@example.invalid" location="site-b"
/snmp community set [find default=yes] name="{{SECRET:snmp_community:site-b}}" read-access=yes write-access=no

# --- Management overlay (WireGuard) ---
# private-key below is a secret placeholder token resolved by deploy.py at
# deploy time -- see docs/secrets-setup.md. Never a real key in this file.
/interface wireguard add name=wg-mgmt listen-port=51820 private-key="{{SECRET:wg_privkey:site-b}}"
/interface wireguard peers add interface=wg-mgmt public-key="EXAMPLEPUBKEY_MGMT_HOST_REPLACE_ME=" endpoint-address=mgmt.example.invalid endpoint-port=51820 allowed-address=10.99.0.0/24 persistent-keepalive=25s
/ip address add address=10.99.0.3/24 interface=wg-mgmt

# --- Service binding: management ONLY on the overlay, insecure services off ---
/ip service disable telnet,ftp,www,api
/ip service set ssh address=10.99.0.0/24 disabled=no
/ip service set winbox address=10.99.0.0/24 disabled=no
/ip service set api-ssl address=10.99.0.0/24 disabled=no

# --- Users: per-human, SSH key only ---
/user group add name=fleet-admin policy=read,write,test,winbox,password,sniff,sensitive,api,rest-api
/user add name=noah group=fleet-admin address=10.99.0.0/24 disabled=no
/user ssh-keys import user=noah public-key-file=noah.pub
/user set [find name=admin] disabled=yes comment="default account disabled; use break-glass for local recovery"

# --- Drift collector: read-only user for the nightly export pull ---
# Deliberately lacks write/policy/sensitive so a stolen collector key gets
# an attacker /export, not /system reset-configuration. See scripts/drift_check.py.
/user group add name=fleet-readonly policy=ssh,read
/user add name=drift-ro group=fleet-readonly address=10.99.0.0/24 disabled=no comment="nightly drift export pull only; key held by the collector host"
/user ssh-keys import user=drift-ro public-key-file=drift-ro.pub

# --- Break-glass local admin (console/serial only, unique password per box) ---
# password is a secret placeholder token; never a real value in this file.
/user add name=breakglass group=full password="{{SECRET:break_glass_password:site-b}}" disabled=no comment="break-glass; existence and use are watched by the nightly drift diff"

# --- Firewall: default-drop input, management from overlay only ---
/ip firewall filter
add chain=input connection-state=established,related action=accept comment="allow established/related"
add chain=input connection-state=invalid action=drop comment="drop invalid"
add chain=input protocol=icmp action=accept comment="allow icmp"
add chain=input in-interface=wg-mgmt action=accept comment="allow mgmt overlay"
add chain=input in-interface=lo action=accept comment="allow loopback"
add chain=input action=drop comment="default drop -- management never on untrusted L2/L3"
add chain=forward connection-state=established,related action=accept comment="allow established/related"
add chain=forward connection-state=invalid action=drop comment="drop invalid"
add chain=forward in-interface=vlan10-mgmt out-interface=ether1 action=accept comment="mgmt to WAN"
add chain=forward in-interface=vlan20-users out-interface=ether1 action=accept comment="users to WAN"
add chain=forward action=drop comment="default drop -- no inter-vlan or inbound-from-wan forwarding unless explicitly allowed above"

# --- NAT ---
/ip firewall nat add chain=srcnat out-interface=ether1 action=masquerade comment="NAT to WAN"

# --- Watchdog: revert to last-known-good if mgmt overlay is unreachable past
#     the change-window threshold. The scheduler always runs, but the script
#     is a no-op unless the $wdArmed global is set -- deploy.py arms it over
#     SSH right after a deploy and disarms it once the human confirms success.
#     See docs/PLAN.md section 3 step 5 and docs/rebuild.md.
/system script add name=mgmt-watchdog-script owner=admin policy=read,write,test,sensitive source={
:global wdArmed
:global wdFailCount

:if ([:typeof $wdArmed] = "nothing") do={ :set wdArmed false }
:if ([:typeof $wdFailCount] = "nothing") do={ :set wdFailCount 0 }

:if ($wdArmed = false) do={
    :set wdFailCount 0
} else={
    :local probe "10.99.0.1"
    :local maxDown 15
    :local backupName "last-known-good.backup"

    :if ([/ping $probe count=3] = 0) do={
        :set wdFailCount ($wdFailCount + 1)
        :log warning ("watchdog: mgmt probe failed while armed, consecutive misses=" . $wdFailCount . "/" . $maxDown)
        :if ($wdFailCount >= $maxDown) do={
            :log error "watchdog: mgmt unreachable past threshold, restoring last-known-good backup and rebooting"
            :set wdArmed false
            :set wdFailCount 0
            /system backup load name=$backupName dont-require-keep-password=yes
        }
    } else={
        :if ($wdFailCount > 0) do={ :log info "watchdog: mgmt probe recovered, resetting counter" }
        :set wdFailCount 0
    }
}
}

/system scheduler add name=mgmt-watchdog interval=1m disabled=no on-event="/system script run mgmt-watchdog-script"
