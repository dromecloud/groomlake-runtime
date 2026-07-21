# MSO und öffentliche Runtime-Registry

## Gemeinsame Quelle

`manifest.json` ist die gemeinsame technische Wahrheit für Mission Systems Officer und Mission
Systems Runtime. Es gibt keine zweite manuell gepflegte Komponentenliste im Toolhub.

MSO liest die Datei serverseitig über den Codehangar-ATIS-Handler. Die Browseroberfläche erhält danach
die bereits gelesene und validierte Datenstruktur. Beim Erstellen einer Maschine schreibt MSO diese
drei Werte in den Installationsplan:

```json
{
  "runtime": {
    "manifest_version": "2026.07.21.1",
    "manifest_sha256": "...64 hex characters...",
    "commit": "...40 hex characters..."
  }
}
```

## Prüfung auf dem Server

Cloud-init checkt den angegebenen Commit aus. MSR liest danach `manifest.json` aus genau diesem
Checkout und prüft in dieser Reihenfolge:

1. Manifest ist gültiges JSON und entspricht dem Schema.
2. `manifest_version` entspricht dem Installationsplan.
3. SHA-256 der lokalen Datei entspricht dem Installationsplan.
4. `git rev-parse HEAD` entspricht dem Installationsplan.
4. Erst danach werden Profil und Komponenten installiert.

Jeder Unterschied beendet den Lauf vor dem ersten Installationsschritt.

## Deployment auf Codehangar

Der Deployment-Checkout liegt beispielsweise unter:

```text
/srv/codehangar/groomlake-runtime/
```

Der Pfad ist nicht öffentlich. Der Webserver veröffentlicht ausschließlich den read-only Handler:

```text
/groomlake-runtime/atis.php
```

Der `.git`-Ordner, Profile und Installationsskripte werden nicht über den Webserver freigegeben,
sofern wir nur die MSO-Registry öffentlich benötigen. Der Handler liest intern die Root-Datei `manifest.json` und enthält nur nichtgeheime
Fähigkeits- und Anzeigeinformationen.

## Aktualisierung

Nach jedem freigegebenen Deployment von `main` zeigt der Webserver die neue Datei. MSO lädt sie beim
Öffnen der Seite erneut. Vor dem Absenden einer kostenpflichtigen Serveranlage lädt das Backend die
Datei nochmals und berechnet die SHA-256 erneut, damit eine alte Browseransicht keinen neuen Stand
vortäuschen kann.

Die öffentliche Datei ist damit ein aktueller Katalog, aber kein unbestätigter Freifahrtschein. Für
die Serveranlage werden immer Version, SHA und Commit gemeinsam verwendet.

## Noch im Toolhub umzusetzen

1. `lifecycle_mso_profiles()` durch den serverseitigen ATIS-Manifest-Reader ersetzen.
2. Öffentliche URL und erwartetes Schema serverseitig konfigurieren.
3. Manifest beim Laden und nochmals vor `create_server` abrufen.
4. Profil-/Komponentenauswahl aus dem Manifest statt aus PHP-Hardcoding bauen.
5. Bei Nichterreichbarkeit, ungültigem Schema oder Änderungen fail-closed abbrechen.
