# Groomlake Runtime

Groomlake Runtime enthält die Mission Systems Runtime (MSR), wiederverwendbare Serverkomponenten,
Zonenprofile und deren Validierung. Zielserver laden dieses Repository per Git und checken den von MSO
vorgegebenen Commit aus.

## Struktur

```text
groomlake-runtime/
├── bin/                         ausführbarer MSR-Einstiegspunkt
├── lib/                         gemeinsame Funktionen der MSR
├── components/                  profilübergreifend installierbare Bausteine
├── profiles/                    Zusammensetzung und Konfiguration pro Zone
├── manifest.json              gemeinsame Registry (Quelle)
├── schemas/                     maschinenlesbare Vertrags-Schemas
├── tests/                       Vertrags- und Smoke-Tests
└── scripts/                     Entwicklungsprüfungen
```

## Gemeinsame Manifest-Wahrheit

`manifest.json` ist die technische Registry für MSO und MSR. MSO lädt sie über den öffentlichen
Codehangar-ATIS-Handler (`public/atis.php`) und baut daraus die sichtbaren Profile und
Komponenten. Der Server liest nach dem Git-Checkout dieselbe Datei lokal.

Die Felder haben unterschiedliche Aufgaben:

- `schema_version` beschreibt das Format der JSON-Datei.
- `manifest_version` beschreibt den konkreten fachlichen Inhalt, aktuell `2026.07.23.2`.
- `provisioning.profiles` ist die einzige Quelle für MSO-Image-, Architektur- und Release-Auswahl.
  Stable/Development sind Freigabestufen derselben fest versionierten Bootstrap-Linie; optionale
  Tailscale-/Docker-Schalter und eine Profil-Bootstrap-Kopplung gehören nicht in diesen Vertrag. Jeder
  Bootstrap nennt zusätzlich den exakt ausgecheckten Runtime-Commit.
- `provisioning.bootstrap_functions` beschreibt die gemeinsamen Basisfunktionen des fest versionierten
  Bootstrap-Artefakts. Diese Liste ist von den profilspezifischen `components` getrennt und wird von MSO
  im Release-Detail als eigener Block angezeigt.
- `profiles.<id>.components` enthält die für das Profil freigegebenen Komponenten. Pflichtkomponenten
  werden von MSO automatisch ausgewählt und können nicht abgewählt werden. Optionale Komponenten stehen
  nur dann zur Auswahl, wenn sie zusätzlich in `optional_components` des Profils stehen. Der Server
  akzeptiert ausschließlich diese IDs; freie Skripte, Pfade oder Shell-Befehle sind ausgeschlossen.
- Der Git-Commit identifies den vollständigen Runtime-Stand.
- Die SHA-256 wird von MSO über die geladenen Manifest-Bytes berechnet und im Installationsplan
  mitgegeben.

Eine Manifest-Änderung erhält immer eine neue `manifest_version`. MSO schreibt beim Erstellen in den
Installationsplan Manifest-Version, Manifest-SHA und vollständigen Commit. MSR vergleicht alle drei
Werte vor dem ersten Installationsschritt und bricht bei jeder Abweichung ab.

## Öffentliche Bereitstellung

Der Git-Checkout liegt außerhalb des Document-Roots. Öffentlich erreichbar ist ausschließlich der
read-only ATIS-Handler `public/atis.php`; er liest eine fest verdrahtete Datei aus dem
Repository-Root und akzeptiert weder Pfade noch Befehle. Der `.git`-Ordner wird niemals öffentlich
erreichbar gemacht.

Der Handler liefert nur bei `GET`/`HEAD` JSON, validiert die Mindeststruktur und setzt SHA-256,
ETag sowie Manifest-Version als Header. `public/commit.txt` enthält ausschließlich die geprüfte
40-stellige Git-Commit-ID. Der Handler validiert diese Datei maschinenlesbar und verwendet sie als
`X-Groomlake-Commit`-Header. Eine Erklärung der ID, ihrer Abgrenzung zu Manifest-/Bootstrap-Versionen
und ihrer Verwendung steht in `public/commit-info.txt`. `commit.txt` darf deshalb nicht um Kommentare
oder weitere Zeilen ergänzt werden.

Die öffentliche Datei enthält keine Geheimnisse. Tailscale-Keys, Hetzner-Tokens, SSH-Private-Keys und
produktive Konfigurationen gehören nicht in dieses Repository.

