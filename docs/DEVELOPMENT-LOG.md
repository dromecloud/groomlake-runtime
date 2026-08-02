# Groomlake Runtime — Entwicklungslog

Diese Datei dokumentiert die laufenden Architekturentscheidungen für `groomlake-runtime`. Sie wird
bei jeder relevanten Runtime-Session ergänzt. Die technische Quelle bleibt der Code; dieses Log hält
fest, warum der Code so aufgebaut ist und welche Punkte noch offen sind.

## 2026-07-21 — Öffentliche Manifestquelle und harter Installationsabgleich

### Entschieden

- `groomlake-runtime` bleibt ein eigenständiges Git-Repository.
- `manifest.json` ist die gemeinsame Registry für MSO und MSR; sie bleibt die Root-Quelle.
- `schema_version` beschreibt das JSON-Format.
- `manifest_version` beschreibt den konkreten fachlichen Inhalt; aktuell `2026.07.22.5`.
- `provisioning.profiles` ist jetzt die verbindliche MSO-Quelle für Images, Architekturen, Release-Kanäle
  und fest versionierte Bootstrap-Dateien samt SHA-256. Jeder Bootstrap ist zusätzlich auf einen
  konkreten Runtime-Commit gepinnt. Tailscale, Docker und eine Profil-Bootstrap-Kopplung sind daraus entfernt.
- MSO übergibt im Installationsplan zusätzlich Manifest-Version, Manifest-SHA-256 und vollständigen
  Git-Commit.
- MSR liest nach dem Checkout `manifest.json` und bricht vor jedem Installationsschritt ab,
  wenn Version, SHA oder Commit nicht übereinstimmen.
- `scripts/` bleibt intern. Der Webserver veröffentlicht ausschließlich den read-only `public/atis.php`-Handler (ATIS), der die Root-Datei ausliefert.
- `build-release.sh` und die frühere Paket-/Archiv-Idee wurden entfernt. Der Server arbeitet direkt mit
  dem exakt ausgecheckten Git-Commit.

### Aktueller Ablauf

```text
MSO lädt öffentliches Manifest
→ MSO erstellt Installationsplan mit Version, SHA und Commit
→ Cloud-init checkt exakt diesen Commit aus
→ MSR liest manifest.json lokal
→ Version/SHA/Commit prüfen
→ Profil und Komponenten ausführen
```

### Implementiert

- Manifest-Version im öffentlichen Manifest.
- Install-Plan-Schema Version 2.
- MSR-Version-/SHA-/Commit-Abgleich.
- MOTD-Installation und Verifikation.
- Smoke-Test für Wiederholbarkeit, unbekanntes Profil und Manifest-Versionsfehler.
- `scripts/check.sh` als zentraler lokaler Prüfpunkt.

### Geprüft

```text
scripts/check.sh: PASS
MOTD-Smoke-Test: PASS
zweiter identischer Lauf: PASS
Manifest-Versionsfehler: wird abgewiesen
Working Tree: sauber
```

### Noch offen

1. Git-Checkout auf Codehangar deployen und `public/commit.txt` aus dem Commit erzeugen.
2. MSO manuell öffnen und prüfen, dass Image, Release-Kanal und Features ausschließlich aus
   `provisioning.profiles` angezeigt werden. Erst danach den kostenpflichtigen Frischserver-Test starten.
3. Erst danach den automatischen Boot-Starter und weitere Komponenten bauen.

## Arbeitsregel

Keine neue Runtime-Komponente ohne:

1. Eintrag im Manifest;
2. Profil-/Komponentenvertrag;
3. Smoke- oder Vertragsprüfung;
4. Dokumentation dieses Ablaufs und der offenen Punkte.

## 2026-07-23 — Komponentenvertrag und Deadman-Zielregel

MSO übergibt jetzt neben Profil und Integritätsdaten auch eine serverseitig
geprüfte Komponentenliste. Pflichtkomponenten kommen aus
profiles.<id>.components und werden immer ergänzt; optionale Komponenten
dürfen nur aus optional_components desselben Profils stammen. MSR validiert
die IDs, Pflichtanteile und depends_on-Beziehungen und führt anschließend
ausschließlich die ausgewählten registrierten Komponenten aus. Der lokale
Smoke-Test deckt MOTD und Health, Wiederholbarkeit sowie einen Manifestfehler
ab. Der Frischserver-End-to-End-Nachweis steht noch aus.

