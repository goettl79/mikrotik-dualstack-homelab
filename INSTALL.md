# Installation & Inbetriebnahme-Leitfaden

Schritt-für-Schritt Anleitung zur physischen Verkabelung, Erstinbetriebnahme, automatischen Bereitstellung (Provisioning) und Konfiguration der Endgeräte für das MikroTik Dual-Stack Homelab.

---

## Übersicht der Phasen

1. [Phase 1: Physische Verkabelung](#phase-1-physische-verkabelung)
2. [Phase 2: RouterOS Provisioning & Deployment](#phase-2-routeros-provisioning--deployment)
3. [Phase 3: Konfiguration der Endgeräte](#phase-3-konfiguration-der-endgeräte)
4. [Phase 4: Sicherheits- & Funktionstests (Smoke Tests)](#phase-4-sicherheits---funktionstests-smoke-tests)
5. [Betrieb & Wartung](#betrieb--wartung)
6. [Secret Management & SOPS-Verschlüsselung](#secret-management--sops-verschlüsselung)
7. [Notfall & Factory Reset](#notfall--factory-reset)

---

## Phase 1: Physische Verkabelung

Verbinde die Netzwerkkabel exakt nach folgender Port-Belegung:

| Router-Port | Ziel-Gerät / Schnittstelle | Funktion / Zone | Kabeltyp |
| :--- | :--- | :--- | :--- |
| **`ether1`** | **A1 / Telematica ONT** (LAN-Port) | Internet Uplink (VLAN 31) | Cat6a / Cat6 |
| **`ether2`** | **QNAP NAS Port 2** (k3d Cluster) | Isolierte Server-Zone / DMZ (`192.168.20.0/24`) | Cat6a |
| **`ether3`** | **QNAP NAS Port 1** (SMB / QTS) | Heimnetz-Speicher (`192.168.10.0/24`) | Cat6a |
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

### 2. Deployment-Skript ausführen
Führe das mitgelieferte Bash-Skript aus. Es erkennt automatisch, ob der Router bereits auf `192.168.10.1` provisioniert ist oder noch auf `192.168.88.1` steht:

```bash
# Automatische Erkennung und Bereitstellung:
./deploy.sh

# Oder mit expliziten Parametern:
./deploy.sh [ZIEL_IP] [BENUTZER] [SSH_PORT] [PASSWORT]
```

Das Skript:
1. Prüft ICMP- und SSH-Konnektivität zum Router.
2. Ermittelt automatisch die Konfiguration (bevorzugt lokales `setup.rsc`, oder entschlüsselt `setup.enc.rsc` via SOPS).
3. Lädt das Skript per SCP hoch.
4. Führt den Import im RouterOS atomar und unterbrechungsfrei aus.

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
1. **Port 1 (Adapter 1 - Heimnetz):** Auf DHCP stellen → Erhält IP `192.168.10.10`.
2. **Port 2 (Adapter 2 - Server-Zone):** Auf DHCP stellen → Erhält IP `192.168.20.10`.
3. **Dienstebindung:** QTS Web-GUI & SMB-Dateifreigaben nur an Adapter 1 binden; k3d Container-Cluster an Adapter 2 binden.

### C. Sonos Multiroom-Lautsprecher
* Alle Sonos-Lautsprecher mit dem WLAN **`Family`** verbinden (oder per Cat6a LAN-Kabel an den Switch anschließen).

### D. Kinder-Endgeräte (KIDS-WLAN & Jugendschutz)
1. **WLAN:** Kinder-Laptops, Tablets und Handys mit der SSID **`Kids`** verbinden.
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
| **High-Speed NAS-Zugriff** | Große Datei auf SMB `\\192.168.10.10` kopieren | ~113–115 MB/s (Gigabit Line-Rate) |
| **k3d Management** | `kubectl get nodes` aus dem Heimnetz | Cluster antwortet über Port 6443 |
| **DMZ-Isolation (CRITICAL)** | Aus Container / Port 2: `ping 192.168.10.1` | **Timeout / DROP (Firewall blockt)** |
| **DNS-Zwang Kids-Geräte** | Am Kids-Gerät: `nslookup adult-site.com` | Wird durch Cloudflare Family blockiert |

---

## Betrieb & Wartung

### Router-Update

```bash
# Update-Status prüfen (read-only):
./bin/update-router.sh --check

# Lokales Pre-Upgrade-Backup:
./bin/update-router.sh --backup-only

# Sicheres RouterOS & Bootloader Update:
./bin/update-router.sh
```

**Sicherheitsmechanismen:** Pre-Flight Speicherprüfung → Automatisches Backup (.backup + .rsc) → Flash-Bereinigung → RouterOS Update + Reboot → RouterBOOT Upgrade + Reboot → Health-Check (WAN, DNS, DHCP).

### Geräte-Kategorien im Inventar (`inventory.enc.yaml`)

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

## Secret Management & SOPS-Verschlüsselung

Dieses Repository trennt strikt zwischen **öffentlicher Architektur-Dokumentation** und **sensiblen lokalen Netzwerkdaten** (reale MAC-Adressen, Hostnamen, Passwörter):

### Architektur des Datenschutzes

1. **Öffentliche Dokumentation (`README.md` & `INSTALL.md`):**
   * Enthält die vollständige Architektur-, Port- und Routing-Dokumentation ohne vertrauliche Gerätedaten.
2. **Verschlüsselte Produktionsdateien (`setup.enc.rsc` & `inventory.enc.yaml`):**
   * **`setup.enc.rsc`:** Echte Router-Konfiguration (SOPS Binary-Modus).
   * **`inventory.enc.yaml`:** Vollständiges Geräte- und Netzwerkinventar (natives SOPS YAML-Format: Schlüssel bleiben im Klartext sichtbar, sensible Werte werden verschlüsselt!).
   * Ausschließlich diese beiden verschlüsselten Dateien werden in Git versioniert und auf GitHub gespeichert.
3. **Lokale, unversionierte Klartext-Dateien (`.gitignore`):**
   * **`inventory.yaml`:** Lokales Geräteinventar im Klartext.
   * **`setup.rsc`:** Lokale Klartext-Konfiguration für die direkte Bereitstellung.
   * **`~/.config/sops/age/keys.txt`:** Lokaler privater age-Schlüssel zur Entschlüsselung.

### Wichtige SOPS-Befehle & Git-Automatisierung

Einmaliges Einrichten der Git-Hooks und Diff-Filter:
```bash
./bin/setup-git.sh
```

#### Automatisierter Workflow (Empfohlen)
* **Automatisches Verschlüsseln beim Commit:**
  ```bash
  git scommit -m "feat: add lease for new device"
  # oder:
  ./bin/commit.sh -m "feat: add lease for new device"
  ```
  *(Erkennt geänderte `inventory.yaml` bzw. `setup.rsc`, verschlüsselt sie automatisch und committet).*
* **Sicherheitsnetz (`pre-commit` Hook):**
  Verhindert zuverlässig, dass Klartext-Dateien (`inventory.yaml`, `setup.rsc`, `*.local.*`) versehentlich gestagt oder gepusht werden.
* **Automatisches Entschlüsseln (`post-merge` / `post-checkout` Hooks):**
  Aktualisiert nach einem `git pull` oder Branch-Wechsel automatisch die lokalen Arbeitsdateien.
* **Lesbares `git diff`:**
  Dank `.gitattributes` zeigt `git diff inventory.enc.yaml` oder `git diff setup.enc.rsc` automatisch die lesbaren Klartext-Änderungen an.

#### Manuelle Befehle & In-Place Bearbeitung
```bash
# Alle vertraulichen Dateien manuell entschlüsseln:
./bin/decrypt.sh

# Lokale Änderungen manuell verschlüsseln:
./bin/encrypt.sh

# Direktes In-Place Bearbeiten im Editor:
sops inventory.enc.yaml

# Deployment: Erkennt automatisch 'setup.rsc' oder entschlüsselt 'setup.enc.rsc':
./deploy.sh
```

---

## Notfall & Factory Reset

Falls der Router fehlkonfiguriert wurde oder nicht mehr erreichbar ist:
1. Stromstecker des MikroTik hEX ziehen.
2. Reset-Taste (`RES`) mit einer Büroklammer gedrückt halten.
3. Stromkabel anschließen, während die Taste gedrückt bleibt.
4. Sobald die `USR`-LED zu blinken beginnt (nach ca. 5–8 Sekunden), Taste **sofort loslassen**.
5. Der Router startet mit Werkseinstellungen (`192.168.88.1`). Danach `./deploy.sh` erneut ausführen.