## Ausführungsvertrag

Cloud-init erzeugt den serverindividuellen Installationsplan, checkt den exakten Commit aus und
startet MSR einmalig:

```bash
/opt/groomlake-runtime/bin/msr apply \
  --plan /etc/groomlake/install-plan.json
```

MSR liest danach `manifest.json`, prüft Manifest-Version, SHA-256 und Git-Commit und führt nur
die im Profil und Manifest registrierten Komponenten aus.

## Erster vertikaler Schnitt

```text
Installationsplan
└── Profil ironbird
    ├── Komponente motd
    │   ├── installiert /etc/groomlake/motd.txt
    │   ├── installiert /etc/update-motd.d/10-groomlake-profile
    │   └── prüft Datei und gerenderte Ausgabe
    └── Komponente health
        ├── installiert den ACARS-Health-Reporter
        └── prüft Reporter, Konfiguration und Timer
```

Der lokale Smoke-Test schreibt ausschließlich in ein temporäres Zielverzeichnis. Er führt MSR
zweimal aus und prüft zusätzlich unbekannte Profile sowie einen Manifest-Versionsfehler:

```bash
scripts/check.sh
```

## Veröffentlichen (Pflicht nach jedem Commit, der `manifest.json` ändert)

`public/commit.txt` muss nach jeder inhaltlichen Änderung in einem eigenen Folgecommit auf den
neuen HEAD zeigen (ein Commit kann nicht auf sich selbst verweisen). Wird dieser zweite Schritt
vergessen oder verzögert, liefert ATIS `manifest_version` und `commit` kurzzeitig inkonsistent —
ein echter Frischservertest bricht dann mit „Manifest-Version stimmt nicht mit dem Broker-Plan
ueberein" ab, noch bevor die erste Komponente installiert. Deshalb **immer**, nicht manuell:

```bash
scripts/publish.sh
```

Setzt `commit.txt`, committet, pusht und prüft live gegen ATIS (mit Retry), dass Manifest-Version
und ausgelieferter Commit zusammenpassen. Bricht laut und mit Exit-Code ungleich 0 ab, wenn ATIS
nicht konvergiert — dann keinen Frischservertest starten, bis das behoben ist.

## Ablageregeln

- Eine installierbare Fähigkeit liegt genau einmal unter `components/`.
- Profile kopieren keine Installer, sondern wählen Komponenten und liefern ihre Konfiguration.
- Laufzeitberichte und Rohlogs gehören nicht ins Git.
- Geheimnisse und produktive Zugangsdaten gehören niemals in dieses Repository.

## Sichtbarkeit dieses Repositories

Entscheidung vom 18.09.2026: Dieses Repository wird **öffentlich**. Der Phase-7-Bootstrap holt den
Stand dann direkt über HTTPS am gepinnten Commit, statt ihn per kurzlebigem GitHub-App-Token über
einen Broker zu klonen. Die Integrität hängt weiterhin am gepinnten Commit plus `manifest_sha256`,
die MSR fail-closed erneut prüft — sie hing nie an der Nichtöffentlichkeit des Repositories.

Praktische Folge für alle Beiträge: Die letzte Ablageregel oben ist damit nicht länger nur eine
Konvention, sondern hart. Komponenten erhalten Geheimnisse ausschließlich über Umgebungsvariablen,
die zur Installationszeit injiziert werden (siehe `MSO_HEALTH_TOKEN` in `components/health/` und
`MSO_NOUS_API_KEY` in `components/hermes/`), niemals über Dateien in diesem Repository.

Begründung und Umsetzungsplan stehen in `groomlake/docs/PHASE-7-PROVISIONING.md`.

## Arbeitsverzeichnis in Komponenten

`bin/msr` wechselt vor dem Aufruf einer Komponente **nicht** das Verzeichnis, Skripte erben also das
Arbeitsverzeichnis des Aufrufers — auf einem echten Server typischerweise `/root`, das ein
unprivilegierter Komponenten-Benutzer nicht lesen darf. Wer per `runuser` Rechte abgibt, muss
deshalb Arbeitsverzeichnis und `HOME` explizit setzen (`runuser -u <user> -- env -C <dir>
HOME=<dir> …`). Andernfalls scheitern Prüfungen mit irreführenden Meldungen, obwohl die Installation
korrekt ist — am 17.09.2026 genau so bei den `ai-lab-*`-Komponenten passiert.
