# Version & Change History

Dokumentation aller Major- und Minor-Änderungen an der MikroTik RouterOS- und Homelab-Netzwerkarchitektur.

> [!NOTE]
> **Two-Tier Architektur:** Konkrete Netzwerkkonfigurationen, reale MAC-Adressen, operative Bereitstellungsskripte und das verschlüsselte Inventar werden zum Schutz vor unbefugtem Zugriff im privaten Operations-Repository (`goettl79/mikrotik-homelab-ops`) verwaltet.

---

## v1.2.0 (2026-09-14) — Zwei-Repository-Architektur & DNS-Zonentrennung

### Features & Änderungen:
* **Zwei-Repository-Architektur (Two-Tier Separation):**
  * Strikte Trennung zwischen öffentlichem Architektur-Showcase (`mikrotik-dualstack-homelab`) und privater Betriebsinfrastruktur (`mikrotik-homelab-ops`).
  * Öffentliches Repository enthält keinerlei Secrets, verschlüsselte Binärdateien oder operative Skripte.
* **Strikte Zonentrennung der DNS-Namen:**
  * **Heimnetz:** Einführung von `router.home.lan`, `nas.home.lan` und `ap.home.lan` (inkl. Kurzaliasen `router.lan`, `nas.lan`, `ap.lan`).
  * **Server-Zone / DMZ:** Einführung der Subdomain `*.dmz.lan` zur eindeutigen Kennzeichnung der DMZ-Isolation.
* **DMZ-Dienste migriert:**
  * NFS-Storage Host: `nas.dmz.lan`
  * Kubernetes API: `k8s.dmz.lan`
  * Grafana Dashboard: `grafana.dmz.lan`
  * Prometheus Metrics: `prometheus.dmz.lan`
  * Alertmanager: `alertmanager.dmz.lan`
* **Bereinigung alter DNS-Einträge:**
  * Veraltete flache `.lan`-DMZ-Namen (`nas-k8s.lan`, `k8s.lan`, `grafana.lan`, `prometheus.lan`, `alertmanager.lan`) wurden vom Router entfernt.
* **Integrations-Guide für Subprojekte:**
  * Interne Netzwerk- und Topologiedokumentation für verwandte Repositories (z. B. `willhaben-scrape`) wird im privaten Operations-Repository gepflegt.

---

## v1.1.0 (2026-09-14) — Monitoring-Stack & RFC 6762 Compliance

### Features & Änderungen:
* **RFC 6762 Konformität:**
  * Vollständige Entfernung aller `.local`-Unicast-DNS-Einträge (`nas160c30.local`, `nas.local`, `nas-k8s.local`), da `.local` gemäß RFC 6762 exklusiv für Multicast DNS (mDNS / Zeroconf / Bonjour / Avahi) reserviert ist.
* **Monitoring-Stack DNS:**
  * Bereitstellung von statischen DNS-Namen für Kubernetes NodePorts (Grafana, Prometheus, Alertmanager).

---

## v1.0.0 (2026-09-12) — Initiales Dual-Stack & DMZ Provisioning

### Features & Änderungen:
* **Edge Routing & Dual-Stack:**
  * MikroTik hEX (RB750Gr3) RouterOS v7 Konfiguration (`setup.rsc`).
  * FTTH VLAN 31 WAN-Uplink (A1/Telematica ONT) mit IPv4 DHCP & IPv6 DHCP-PD.
* **Zonensegmentierung:**
  * `HEIMNETZ` (`bridge-heimnetz`, ether3–5) mit L2 Hardware-Offloading.
  * `SERVER-ZONE` (ether2) isoliert für k3d Kubernetes (QNAP Port 2).
  * Firewall-Regelwerk: Strikte Isolation `SERVER-ZONE` → `HEIMNETZ` (`action=drop`).
* **Ingress & NAT:**
  * WAN Port 80/443 Forwarding an Ingress NodePorts.
  * Hairpin-NAT (Loopback Masquerade) für internen Zugriff auf Ingress-Domains.
  * Split-DNS für Ingress-Subdomains.
* **Sicherheit & Härtung:**
  * Management-Plane gehärtet (SSH strong-crypto, WinBox nur LAN, LEDs deaktiviert).
  * Jugendschutz (Kid-Control Zeitsteuerung, Cloudflare Family DNS, DoT Port 853 Sperre, IPv6-Block für Kids-Geräte).
  * IoT-Isolation auf TP-Link Archer AXE75 AP (`IoT_Home` AP-Isolation).
* **GitOps & Secret Management:**
  * SOPS + age Verschlüsselung für sensible Konfigurationsdateien.
  * Automatisches Deployment via SSH/SCP (`deploy.sh`).