Deadman Control verwendet keine 24-Stunden-Karenz mehr. Die Konfiguration
unterstützt eine kurze Grace-Phase (Standard 120 Sekunden): Lease abgelaufen
→ Graceful Shutdown → bei weiter laufendem Server Hetzner-Poweroff
→ nach bestätigtem off Server löschen. Volumes bleiben unberührt. Der Dienst
bleibt standardmäßig deaktiviert, bis ein kontrollierter Dry-Run und ein
produktiver Test ausdrücklich freigegeben sind.

Der öffentliche Commit-Marker wurde anschließend auf den geprüften
Content-Commit c145559415779f91dc9f5fd19f6067510deb3f57 gesetzt. Der
Marker-Commit selbst enthält nur diese Veröffentlichung; dadurch checkt MSO
den Runtime-Stand mit Komponentenvertrag und Manifest-Version 2026.07.23.2
aus, ohne einen selbstreferenziellen Commit-Marker zu erzeugen.

## 2026-07-22 — Git-Clone mit kurzlebigem Broker-Zugriff

Die Paket-Variante wurde als unnötiger Zwischenpfad zurückgenommen. Für den ersten funktionalen
MOTD-/Frischserver-Test bleibt das Runtime-Git die vollständige, aber geheimnisfreie Quelle. Der
Bootstrap klont ausschließlich den vom Broker freigegebenen Repository-Commit und MSR führt weiterhin
nur die Profil-Komponenten aus.

Der Runtime-Katalog trägt jetzt pro Profil die freigegebenen Komponenten. Toolhub erzeugt vor dem
Hetzner-Aufruf ein einmaliges Ticket; der Provisioning-Broker tauscht es gegen einen kurzlebigen,
read-only GitHub-App-Installationstoken. Der Token wird nie in Init oder Git gespeichert und nach dem
Checkout gelöscht.

`public/commit.txt` markiert den geprüften Runtime-Commit für ATIS. Der Inhalt muss bei jeder neuen
freigegebenen Runtime-Manifest-Version auf genau den Commit zeigen, dessen Manifest ATIS ausliefert;
dadurch kann Toolhub den Commit im Provisioning-Ticket unverändert an den Bootstrap weitergeben.

GitHub-App/Installation ist im server-only Config hinterlegt, die Ticket-Migration ist angewendet,
der Broker-Smoke-Test ist PASS und Bootstrap v1.0.3 ist veröffentlicht. Offen bleibt nur der
Plesk-Pull dieses Runtime-Branches und danach der neue Frischserver-Test.

## 2026-07-22 — ATIS-Deployment-Drift erkannt und sicher abgefangen

Der MSO-Create wurde fail-closed mit „Runtime-Profil enthält keine freigegebenen Komponenten“
abgebrochen. Ursache war kein Token- oder GitHub-Fehler, sondern ein veralteter Plesk-Checkout:
ATIS lieferte noch Manifest `2026.07.22.3`, obwohl Git bereits `2026.07.22.5` mit
`profiles.ironbird.components = ["motd"]` enthielt. Die Runtime-Korrektur wurde per Fast-Forward
nach `main` übernommen. Vor jedem kostenpflichtigen Server wird deshalb zuerst ATIS-Version und
Profil-Komponenten geprüft; erst danach folgt der Toolhub-Deploy und der Frischserver-Test.

## 2026-08-02 — Hermes-Agent und System-Upgrade als optionale Ironbird-Komponenten

### Entschieden

- Neue Komponente `hermes` installiert den Hermes-Agent (Nous Research,
  `https://hermes-agent.nousresearch.com/install.sh`) unter einem eigenen Systembenutzer `hermes`
  (kein Login-Shell, keine Mitgliedschaft in `sudo`). Der Installer wird per `curl` in eine Datei
  geladen, gegen eine in `profiles/ironbird/config/hermes.json` gepinnte SHA-256-Prüfsumme geprüft
  und erst danach als `hermes`-User ausgeführt — kein `curl | bash` ohne vorherige Prüfung.
