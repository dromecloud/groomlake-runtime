# Flowise – Installationssequenz (Iron Bird / Groomlake)

Dokumentierter, reproduzierbarer Aufbau von Flowise auf einem
temporären Iron-Bird-Testserver (Hetzner, über Groomlake bereitgestellt).

Getestet auf: Ubuntu 24.04.4 LTS

## Übersicht

| # | Schritt | Typ |
|---|---|---|
| 1 | Server über Toolhub/Groomlake bereitstellen | manuell |
| 2 | Per SSH verbinden | manuell |
| 3 | Docker installieren | automatisierbar |
| 4 | Docker Compose Plugin installieren | automatisierbar |
| 5 | Verzeichnisstruktur anlegen | automatisierbar |
| 6 | Flowise-Container starten | automatisierbar |
| 7 | Lokal testen | automatisierbar |
| 8 | SSH-Tunnel für Zugriff | manuell |
| 9 | Browser-Test | manuell |

## Voraussetzungen

- Temporärer Hetzner-Server, bereitgestellt über Toolhub → Groomlake → Iron Bird
- SSH-Zugriff mit hinterlegtem Key
- Ubuntu 24.04 (oder kompatibel)

## 1. Server bereitstellen

Über Toolhub → Groomlake → Iron Bird einen temporären Hetzner-Server anfordern.
**Hinweis:** Temporäre Server können automatisch wieder abgebaut werden –
IP-Adresse ändert sich bei jedem neuen Server.

## 2. Verbinden

```bash
ssh -i <pfad-zum-key> root@<SERVER-IP>
falls Probleme wegen Key auftauchen, dann alte Schlüsseleinträge löschen mit Befehl:
ssh-keygen -R 2.28.48.201
```

## 3. Grundlagen prüfen

```bash
lsb_release -a
docker --version
docker compose version
```

Auf einem frischen Server sind Docker und Docker Compose in der Regel
**nicht** vorinstalliert.

## 4. Docker installieren

```bash
apt update
apt install -y docker.io
```

## 5. Docker Compose installieren

**Wichtig:** `docker-compose-plugin` ist NICHT über die normalen
Ubuntu-Paketquellen verfügbar (nur `docker.io`). Das offizielle
Docker-Repository muss eingebunden werden:

```bash
apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-compose-plugin
```

Prüfen: `docker compose version`

## 6. Flowise starten

```bash
mkdir -p /opt/flowise/data
cd /opt/flowise
# docker-compose.yml aus diesem Repo-Ordner hierher kopieren
über lokale Powershell klonen, nicht über bestehende ssh verbindung zum server
scp -i <Path to ssh key> <Path>\docker-compose.yml root@2.28.48.201:/opt/flowise/docker-compose.yml
docker compose up -d
```

Siehe `docker-compose.yml` in diesem Ordner für die vollständige Konfiguration.

**⚠️ Bekanntes Problem:** Das Image-Tag `flowiseai/flowise:latest` zeigt
aktuell auf Version 3.1.4, die beim Start abstürzt
(`TypeError: this.db.exec is not a function` in `connect-sqlite3`,
siehe [FlowiseAI/Flowise#6688](https://github.com/FlowiseAI/Flowise/issues/6688)).
**Workaround:** Version explizit auf `3.1.3` fixieren (bereits in der
`docker-compose.yml` in diesem Ordner umgesetzt).

## 7. Lokal testen

```bash
docker compose ps
docker compose logs --tail 50
curl -I http://127.0.0.1:3000
```

Erwartet: `HTTP/1.1 200 OK`

## 8. Zugriff via SSH-Tunnel

Flowise ist bewusst nur auf `127.0.0.1:3000` gebunden (nicht öffentlich
erreichbar). Zugriff erfolgt über SSH-Portweiterleitung:

```bash
ssh -i <pfad-zum-key> -L 3000:127.0.0.1:3000 root@<SERVER-IP>
```

Diese SSH-Sitzung muss offen bleiben, solange die Oberfläche genutzt wird.

**Hinweis:** Aktuell wird ein einfacher SSH-Tunnel statt einer vollwertigen
VPN-Lösung (WireGuard/Tailscale) genutzt – ausreichend für den Testbetrieb,
aber noch keine produktionsreife Lösung.

## 9. Browser-Test

```
http://localhost:3000
```

## Offene Punkte / nicht automatisiert

- Server-Bereitstellung über Toolhub (Schritt 1) läuft manuell, nicht scriptbar
- SSH-Tunnel (Schritt 8) ist eine manuelle Übergangslösung, kein dauerhafter VPN-Zugang
- Zwei nicht-fatale Node-Ladefehler beim Start (ReActAgent-Komponenten,
  `@langchain/core` Kompatibilitätsproblem) – Ursache noch nicht behoben,
  betrifft nur den ReAct-Agent-Node-Typ, restliche Funktionalität unbeeinträchtigt
- Persistenz nach Server-Neustart wurde manuell getestet, aber noch nicht
  in ein automatisiertes Test-Skript überführt
  
  
Dieses Repository enthält aktuell nur die **Baupläne** für den
Flowise-Aufbau (Compose-Datei, dokumentierte Schrittfolge). Die
**Ausführung** dieser Schritte erfolgt bisher manuell auf einem
temporären Iron-Bird-Server.

**In GitHub verbleibt:**
- `docker-compose.yml` (Container-Definition, Image-Version, Ports, Volumes)
- Diese README als dokumentierte Installationssequenz

**In die Groomlake Runtime wandert** (nächste Phase):
- Automatisiertes Ausführen der Schritte 3–7 (Docker-Installation,
  Compose-Datei-Bereitstellung, Container-Start) ohne manuelles
  SSH-Eintippen
- Möglichst auch Schritt 1 (Server-Bereitstellung über Toolhub),
  sofern die Runtime das anstoßen kann
- Die Schritte 2, 8 und 9 (SSH-Verbindung, Tunnel-Aufbau,
  Browser-Test) bleiben vermutlich auch danach manuelle
  Nutzerinteraktion, da sie den Zugriff einer Person betreffen,
  nicht die Server-Konfiguration selbst

Der Frischserver-Test in Phase 5 soll zeigen, ob diese Trennung so
funktioniert.
