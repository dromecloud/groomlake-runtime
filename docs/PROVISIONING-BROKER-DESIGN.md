# Provisioning-Broker und Runtime-Pakete

Stand: 2026-07-22 — technische Grundlage gebaut, Handshake noch nicht live.

## Ziel

Ein neuer Server soll nicht das vollständige Entwicklungs-Repository klonen. Er erhält nur ein
versioniertes Runtime-Paket mit der für seinen Auftrag erlaubten Struktur:

```text
bin/msr
manifest.json
release.json
schemas/
profiles/<profil>/
components/<ausgewählte-komponente>/
```

`scripts/build-release.sh` baut dieses Paket aus einer Allowlist. `.git`, `docs/`, `tests/`, andere
Profile und nicht ausgewählte Komponenten werden nicht übertragen. Der lokale Bundle-Smoke-Test
prüft außerdem, dass MSR ohne `.git` arbeiten kann.

## Sicherheitsfluss

```text
MSO/Toolhub erzeugt Auftrag
  → einmaliges Ticket + Profil + Release-ID in cloud-init
  → Bootstrap startet auf dem Server
  → Provisioning-Broker prüft Ticket und Auftrag
  → Broker liefert nur erlaubte Paket-URLs und SHA-256
  → Bootstrap lädt Pakete und prüft jede SHA-256
  → MSR prüft Manifest-Version, Manifest-SHA und Commit aus release.json
  → nur registrierte Profil-Komponenten werden ausgeführt
```

Das Ticket ist keine GitHub-Berechtigung. Es autorisiert nur den einmaligen, eng begrenzten
Provisioning-Auftrag. Der Server akzeptiert keine freien Shell-Befehle und keine frei übergebenen
Dateipfade.

## Noch offene Entscheidungen

1. Persistenz für Ticket-Hash, Ablaufzeit und `used_at` (separate Toolhub-Tabelle oder kurzlebiger
   Secret-/Job-Store).
2. GitHub-App mit `Contents: Read` bleibt nur nötig, solange der Broker private Release-Pakete aus
   GitHub erzeugt. Alternativ werden die fertigen Pakete ausschließlich aus Codehangar ausgeliefert.
3. Ob wir ein Gesamtpaket je Profil oder getrennte Core-/Profil-/Komponentenpakete veröffentlichen.
4. Secret-Ausgabe für spätere Automation (Google/Redtrack) bleibt vollständig getrennt vom Runtime-
   Release und wird nicht über den öffentlichen Artefakt-Download ausgeliefert.

## Arbeitsregel

Git ist Entwicklungs- und Veröffentlichungsquelle. Der Server bekommt nur signierte bzw. per SHA
gepinnt veröffentlichte Artefakte. Der neue Bootstrap wird erst nach erfolgreichem Bundle-Smoke-Test
und dokumentierter Broker-Prüfung als neue Version veröffentlicht.
