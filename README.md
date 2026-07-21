# Groomlake Runtime

Groomlake Runtime enthält den Autoloader, wiederverwendbare Serverkomponenten, Zonenprofile und deren
Validierung. Zielserver laden ausschließlich dieses Repository und checken immer einen von Mission
Systems Officer vorgegebenen Commit aus. Es gibt kein unkontrolliertes `git pull` auf einen beweglichen
Branch.

## Struktur

```text
groomlake-runtime/
├── bin/                         ausführbare Runtime-Einstiegspunkte
├── lib/                         gemeinsame Funktionen des Autoloaders
├── components/                  profilübergreifend installierbare Bausteine
│   ├── blackbox-agent/
│   ├── health/
│   ├── motd/
│   ├── git/
│   ├── dns/
│   ├── docker/
│   ├── tailscale/
│   └── hermes/
├── profiles/                    Zusammensetzung und Konfiguration pro Zone
│   ├── ironbird/
│   │   ├── config/
│   │   └── sequences/
│   └── recon/
│       ├── config/
│       └── sequences/
├── schemas/                     maschinenlesbare Vertrags-Schemas
├── tests/
│   ├── contracts/
│   ├── components/
│   ├── profiles/
│   └── smoke/
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

## Aufbaufolge

Die Verzeichnisse sind zunächst bewusst leer. Verträge und ausführbare Dateien werden erst mit einem
funktionalen Verbraucher ergänzt:

1. Schema für Installationsplan, Profil und Komponente festlegen.
2. Minimalen Autoloader bauen.
3. `health`, `motd` und `blackbox-agent` als erste gemeinsame Komponenten umsetzen.
4. Iron-Bird-Profil vollständig durchlaufen lassen.
5. Erst danach weitere Komponenten und das Recon-Profil aktivieren.
