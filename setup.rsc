# ==============================================================================
# MikroTik RouterOS v7 - Dual-Stack Provisioning Script
# Target Hardware: MikroTik hEX (RB750Gr3)
#
# SUB-NETZWERKE (Menschlich verständliche Nomenklatur):
#   1. INTERNET    (WAN)         : VLAN 31 auf ether1 (A1/Telematica ONT)
#   2. HEIMNETZ    (Privates LAN): 192.168.10.0/24 + IPv6 SLAAC (ether3-5)
#   3. SERVER-ZONE (k3d DMZ)     : 192.168.20.0/24 + IPv6 SLAAC (ether2)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. System, Identity & Basic Service Hardening
# ------------------------------------------------------------------------------
/system identity set name="MikroTik-hEX"

# Disable all LEDs permanently
:do { /system leds disable [ find ] } on-error={}

# --- Disable Unneeded & Insecure Management Services ---
/ip service set [ find name=telnet ] disabled=yes
/ip service set [ find name=ftp ] disabled=yes
/ip service set [ find name=www ] disabled=yes
/ip service set [ find name=api ] disabled=yes
/ip service set [ find name=api-ssl ] disabled=yes
/ip service set [ find name=winbox ] disabled=no
/ip service set [ find name=ssh ] disabled=no

# Enforce strong cryptographic algorithms for SSH
/ip ssh set strong-crypto=yes

# Disable Bandwidth Test Server & RoMON
/tool bandwidth-server set enabled=no
/tool romon set enabled=no

# Disable Unused Proxies, UPnP and Cloud DDNS
/ip proxy set enabled=no
/ip socks set enabled=no
/ip upnp set enabled=no
/ip cloud set ddns-enabled=no update-time=no

# ------------------------------------------------------------------------------
# 2. Interface Configuration & Bridge Setup
# ------------------------------------------------------------------------------
# Set interface comments
/interface set [ find default-name=ether1 ] name=ether1 comment="Uplink zum ONT (Internet)"
/interface set [ find default-name=ether2 ] name=ether2 comment="Server-Zone: QNAP Port 2 (k3d Kubernetes Cluster)"
/interface set [ find default-name=ether3 ] name=ether3 comment="Heimnetz: QNAP Port 1 (SMB / QTS Speicher)"
/interface set [ find default-name=ether4 ] name=ether4 comment="Heimnetz: TP-Link Archer AXE75 WLAN Access Point"
/interface set [ find default-name=ether5 ] name=ether5 comment="Heimnetz: Kabel-Hauptnetz (Switch -> Cat6a Raumdosen)"

# Seamless Bridge Setup (kein Verbindungsabbruch):
:do { /interface bridge set [ find name=bridge ] name=bridge-heimnetz comment="Bridge für privates Heimnetz (ether3-ether5)" } on-error={}
:if ([:len [/interface bridge find name=bridge-heimnetz]] = 0) do={
    /interface bridge add name=bridge-heimnetz comment="Bridge für privates Heimnetz (ether3-ether5)"
}

# ether1 (WAN) und ether2 (Server-Zone) aus der Bridge entfernen
:do { /interface bridge port remove [ find interface=ether1 ] } on-error={}
:do { /interface bridge port remove [ find interface=ether2 ] } on-error={}

# ether3, ether4, ether5 in bridge-heimnetz sicherstellen (Hardware Offloading)
:if ([:len [/interface bridge port find interface=ether3 and bridge=bridge-heimnetz]] = 0) do={
    /interface bridge port add bridge=bridge-heimnetz interface=ether3 hw=yes comment="QNAP Port 1 (SMB/QTS - HW-Switching 1 Gbps)"
}
:if ([:len [/interface bridge port find interface=ether4 and bridge=bridge-heimnetz]] = 0) do={
    /interface bridge port add bridge=bridge-heimnetz interface=ether4 hw=yes comment="TP-Link AXE75 AP (HW-Switching 1 Gbps)"
}
:if ([:len [/interface bridge port find interface=ether5 and bridge=bridge-heimnetz]] = 0) do={
    /interface bridge port add bridge=bridge-heimnetz interface=ether5 hw=yes comment="Kabel-Hauptnetz (HW-Switching 1 Gbps)"
}

# Create WAN VLAN 31 on ether1
:if ([:len [/interface vlan find name=vlan31-internet]] = 0) do={
    /interface vlan add name=vlan31-internet vlan-id=31 interface=ether1 comment="Internet Uplink VLAN 31 (A1/Telematica)"
}

