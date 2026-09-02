# Agent Task: MikroTik hEX RB750Gr3 Dual-Stack Provisioning

## 1. Rolle & Ziel
Du bist ein Senior Network & Security Engineer. Deine Aufgabe ist es, ein vollständiges, idempotentes und produktionsreifes RouterOS v7 Konfigurationsskript (`setup.rsc`) für einen MikroTik hEX (RB750Gr3) zu generieren sowie ein Linux-Bash-Skript für das automatische Deployment via SSH/SCP bereitzustellen.

### Hauptziele der Architektur:
1. **Perimeter & Uplink:** Dual-Stack WAN-Anbindung über VLAN 31 (A1/Telematica ONT) mit IPv4 DHCP und IPv6 DHCP-PD (`/64`).
2. **High-Performance Heimnetz (`HEIMNETZ`):** 
   - L2 Hardware-Offloading (`hw=yes`) auf `bridge-heimnetz` für latenzfreien Gigabit-Drahtgeschwindigkeits-Zugriff (1 GBit/s, 0% CPU-Last) aus dem **Kabel-Hauptnetz (`ether5`)** und dem **Family-WLAN (`ether4`)** auf das **QNAP NAS (Port 1 / SMB & QTS auf `ether3`)**.
3. **Isolierte Dual-Stack Server-Zone (`SERVER-ZONE`):** 
   - Bereitstellung von IPv4 (`192.168.20.0/24`) und IPv6 SLAAC auf `ether2` für den **k3d Kubernetes Cluster** (QNAP Port 2 / Traefik Ingress & Pods).
   - Cluster-Administration (`kubectl`, API, Lens) aus dem `HEIMNETZ` erlaubt.
   - **Strikte Isolation (DROP):** Vollständige Blockierung jeglicher Zugriffe aus der `SERVER-ZONE` in das `HEIMNETZ` oder auf private QNAP Port 1 Daten.
4. **WLAN-Segmentierung (Archer AXE75 AP):** 
   - `Family` (Hauptnetz: Eltern, Laptops, PCs), `Kids` (Kindernetz & Gäste: isoliert) und `IoT_Home` (Smart Home: isoliert).
5. **Management-Plane Hardening:** 
   - Vollständige Härtung von RouterOS (Dienste minimiert, WinBox/SSH nur aus Heimnetz, L2 MAC-Server & Neighbor Discovery beschränkt, LEDs dauerhaft aus).

---

## 2. Netzwerk-Topologie & Subnetze (Klare Nomenklatur)

### 1. `INTERNET` (WAN Uplink auf ether1):
- Uplink zu A1/Telematica ONT
- VLAN 31 Interface: `vlan31-internet`
- IPv4 DHCP-Client auf VLAN 31 (Default Route: ja, Peer-DNS: nein)
- IPv6 DHCP-Client (Prefix Delegation) auf VLAN 31 (`ipv6-pd`, `/64`, Default Route: via BNG Neighbor / Link-Local Gateway)

### 2. `SERVER-ZONE` (Isolierte k3d Kubernetes DMZ & Luanti-Server auf ether2):
- Physisch isoliert (kein Bridge-Member, Interface: `ether2`)
- Uplink zu QNAP NAS Port 2 (k3d Cluster / Luanti-Gameserver / Traefik Ingress / Pods)
- IPv4 Subnetz: `192.168.20.0/24` (Gateway: `192.168.20.1`, DHCP-Pool: `192.168.20.100 - 192.168.20.200`, DNS: `1.1.1.1, 8.8.8.8`)
- IPv6 Subnetz: Subnetz aus Pool `ipv6-pd` (SLAAC / `advertise=yes`)

