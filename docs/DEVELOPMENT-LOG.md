# Groomlake Runtime — Entwicklungslog

Diese Datei dokumentiert die laufenden Architekturentscheidungen für `groomlake-runtime`. Sie wird
bei jeder relevanten Runtime-Session ergänzt. Die technische Quelle bleibt der Code; dieses Log hält
fest, warum der Code so aufgebaut ist und welche Punkte noch offen sind.

## 2026-07-21 — Öffentliche Manifestquelle und harter Installationsabgleich

### Entschieden

- `groomlake-runtime` bleibt ein eigenständiges Git-Repository.
- `public/manifest.json` ist die gemeinsame Registry für MSO und MSR.
- `schema_version` beschreibt das JSON-Format.
- `manifest_version` beschreibt den konkreten fachlichen Inhalt; aktuell `2026.07.21.1`.
- MSO übergibt im Installationsplan zusätzlich Manifest-Version, Manifest-SHA-256 und vollständigen
  Git-Commit.
- MSR liest nach dem Checkout `public/manifest.json` und bricht vor jedem Installationsschritt ab,
  wenn Version, SHA oder Commit nicht übereinstimmen.
- `scripts/` bleibt intern. Der Webserver veröffentlicht ausschließlich `public/manifest.json`.
- `build-release.sh` und die frühere Paket-/Archiv-Idee wurden entfernt. Der Server arbeitet direkt mit
  dem exakt ausgecheckten Git-Commit.

### Aktueller Ablauf

```text
MSO lädt öffentliches Manifest
→ MSO erstellt Installationsplan mit Version, SHA und Commit
→ Cloud-init checkt exakt diesen Commit aus
→ MSR liest public/manifest.json lokal
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

1. Git-Checkout auf Codehangar deployen.
2. Nur `public/manifest.json` über die Codehangar-Subdomain veröffentlichen.
3. MSO serverseitig auf diesen Manifest-Endpunkt umstellen; derzeit ist die MSO-Fähigkeitsmatrix noch
   in Toolhub-PHP fest codiert.
4. Späteres Ticket: Handler/InfoCollector für validierten serverseitigen Manifestabruf.
5. Erst danach den automatischen Boot-Starter und weitere Komponenten bauen.

## Arbeitsregel

Keine neue Runtime-Komponente ohne:

1. Eintrag im Manifest;
2. Profil-/Komponentenvertrag;
3. Smoke- oder Vertragsprüfung;
4. Dokumentation dieses Ablaufs und der offenen Punkte.