# ------------------------------------------------------------------------------
# 3. Interface Lists (Strukturierte Sicherheitszonen)
# ------------------------------------------------------------------------------
:if ([:len [/interface list find name=INTERNET]] = 0) do={ /interface list add name=INTERNET }
:if ([:len [/interface list find name=HEIMNETZ]] = 0) do={ /interface list add name=HEIMNETZ }
:if ([:len [/interface list find name=SERVER-ZONE]] = 0) do={ /interface list add name=SERVER-ZONE }

# Alte Firewall-Regeln VOR Abänderung der Interface-Listen leeren, damit alte Drop-Regeln (!LAN) die Session nicht trennen
:do { /ip firewall filter remove [ find dynamic=no ] } on-error={}
:do { /ip firewall nat remove [ find dynamic=no ] } on-error={}
:do { /ipv6 firewall filter remove [ find dynamic=no ] } on-error={}

/interface list member remove [ find ]
/interface list member add interface=vlan31-internet list=INTERNET
/interface list member add interface=bridge-heimnetz list=HEIMNETZ
/interface list member add interface=ether2 list=SERVER-ZONE

# ------------------------------------------------------------------------------
# 4. Management Plane & Discovery Hardening (L2 / Neighbors)
# ------------------------------------------------------------------------------
# Restrict MAC-Winbox and MAC-Server strictly to Heimnetz
/tool mac-server set allowed-interface-list=HEIMNETZ
/tool mac-server mac-winbox set allowed-interface-list=HEIMNETZ
/tool mac-server ping set enabled=no

# Restrict Neighbor Discovery strictly to Heimnetz
/ip neighbor discovery-settings set discover-interface-list=HEIMNETZ

# ------------------------------------------------------------------------------
# 5. IPv4 Addressing & DHCP Servers
# ------------------------------------------------------------------------------
# Alte DHCP-Konfigurationen aufräumen
/ip dhcp-client remove [ find ]
/ip dhcp-server remove [ find ]
/ip dhcp-server network remove [ find ]
/ip pool remove [ find ]

# --- 1. HEIMNETZ (192.168.10.0/24) ---
/ip pool add name=pool-heimnetz ranges=192.168.10.100-192.168.10.200 comment="DHCP Pool für Heimnetz"
/ip dhcp-server add name=dhcp-heimnetz interface=bridge-heimnetz address-pool=pool-heimnetz disabled=no lease-time=12h
/ip dhcp-server network add address=192.168.10.0/24 gateway=192.168.10.1 dns-server=192.168.10.1 comment="Heimnetz DHCP Konfiguration"

# Neue IP auf bridge-heimnetz hinzufügen (192.168.88.1 bleibt temporär für die laufende SSH-Session bestehen)
:if ([:len [/ip address find address="192.168.10.1/24" and interface=bridge-heimnetz]] = 0) do={
    /ip address add address=192.168.10.1/24 interface=bridge-heimnetz network=192.168.10.0 comment="Gateway IP Heimnetz"
}

# --- 2. SERVER-ZONE (192.168.20.0/24 - k3d Cluster) ---
/ip pool add name=pool-server-zone ranges=192.168.20.100-192.168.20.200 comment="DHCP Pool für Server-Zone (k3d)"
:if ([:len [/ip address find address="192.168.20.1/24" and interface=ether2]] = 0) do={
    /ip address add address=192.168.20.1/24 interface=ether2 network=192.168.20.0 comment="Gateway IP Server-Zone"
}
/ip dhcp-server add name=dhcp-server-zone interface=ether2 address-pool=pool-server-zone disabled=no lease-time=12h
/ip dhcp-server network add address=192.168.20.0/24 gateway=192.168.20.1 dns-server=1.1.1.1,8.8.8.8 comment="Server-Zone DHCP Konfiguration (Externe DNS für Container)"

# --- 3. INTERNET (WAN IPv4 DHCP Client) ---
/ip dhcp-client add interface=vlan31-internet add-default-route=yes use-peer-dns=no comment="Internet IPv4 DHCP Client"

# ------------------------------------------------------------------------------
# 6. IPv6 Addressing & DHCPv6-PD
# ------------------------------------------------------------------------------
/ipv6 settings set forward=yes accept-router-advertisements=yes