- `libatomic1` wird vor dem Hermes-Installer explizit per `apt-get` installiert. Grund: ein
  Frischservertest am 01.08.2026 scheiterte mit `error while loading shared libraries:
  libatomic.so.1: cannot open shared object file`; das Paket fehlte auf dem Ubuntu-24.04-Basisimage.
- Der Installer läuft mit `--skip-setup --non-interactive --skip-browser`. Modellzugang/API-Schlüssel
  werden bewusst NICHT automatisiert — das bleibt ein separater, manueller Schritt nach der
  Installation, damit keine Secrets ins Manifest/Git gelangen.
- Bewusst keine Einzel-Checkboxen für Hermes-interne Abhängigkeiten (Python via `uv`, Hermes-verwaltetes
  Node.js). Das wären keine unabhängig abwählbaren Fähigkeiten, sondern Interna des Installers; sie
  stehen stattdessen als Klartext in `manifest.json.components.hermes.display.description`.
- Keine automatische Fehlerbehebung bei Installationsfehlern. `install.sh` prüft alle bekannten
  Vorbedingungen hart und bricht bei jeder Abweichung ab (fail-closed, wie `health`); der Fehler landet
  über den bestehenden ACARS/Health-Pfad im Tower.
- Neue, unabhängige Komponente `system-upgrade` (`apt-get update && apt-get upgrade -y`) — bewusst
  getrennt von `hermes`, keine `depends_on`-Beziehung, frei an-/abwählbar. Ein volles Upgrade macht
  den Paketstand vom Ausführungszeitpunkt abhängig und würde die Reproduzierbarkeit gepinnter Commits
  aufweichen, wenn es fest in andere Komponenten eingebaut wäre.
- Beide Komponenten unterstützen ausschließlich `--root /` (echte Systemänderungen, kein
  Datei-Baum-Dry-Run wie bei `motd`/`health` möglich) und verlangen `EUID 0`.
- `manifest_version` auf `2026.07.23.5` angehoben; `hermes`/`system-upgrade` in
  `profiles.ironbird.optional_components` und `profiles/ironbird/profile.json` ergänzt
  (`required: false`, `default_enabled: false`).
- Kein Toolhub-Code (MSO/Lifecycle-PHP) geändert: `optional_components`-Checkboxen und deren
  serverseitige Validierung sind dort bereits vollständig manifest-getrieben.

### Geprüft

```text
scripts/check.sh: PASS (Syntax, JSON-Validität, msr-motd.sh, msr-hermes.sh)
tests/smoke/msr-hermes.sh: PASS — bestätigt gezielte Ablehnung wegen --root /
  für hermes und system-upgrade, nicht irgendeinen Registrierungsfehler
Commit 52e493a gepusht, commit.txt-Marker in Folgecommit ed06129 gesetzt.
Live-ATIS (https://groomlake-runtime.aero.drome.cloud/atis.php) verifiziert:
  X-Groomlake-Manifest-Version 2026.07.23.5, X-Groomlake-Commit 52e493a...,
  ironbird.optional_components enthält hermes + system-upgrade. Auto-Webhook-
  Deploy hat diesmal ohne manuellen Plesk-Pull funktioniert.
```

### Noch offen

1. MSO in echt öffnen und die beiden Checkboxen unter Iron Bird visuell bestätigen (ATIS-seitig
   bereits verifiziert, UI-seitig noch nicht mit eigenen Augen geprüft).
2. Erst danach, mit explizitem Go: realer, kostenpflichtiger Frischserver-Test (prüft `install.sh`/
   `verify.sh` echt, inkl. der jetzt vorab installierten `libatomic1`-Abhängigkeit).
3. Modellzugang/API-Schlüssel-Konfiguration und ein "Setup abgeschlossen"-Verweis im Tower bleiben
   bewusst spätere, eigene Schritte — nicht Teil dieser Komponente.
