# Runtime-Registry für Mission Systems Officer

## Ziel

`groomlake-runtime` ist die technische Wahrheit darüber, welche Profile und Komponenten existieren,
wie sie heißen, womit sie kompatibel sind und wie sie zusammengesetzt werden. Mission Systems Officer
(MSO) pflegt keine zweite Komponentenliste von Hand.

MSO entscheidet weiterhin unabhängig, welcher erkannte Runtime-Release als Development oder Stable
freigegeben ist. Ein Merge nach `main` darf deshalb niemals automatisch eine freigegebene
Serverinstallation verändern.

## Drei getrennte Verträge

1. `manifest.json` ist die Quellen-Registry im Runtime-Repository.
2. `profiles/<id>/profile.json` enthält die Zusammensetzung und profilbezogenen Regeln.
3. `release-manifest.json` ist der erzeugte, unveränderliche Snapshot für einen exakten Git-Commit.

`scripts/build-release.sh` löst alle registrierten Verweise auf, prüft die referenzierten Dateien,
erzeugt ein Runtime-Archiv und schreibt dessen SHA-256 in das Release-Manifest. Das Release-Manifest
enthält außerdem die aufgelösten Profil- und Komponentendefinitionen. MSO muss deshalb keine weiteren
Dateien aus dem Repository zusammensuchen.

## Sicherer Ablauf nach einem Merge nach `main`

Der geplante GitHub-Workflow läuft ausschließlich auf einem exakten Commit von `main`:

1. Checkout des Commit-SHA, nicht eines später erneut aufgelösten Branch-Namens.
2. Syntax-, Vertrags- und Smoke-Tests ausführen.
3. `scripts/build-release.sh --commit "$GITHUB_SHA"` ausführen.
4. Archiv, `release-manifest.json` und beide `.sha256`-Dateien unveränderlich veröffentlichen.
5. Das Release-Manifest serverseitig an den MSO-Registry-Endpunkt senden.
6. MSO speichert den neuen Commit zunächst als `detected`, niemals direkt als `development` oder
   `stable`.

Der Import wird mit einem eigenen HMAC-Schlüssel authentifiziert. Der Schlüssel liegt nur als GitHub
Actions Secret und in der serverseitigen Toolhub-Konfiguration. Der Browser, Cloud-init und das
Runtime-Repository erhalten ihn nie. Der Registry-Endpunkt prüft mindestens:

- HMAC über den unveränderten Request-Body;
- Zeitstempel und einmalige Request-ID gegen Wiederholung;
- fest erlaubtes Repository `dromecloud/groomlake-runtime`;
- vollständiges 40-stelliges Commit-SHA;
- Manifest-Schema und alle eindeutigen IDs;
- SHA-256 des Release-Manifests und des Runtime-Archivs;
- dass derselbe Commit niemals nachträglich mit einem anderen SHA gespeichert wird.

## Freigabestatus

Die MSO-Registry führt Releases getrennt vom Runtime-Inhalt:

```text
detected     automatisch erkannt, nicht für Server auswählbar
development bewusst für kontrollierte Frischserver-Tests freigegeben
stable      exakt der getestete Development-Inhalt mit identischer SHA
revoked     gesperrt, nicht mehr für neue Server auswählbar
```

Eine Stable-Promotion erzeugt kein neues Paket. Sie ändert ausschließlich den Freigabestatus des
bereits getesteten Commit- und SHA-Paars.

## Zuständigkeit von MSO

MSO liest für seine Oberfläche ausschließlich einen gespeicherten, freigegebenen Snapshot aus seiner
serverseitigen Registry. Es lädt weder im Browser noch während einer kostenpflichtigen Serveranlage
eine bewegliche `main`-Datei. Neue Releases können in einer Owner-Ansicht als „erkannt, nicht
freigegeben“ erscheinen.

Bei der Serveranlage schreibt MSO Commit, Archiv-SHA, Profil und Komponentenauswahl in den
Installationsplan. MSR akzeptiert daraus nur Einträge, die im zugehörigen Release-Manifest erlaubt
sind.

## Noch umzusetzen im Toolhub-Repository

1. Serverseitigen Runtime-Registry-Speicher und HMAC-geschützten Import-Endpunkt bauen.
2. Die aktuell hart codierte Funktion `lifecycle_mso_profiles()` durch freigegebene Registry-Snapshots
   ersetzen.
3. Development-/Stable-Freigabe als bewusste Owner-Aktion ergänzen.
4. Erst danach den GitHub-Main-Workflow mit dem produktiven Registry-Endpunkt verbinden.

Bis diese vier Punkte umgesetzt und getestet sind, wird kein automatischer Import aktiviert.