### 3. `HEIMNETZ` (Privates Dual-Stack LAN auf ether3, ether4, ether5):
- Bridge: `bridge-heimnetz`
- IPv4 Subnetz: `192.168.10.0/24` (Gateway: `192.168.10.1`, DHCP-Pool: `192.168.10.100 - 192.168.10.200`, DNS: `192.168.10.1`)
- IPv6 Subnetz: Subnetz aus Pool `ipv6-pd` (SLAAC / `advertise=yes`)
- **Port-Zuordnung:**
  - **ether3 (QNAP NAS Port 1):** 
    - Interne Dienste: SMB Speicher, automatische Foto-Backups, Cloud-Synchronisation & QTS Administration
    - *Zugriff ERLAUBT:* Aus `ether5` (Kabel-Hauptnetz) sowie `ether4` WLAN (`Family` & `Kids` SSIDs)
    - *Zugriff VERWEHRT:* `IoT_Home` (AP-Isolation), `SERVER-ZONE` (Firewall DROP) und `INTERNET` (Default Drop)
  - **ether4 (TP-Link Archer AXE75 im AP-Modus):**
    - Haupt-WLAN (`Family`, 2.4 / 5 / 6 GHz / Smart Connect): Eltern, Laptops, Arbeitsrechner, **Kinder-Smartphones**, **Sonos-Lautsprecher** $\rightarrow$ Voller Zugriff auf Heimnetz, QNAP Port 1 & k3d Server-Zone
    - Kindernetz (`Kids`, 2.4 / 5 GHz): **Schullaptops & persönliche Laptops der Kinder**, Tablets, Konsolen $\rightarrow$ Voller Zugriff auf Heimnetz, Streaming & QNAP Port 1 (keine AP-Isolation)
    - IoT-Netzwerk (`IoT_Home`, 2.4 GHz): Smart Home, Saugroboter $\rightarrow$ AP-Isolation aktiv (kein Zugriff auf private Daten)
  - **ether5 (Kabel-Hauptnetz):**
    - Zentraler Switch mit Cat6a Raumverkabelung in alle Zimmer $\rightarrow$ Voller Zugriff auf Heimnetz, QNAP Port 1 & k3d Server-Zone

---

## 3. Sicherheits- & Firewall-Matrix

### Interface Lists (Sicherheitszonen):
- `INTERNET`: `vlan31-internet`
- `HEIMNETZ`: `bridge-heimnetz`
- `SERVER-ZONE`: `ether2`

### IPv4 Forwarding-Regeln:
1. `established, related` $\rightarrow$ `accept`
2. `invalid` $\rightarrow$ `drop`
3. `HEIMNETZ` $\rightarrow$ `INTERNET` $\rightarrow$ `accept`
4. `SERVER-ZONE` $\rightarrow$ `INTERNET` $\rightarrow$ `accept` (Image-Pulls, Helm Repositories)
5. `HEIMNETZ` $\rightarrow$ `SERVER-ZONE` $\rightarrow$ `accept` (`kubectl`, Lens, Dev-Testing)
6. **`SERVER-ZONE` $\rightarrow$ `HEIMNETZ` $\rightarrow$ `drop` (KRITISCHE ISOLATION für QNAP Port 1 & Familien-PCs)**
7. `INTERNET` $\rightarrow$ `SERVER-ZONE` $\rightarrow$ nur `dstnat` (Port 80/443 für Traefik Ingress)
8. Standard-Fallback: `drop all`

### IPv6 Forwarding-Regeln:
1. `established, related` $\rightarrow$ `accept`
2. `invalid` $\rightarrow$ `drop`
3. `icmpv6` $\rightarrow$ `accept`
4. `HEIMNETZ` $\rightarrow$ `INTERNET` $\rightarrow$ `accept`
5. `SERVER-ZONE` $\rightarrow$ `INTERNET` $\rightarrow$ `accept`
6. `HEIMNETZ` $\rightarrow$ `SERVER-ZONE` $\rightarrow$ `accept`
7. **`SERVER-ZONE` $\rightarrow$ `HEIMNETZ` $\rightarrow$ `drop` (KRITISCHE ISOLATION)**
8. Standard-Fallback: `drop all`

### Input-Kette & System (Management Plane Hardening):
- Router-Management (WinBox, SSH) nur aus dem `HEIMNETZ` (`192.168.10.0/24`) erlauben; Telnet, FTP, WWW, API, API-SSL deaktivieren
- SSH mit `strong-crypto=yes` absichern
- MAC-Server & MAC-Winbox auf Interface-List `HEIMNETZ` beschränken, MAC-Ping deaktivieren
- Neighbor Discovery (MNDP/CDP/LLDP) auf INTERNET und SERVER-ZONE deaktivieren (`discover-interface-list=HEIMNETZ`)
- Bandwidth-Server, RoMON, UPnP, Proxies und Cloud DDNS deaktivieren
- Alle LEDs dauerhaft deaktivieren (`/system leds settings set all-leds-off=always`)

---

## 4. Erwartete Artefakte

1. **`setup.rsc`**: 
   - Vollständiges, produktionsreifes RouterOS v7 CLI-Skript
   - Saubere Strukturierung mit aussagekräftigen Kommentaren
2. **`deploy.sh`**: 
   - Bash-Skript für Linux (Konnektivitätsprüfung, SCP-Upload, Ausführung via SSH `/import setup.rsc`)
3. **`README.md` & Validierungsschritte**:
   - Dokumentation der Topologie (inkl. Mermaid-Diagramm)
   - CLI-Befehle zur Überprüfung der Zonen `INTERNET`, `HEIMNETZ`, `SERVER-ZONE` und Zugriffsmatrix