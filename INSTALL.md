# Installation & Inbetriebnahme-Leitfaden

> [!NOTE]
> **Showcase & Architektur-Referenz:**
> Dieser Leitfaden beschreibt die physische Verkabelung, Erstinbetriebnahme und Konfiguration der Endgeräte für das MikroTik Dual-Stack Homelab. Sämtliche operativen Skripte (`deploy.sh`, `update-router.sh`), reale MAC-Adressen und das verschlüsselte Geräteinventar werden im privaten Operations-Repository (`goettl79/mikrotik-homelab-ops`) betrieben.

---

## Übersicht der Phasen

1. [Phase 1: Physische Verkabelung](#phase-1-physische-verkabelung)
2. [Phase 2: RouterOS Provisioning & Deployment](#phase-2-routeros-provisioning--deployment)
3. [Phase 3: Konfiguration der Endgeräte](#phase-3-konfiguration-der-endgeräte)
4. [Phase 4: Sicherheits- & Funktionstests (Smoke Tests)](#phase-4-sicherheits---funktionstests-smoke-tests)
5. [Betrieb & Wartung](#betrieb--wartung)
6. [Operativer Betrieb & Secret Management](#operativer-betrieb--secret-management)
7. [Notfall & Factory Reset](#notfall--factory-reset)

---

## Phase 1: Physische Verkabelung

Verbinde die Netzwerkkabel exakt nach folgender Port-Belegung:

| Router-Port | Ziel-Gerät / Schnittstelle | Funktion / Zone | Kabeltyp |
| :--- | :--- | :--- | :--- |
| **`ether1`** | **A1 / Telematica ONT** (LAN-Port) | Internet Uplink (VLAN 31) | Cat6a / Cat6 |
| **`ether2`** | **QNAP NAS Port 2** (k3d Cluster / Ingress) | Isolierte Server-Zone / DMZ (`nas.dmz.lan` / `192.168.20.10`) | Cat6a |
| **`ether3`** | **QNAP NAS Port 1** (SMB / QTS Web-UI) | Heimnetz-Speicher (`nas.home.lan` / `nas.lan` / `192.168.10.10`) | Cat6a |
| **`ether4`** | **TP-Link Archer AXE75** (WAN/LAN) | Wi-Fi 6E Tri-Band Access Point | Cat6a |
| **`ether5`** | **Zentraler Gigabit-Switch** | Kabel-Hauptnetz (Dosen in allen Zimmern) | Cat6a |

> [!IMPORTANT]
> **Keine Kabelbrücke auf dem QNAP NAS!**
> QNAP Port 1 und Port 2 dürfen im QTS Betriebssystem **niemals** gebrückt werden. Sie gehören in zwei getrennte Layer-3-Subnetze.

---

## Phase 2: RouterOS Provisioning & Deployment

### 1. Physische Verbindung herstellen
Schließe deinen PC/Laptop per LAN-Kabel an **`ether3`**, **`ether4`** oder **`ether5`** des MikroTik hEX an.
*(Ein fabrikneuer oder zurückgesetzter Router startet mit der IP `192.168.88.1`).*

### 2. Deployment & Konfigurations-Import
Das Deployment erfolgt im Produktivbetrieb vollautomatisiert über das private Operations-Repository (`mikrotik-homelab-ops`):

```bash
# Im privaten Operations-Repository:
./deploy.sh
```

Das Skript:
1. Prüft ICMP- und SSH-Konnektivität zum Router (erkennt `192.168.88.1` oder `192.168.10.1`).
2. Entschlüsselt `setup.enc.rsc` on-the-fly via SOPS (oder nutzt lokales `setup.rsc`).
3. Lädt das Skript per SCP hoch und führt `/import verbose=no` atomar und unterbrechungsfrei aus.

*(Alternativ: Manueller Import einer vorbereiteten `.rsc`-Datei im RouterOS Terminal via `/import file-name=setup.rsc`)*

### 3. Admin-Passwort setzen & absichern
Verbinde dich unmittelbar nach dem ersten Import via SSH oder WinBox auf **`192.168.10.1`** und setze ein starkes Admin-Passwort:

```routeros
/user set admin password="DeinSicheresPasswort"
```

*(Optional: Hinterlege deinen SSH-Public-Key für passwortlosen Zugriff)*:
```bash
scp ~/.ssh/id_rsa.pub admin@192.168.10.1:id_rsa.pub
ssh admin@192.168.10.1 "/user ssh-keys import public-key-file=id_rsa.pub user=admin"
```

### 4. Status kontrollieren
Überprüfe im RouterOS Terminal die erfolgreiche IP- und Prefix-Zuweisung:

```routeros
# IPv4 DHCP-Client Status (VLAN 31)
/ip dhcp-client print

# IPv6 DHCP-PD Status (Prefix Delegation /64 bezogen)
/ipv6 dhcp-client print detail

# IP-Adressen auf Heimnetz-Bridge und Server-Zone (IPv6 SLAAC auf Heimnetz priorisiert)
/ip address print
/ipv6 address print
```

---

## Phase 3: Konfiguration der Endgeräte

### A. TP-Link Archer AXE75 (WLAN Access Point)
1. **Admin-GUI aufrufen:** Erreichbar unter **http://192.168.10.2** (feste DHCP-Reservierung im MikroTik).
2. **Betriebsmodus:** In der TP-Link Web-GUI auf **Access Point (AP-Modus)** umstellen.
3. **SSIDs einrichten:**
   * **`Family`** (2.4 / 5 / 6 GHz, Smart Connect, WPA2/WPA3): Alle Familien-Geräte inkl. Kinder-Smartphones, Chromecast, Sonos.
   * **`IoT_Home`** (2.4 GHz, WPA2): Smart Home (**Roborock Saugroboter**, **Gardena Mower**, **Portasplit Klimaanlage**). **„Access Local Network" / „AP-Isolation" AKTIVIEREN**.

#### WLAN SSIDs Übersicht

| SSID | Frequenz | Zielgruppe | NAS-Zugriff | k3d-Zugriff |
|:-----|:---------|:-----------|:---:|:---:|
| `Family` | 2.4 / 5 / 6 GHz (Wi-Fi 6E) | Alle Familien-Geräte inkl. Kinder (Jugendschutz MAC-basiert) | ✅ | ✅ |
| `IoT_Home` | 2.4 GHz (AP-Isolation) | Saugroboter, Mower, Klimaanlage | ⛔ | ⛔ |

### B. QNAP NAS (QTS Betriebssystem)
1. **Port 1 (Adapter 1 - Heimnetz):** Auf DHCP stellen → Erhält feste IP `192.168.10.10` (`nas.home.lan` / `nas.lan`).
2. **Port 2 (Adapter 2 - Server-Zone):** Auf DHCP stellen → Erhält feste IP `192.168.20.10` (`nas.dmz.lan`).
3. **Dienstebindung:** QTS Web-GUI & SMB-Dateifreigaben nur an Adapter 1 binden; k3d Container-Cluster an Adapter 2 binden.
4. **Caddy Ingress:** Läuft im Kubernetes-Cluster auf NodePorts 61200 (HTTP) und 61201 (HTTPS) und routet intern via Cluster-DNS (`prod-ui.immoad-prod:1080`, `prod-backend.immoad-prod:5000`, etc.).

### C. Sonos Multiroom-Lautsprecher
* Alle Sonos-Lautsprecher mit dem WLAN **`Family`** verbinden (oder per Cat6a LAN-Kabel an den Switch anschließen).

### D. Kinder-Endgeräte (Jugendschutz & Kid-Control)
1. **WLAN:** Kinder-Laptops, Tablets und Handys verbinden sich mit der normalen SSID **`Family`** (die separate SSID `Kids` wurde zugunsten eines einheitlichen WLAN-Meshs konsolidiert).
2. **MAC-Randomisierung deaktivieren:** In den WLAN-Einstellungen des Geräts **„Private WLAN-Adresse" auf „Aus"** (Telefon-/Geräte-MAC) stellen.
3. **Im MikroTik registrieren:**
   ```routeros
   # Gerät als statischen Lease mit Cloudflare Family DNS & Adressliste KIDS-DEVICES festlegen:
   /ip dhcp-server lease make-static [ find mac-address="XX:XX:XX:XX:XX:XX" ]
   /ip dhcp-server lease set [ find mac-address="XX:XX:XX:XX:XX:XX" ] dhcp-option=dns-cloudflare-family address-list=KIDS-DEVICES comment="Kind 1 Laptop"
   ```

---

## Phase 4: Sicherheits- & Funktionstests (Smoke Tests)

Führe nach Abschluss folgende Tests durch:

| Test | Durchführung / Befehl | Erwartetes Ergebnis |
| :--- | :--- | :--- |
| **Internetzugang IPv4 & IPv6** | `ping 1.1.1.1` & `ping6 google.com` | Erfolgreich (<20 ms Latenz) |
| **DNS-Auflösung Heimnetz & DMZ** | `getent hosts nas.home.lan` & `getent hosts nas.dmz.lan` | `.10.10` bzw. `.20.10` |
| **High-Speed NAS-Zugriff** | Große Datei auf SMB `\\nas.home.lan` kopieren | ~113–115 MB/s (Gigabit Line-Rate) |
| **k3d Management** | `kubectl get nodes` aus dem Heimnetz | Node `qnap-k3s` antwortet über Port 6443 |
| **Caddy Ingress & Hairpin-NAT** | `curl -k -I https://home.oettl.work` | HTTP/2 200 OK |
| **Backend API Health Check** | `curl -k -i https://api.oettl.work/api/v1/healthz` | HTTP/2 200 OK (`healthy`) |
| **DMZ-Isolation (CRITICAL)** | Aus Container / Port 2: `ping 192.168.10.1` | **Timeout / DROP (Firewall blockt)** |
| **DNS-Zwang Kids-Geräte** | Am Kids-Gerät: `nslookup adult-site.com` | Wird durch Cloudflare Family blockiert |

---

## Betrieb & Wartung

### Router-Update (Automatisierung im Ops-Repo)

Im privaten Operations-Repository (`mikrotik-homelab-ops`) steht ein gehärtetes Skript für automatisierte Updates zur Verfügung:

```bash
# Update-Status prüfen (read-only):
./bin/update-router.sh --check

# Lokales Pre-Upgrade-Backup:
./bin/update-router.sh --backup-only

# Sicheres RouterOS & Bootloader Update:
./bin/update-router.sh
```

**Sicherheitsmechanismen:** Pre-Flight Speicherprüfung → Automatisches Backup (.backup + .rsc) → Flash-Bereinigung → RouterOS Update + Reboot → RouterBOOT Upgrade + Reboot → Health-Check (WAN, DNS, DHCP).

### Geräte-Kategorien im Inventar (Architektur-Referenz)

Im Produktivbetrieb (`inventory.enc.yaml` im Ops-Repo) werden alle Geräte strukturiert verwaltet:

* **`family_devices`:** Eltern-Smartphones, Tablets, Workstations, Drucker, Streaming-Clients (Chromecast).
* **`kids_devices`:** Kinder-Smartphones und Laptops mit Kid-Control Zeitsteuerung & Cloudflare Family DNS.
* **`iot_devices`:** Smart Home (Roborock, Gardena Mower, Portasplit Klimaanlage) — AP-isoliert.
* **`sonos_audio`:** Multiroom-Audiosystem im Heimnetz.

### IPv6 Hinweise

* **Einzige /64 Prefix Delegation:** A1/Telematica delegiert ein einzelnes `/64` → nur ein L2-Segment kann SLAAC nutzen.
* **Priorisierung Heimnetz:** `/64` liegt auf `bridge-heimnetz` (Streaming-Kompatibilität für Chromecast/Android TV).
* **Server-Zone:** Läuft stabil über IPv4 NAT. Bei ISP-Upgrade auf `/56` kann `ether2` ein eigenes `/64` erhalten.

### RouterOS Cheat Sheet

#### Interfaces & Bridge
```routeros
/interface print                               # Link-Status
/interface bridge port print                   # HW-Offload Flags (H)
/interface list member print                   # Sicherheitszonen
```

#### DHCP & Leases
```routeros
/ip dhcp-server lease print                    # Alle Leases
/ip dhcp-server lease print detail             # Inkl. Lease-Time, Client-ID
/ip dhcp-server lease make-static [ find mac-address="XX:XX:XX:XX:XX:XX" ]
/ip dhcp-server lease set [ find mac-address="XX:XX:XX:XX:XX:XX" ] comment="Name"
```

#### Firewall & NAT
```routeros
/ip firewall filter print stats                # Paketzähler & Drop-Counter
/ip firewall filter print stats where action=drop
/ip firewall nat print stats                   # NAT-Statistiken
/ip firewall connection print                  # Aktive Verbindungen
/ip firewall address-list print where list="KIDS-DEVICES"
```

#### DNS
```routeros
/ip dns print                                  # Upstream-Server & Cache
/ip dns cache print                            # Cache-Inhalt
/ip dns cache flush                            # Cache leeren
:put [:resolve heise.de]                       # DNS-Test
```

#### IPv6
```routeros
/ipv6 dhcp-client print detail                 # PD-Status
/ipv6 address print                            # Globale Adressen
/ipv6 firewall filter print stats              # IPv6 Firewall
```

#### Kid-Control
```routeros
/ip kid-control print detail                   # Profile & Status
/ip kid-control device print detail            # Zugewiesene Geräte
/ip kid-control pause [ find name="Antonia" ]  # Sofort-Sperre
/ip kid-control resume [ find name="Antonia" ] # Freigabe
```

#### System & Monitoring
```routeros
/system resource print                         # CPU, RAM, Flash
/system clock print                            # NTP & Zeitzone
/log print follow                              # Live-Logs
/log print where topics~"dhcp"                 # Nur DHCP-Events
/interface monitor-traffic ether1,bridge-heimnetz  # Bandbreite
```

#### Backup & Export
```routeros
/export file=aktuelles-setup.rsc               # Text-Export
/system backup save name=backup-full           # Binär-Backup
```

---

## Operativer Betrieb & Secret Management

Dieses Setup nutzt eine strikte **Zwei-Repository-Architektur (Two-Tier Architecture)** zur vollständigen Trennung von öffentlicher Dokumentation und vertraulichen Netzwerkdaten:

### 1. Öffentlicher Showcase (`mikrotik-dualstack-homelab`)
* **Umfang:** Enthält die vollständige Architektur-, Port-, VLAN- und Routing-Dokumentation sowie C-Level Lessons Learned.
* **Sicherheit:** 100% frei von Secrets, Passwörtern, operativen Skripten und realen Geräte-Identifikatoren (MACs/IPs).

### 2. Privates Operations-Repository (`mikrotik-homelab-ops`)
* **Umfang:** Enthält alle operativen Bereitstellungs-Skripte (`deploy.sh`, `update-router.sh`), das vollständige Geräteinventar sowie die RouterOS-Konfiguration (`setup.rsc`).
* **Verschlüsselung (SOPS + age):**
  * `setup.enc.rsc`: Echte Router-Konfiguration (SOPS Binary-Modus).
  * `inventory.enc.yaml`: Zentrales Geräte- und Netzwerkinventar (natives SOPS YAML-Format: Schlüssel lesbar, sensible Werte verschlüsselt).
  * `NETWORK.enc.md`: Interne Topologie & DNS-Dokumentation für Subprojekte.
* **GitOps-Automatisierung:**
  * Git-Hooks (`pre-commit`) verhindern Leaks unverschlüsselter Arbeitsdateien.
  * Automatisches Ver- und Entschlüsseln via `./bin/encrypt.sh` und `./bin/decrypt.sh`.
  * Diff-Filter über `.gitattributes` für lesbare Klartext-Diffs verschlüsselter YAML-Dateien.

---

## Notfall & Factory Reset

Falls der Router fehlkonfiguriert wurde oder nicht mehr erreichbar ist:
1. Stromstecker des MikroTik hEX ziehen.
2. Reset-Taste (`RES`) mit einer Büroklammer gedrückt halten.
3. Stromkabel anschließen, während die Taste gedrückt bleibt.
4. Sobald die `USR`-LED zu blinken beginnt (nach ca. 5–8 Sekunden), Taste **sofort loslassen**.
5. Der Router startet mit Werkseinstellungen (`192.168.88.1`).
6. PC per LAN an Port 3, 4 oder 5 anschließen und im privaten Operations-Repository (`mikrotik-homelab-ops`) das Deployment-Skript ausführen:
   ```bash
   ./deploy.sh
   ```