# Request /64 Prefix Delegation from ISP
:do { /ipv6 dhcp-client remove [ find ] } on-error={}
/ipv6 dhcp-client add interface=vlan31-internet request=prefix pool-name=ipv6-pd pool-prefix-length=64 add-default-route=no comment="Internet IPv6 DHCP-PD" script=":if (\$\"pd-valid\" = 1) do={\
    :delay 2s;\
    :local gw [/ipv6 neighbor find interface=vlan31-internet router=yes];\
    :if ([:len \$gw] > 0) do={\
        :local gwIp ([/ipv6 neighbor get [:pick \$gw 0] address] . \"%vlan31-internet\");\
        :do { /ipv6 route remove [ find comment=\"Dynamic IPv6 Default Gateway (A1/Telematica)\" ] } on-error={};\
        /ipv6 route add dst-address=::/0 gateway=\$gwIp comment=\"Dynamic IPv6 Default Gateway (A1/Telematica)\";\
    }\
}"

# Fallback IPv6 Default Route to A1/Telematica BNG Gateway
:if ([:len [/ipv6 route find comment="Default IPv6 Gateway A1/Telematica"]] = 0) do={
    /ipv6 route add dst-address=::/0 gateway=fe80::ee38:73ff:fe0f:1005%vlan31-internet comment="Default IPv6 Gateway A1/Telematica"
}

# Assign IPv6 to Heimnetz & Server-Zone from ISP delegated pool (SLAAC / advertise=yes)
:do { /ipv6 address remove [ find dynamic=no ] } on-error={}
:if ([:len [/ipv6 address find interface=bridge-heimnetz and from-pool=ipv6-pd]] = 0) do={
    /ipv6 address add from-pool=ipv6-pd interface=bridge-heimnetz advertise=yes comment="Heimnetz IPv6 Subnetz (SLAAC)"
}
:if ([:len [/ipv6 address find interface=ether2 and from-pool=ipv6-pd]] = 0) do={
    /ipv6 address add from-pool=ipv6-pd interface=ether2 advertise=yes comment="Server-Zone IPv6 Subnetz (SLAAC - k3d)"
}

# Neighbor Discovery Settings
/ipv6 nd set [ find default=yes ] disabled=yes
:do { /ipv6 nd remove [ find default=no ] } on-error={}
:if ([:len [/ipv6 nd find interface=bridge-heimnetz]] = 0) do={
    /ipv6 nd add interface=bridge-heimnetz advertise-dns=yes managed-address-configuration=no other-configuration=no comment="ND für Heimnetz"
}
:if ([:len [/ipv6 nd find interface=ether2]] = 0) do={
    /ipv6 nd add interface=ether2 advertise-dns=yes managed-address-configuration=no other-configuration=no comment="ND für Server-Zone"
}

# ------------------------------------------------------------------------------
# 7. DNS Configuration
# ------------------------------------------------------------------------------
/ip dns set allow-remote-requests=yes servers=1.1.1.1,8.8.8.8,2606:4700:4700::1111,2001:4860:4860::8888

# ------------------------------------------------------------------------------
# 8. IPv4 Firewall & NAT
# ------------------------------------------------------------------------------
# Bestehende Firewall-Regeln aufräumen
:do { /ip firewall nat remove [ find dynamic=no ] } on-error={}
:do { /ip firewall filter remove [ find dynamic=no ] } on-error={}

# --- NAT ---
/ip firewall nat add chain=srcnat out-interface-list=INTERNET action=masquerade comment="NAT: Masquerade für ausgehenden Internet-Verkehr"

# --- Input Chain ---
/ip firewall filter add chain=input connection-state=established,related action=accept comment="Input: Etablierte Verbindungen erlauben"
/ip firewall filter add chain=input connection-state=invalid action=drop comment="Input: Invalide Pakete verwerfen"
/ip firewall filter add chain=input protocol=icmp action=accept comment="Input: ICMP (Ping) erlauben"
/ip firewall filter add chain=input in-interface-list=HEIMNETZ dst-port=53 protocol=udp action=accept comment="Input: DNS Anfragen aus Heimnetz erlauben (UDP)"
/ip firewall filter add chain=input in-interface-list=HEIMNETZ dst-port=53 protocol=tcp action=accept comment="Input: DNS Anfragen aus Heimnetz erlauben (TCP)"
/ip firewall filter add chain=input in-interface-list=HEIMNETZ action=accept comment="Input: Router-Management nur aus dem Heimnetz"
/ip firewall filter add chain=input action=drop comment="Input: Alles andere verwerfen (Default Drop)"

# --- Forward Chain ---
/ip firewall filter add chain=forward connection-state=established,related action=accept comment="Forward: Etablierte Verbindungen erlauben"
/ip firewall filter add chain=forward connection-state=invalid action=drop comment="Forward: Invalide Pakete verwerfen"

