# Groomlake Runtime

Groomlake Runtime enthält die Mission Systems Runtime (MSR), wiederverwendbare Serverkomponenten, Zonenprofile und deren
Validierung. Zielserver laden ausschließlich dieses Repository und checken immer einen von Mission
Systems Officer vorgegebenen Commit aus. Es gibt kein unkontrolliertes `git pull` auf einen beweglichen
Branch.

## Struktur

```text
groomlake-runtime/
├── bin/                         ausführbarer MSR-Einstiegspunkt
├── lib/                         gemeinsame Funktionen der MSR
├── components/                  profilübergreifend installierbare Bausteine
├── profiles/                    Zusammensetzung und Konfiguration pro Zone
│   ├── ironbird/
│   │   ├── config/
│   │   └── sequences/
│   ├── recon/
│   │   ├── config/
│   │   └── sequences/
│   ├── intelligence/
│   │   ├── config/
│   │   └── sequences/
│   └── blackops/
│       ├── config/
│       └── sequences/
├── schemas/                     maschinenlesbare Vertrags-Schemas
├── tests/                       entsteht zusammen mit realen Verbrauchern
└── scripts/                     Entwicklungs- und Repository-Prüfungen
```

## Ablageregeln

- Eine installierbare Fähigkeit liegt genau einmal unter `components/`.
- Profile kopieren keine Installer. Sie wählen Komponenten aus und liefern nur ihre eigene
  Konfiguration, MOTD-Inhalte und Startsequenzen.
- Hat etwas einen eigenen Installations- und Prüfablauf, ist es eine Komponente — auch wenn zunächst
  nur ein Profil sie verwendet.
- `verify`-Logik, die auf dem Zielserver benötigt wird, gehört zur jeweiligen Komponente.
- Entwicklungs-, Vertrags- und Smoke-Tests gehören unter `tests/`.
- Laufzeitberichte und Rohlogs gehören nicht ins Git. Sie werden künftig vom Blackbox-Agenten an den
  Blackbox-Collector übertragen.
- Geheimnisse, private Schlüssel, Tokens und produktive Konfigurationen gehören niemals in dieses
  Repository.

## Ausführungsvertrag

Cloud-init erzeugt den serverindividuellen Installationsplan, checkt den vom Mission Systems Officer
freigegebenen Commit aus und startet MSR einmalig:

```bash
/opt/groomlake-runtime/bin/msr apply \
  --plan /etc/groomlake/install-plan.json
```

Der Installationsplan enthält in der ersten Version ausschließlich Vertragsversion, Lauf-ID und
Profil-ID. MSR führt niemals pauschal Dateien aus einem Verzeichnis aus. `manifest.json` registriert
die erlaubten Profile und Komponenten; das Profilmanifest bestimmt deren Reihenfolge und liefert
die profilbezogene Konfiguration. Jede Komponente installiert und prüft ihr Ergebnis selbst.

## Erster vertikaler Schnitt

Der erste vollständig ausführbare Weg ist bewusst klein:

```text
Installationsplan
└── Profil ironbird
    └── Komponente motd
        ├── installiert /etc/groomlake/motd.txt
        ├── installiert /etc/update-motd.d/10-groomlake-profile
        └── prüft Datei und gerenderte Ausgabe
```

Der lokale Smoke-Test schreibt ausschließlich in ein temporäres Zielverzeichnis. Er führt MSR
zweimal aus, prüft damit die Wiederholbarkeit und stellt sicher, dass ein unbekanntes Profil
abgelehnt wird:

```bash
tests/smoke/msr-motd.sh
```

## Aufbaufolge

Unterordner, Verträge und ausführbare Dateien werden nur zusammen mit einem funktionalen Verbraucher
ergänzt:

1. Schema für Installationsplan, Profil und Komponente festlegen. **Erledigt**
2. Minimalen MSR-Einstiegspunkt `bin/msr` bauen. **Erledigt**
3. `motd` als erste gemeinsame Komponente im Iron-Bird-Profil umsetzen. **Erledigt**
4. Den gleichen Weg auf einem frischen Ubuntu-Server über Cloud-init prüfen.
5. Danach `health` und den späteren Blackbox-Transport einzeln ergänzen.
6. Erst nach realen Verbrauchern weitere Profile aktivieren.