# Ausgehender Internetzugriff
/ip firewall filter add chain=forward in-interface-list=HEIMNETZ out-interface-list=INTERNET action=accept comment="Forward: Heimnetz -> Internet erlauben"
/ip firewall filter add chain=forward in-interface-list=SERVER-ZONE out-interface-list=INTERNET action=accept comment="Forward: Server-Zone -> Internet erlauben (Image Pulls/APIs)"

# Management & Zugriff aus dem Heimnetz in die Server-Zone (kubectl, Lens, Dev Web)
/ip firewall filter add chain=forward in-interface-list=HEIMNETZ out-interface-list=SERVER-ZONE action=accept comment="Forward: Heimnetz -> Server-Zone erlauben (kubectl/Dev)"

# Isolation: Server-Zone -> Heimnetz DROP (KRITISCHER SCHUTZ für QNAP Port 1 & Familien-PCs)
/ip firewall filter add chain=forward in-interface-list=SERVER-ZONE out-interface-list=HEIMNETZ action=drop comment="Forward: Server-Zone -> Heimnetz SPERREN (CRITICAL)"

# Eingehender Web-Verkehr aus dem Internet (dstnat auf Traefik Ingress)
/ip firewall filter add chain=forward in-interface-list=INTERNET out-interface-list=SERVER-ZONE connection-nat-state=dstnat action=accept comment="Forward: Internet -> Server-Zone (nur freigegebener Ingress)"

# Standard Fallback
/ip firewall filter add chain=forward action=drop comment="Forward: Alles andere verwerfen (Default Drop)"

# ------------------------------------------------------------------------------
# 9. IPv6 Firewall
# ------------------------------------------------------------------------------
:do { /ipv6 firewall filter remove [ find dynamic=no ] } on-error={}

# --- Input Chain ---
/ipv6 firewall filter add chain=input connection-state=established,related action=accept comment="IPv6 Input: Etablierte Verbindungen erlauben"
/ipv6 firewall filter add chain=input connection-state=invalid action=drop comment="IPv6 Input: Invalide Pakete verwerfen"
/ipv6 firewall filter add chain=input protocol=icmpv6 action=accept comment="IPv6 Input: ICMPv6 erlauben"
/ipv6 firewall filter add chain=input protocol=udp dst-port=546 in-interface-list=INTERNET action=accept comment="IPv6 Input: DHCPv6-PD Antworten aus Internet erlauben"
/ipv6 firewall filter add chain=input in-interface-list=HEIMNETZ action=accept comment="IPv6 Input: Router-Management nur aus Heimnetz"
/ipv6 firewall filter add chain=input action=drop comment="IPv6 Input: Alles andere verwerfen (Default Drop)"

# --- Forward Chain ---
/ipv6 firewall filter add chain=forward connection-state=established,related action=accept comment="IPv6 Forward: Etablierte Verbindungen erlauben"
/ipv6 firewall filter add chain=forward connection-state=invalid action=drop comment="IPv6 Forward: Invalide Pakete verwerfen"
/ipv6 firewall filter add chain=forward protocol=icmpv6 action=accept comment="IPv6 Forward: ICMPv6 erlauben"

/ipv6 firewall filter add chain=forward in-interface-list=HEIMNETZ out-interface-list=INTERNET action=accept comment="IPv6 Forward: Heimnetz -> Internet erlauben"
/ipv6 firewall filter add chain=forward in-interface-list=SERVER-ZONE out-interface-list=INTERNET action=accept comment="IPv6 Forward: Server-Zone -> Internet erlauben"
/ipv6 firewall filter add chain=forward in-interface-list=HEIMNETZ out-interface-list=SERVER-ZONE action=accept comment="IPv6 Forward: Heimnetz -> Server-Zone erlauben (kubectl)"

# Isolation Server-Zone -> Heimnetz (KRITISCHER SCHUTZ)
/ipv6 firewall filter add chain=forward in-interface-list=SERVER-ZONE out-interface-list=HEIMNETZ action=drop comment="IPv6 Forward: Server-Zone -> Heimnetz SPERREN (CRITICAL)"

# Default Fallback
/ipv6 firewall filter add chain=forward action=drop comment="IPv6 Forward: Alles andere verwerfen (Default Drop)"

# ------------------------------------------------------------------------------
# 10. Final Cleanup: Alte 192.168.88.1 IP entfernen
# ------------------------------------------------------------------------------
:delay 2s
/ip address remove [ find address="192.168.88.1/24" ]

# ==============================================================================
# End of setup.rsc
# ==============================================================================
