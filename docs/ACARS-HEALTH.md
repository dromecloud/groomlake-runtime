# ACARS Health Reporter

Der Runtime-Baustein `health` ist Bestandteil des Iron-Bird-Profils und wird
bei jedem neuen MSO-Bootstrap automatisch installiert. Er meldet nur
strukturierte Zustände an den Groomlake-Tower:

- `status`: `pending`, `running`, `complete`, `failed` oder `stale`
- aktuelle Aufgabe, Sequenznummer, Profil, Bootstrap-/Manifest-/Runtime-Version
- begrenzte Checks und Fehlercodes, niemals Rohlogs oder freie Befehle

Beim Erstellen eines MSO-Servers erzeugt der Lifecycle-Core ein zufälliges
64-stelliges Health-Token. Cloud-init übergibt es einmalig an MSO. Die Runtime
legt es root-only in `/etc/groomlake/health.env` ab; Supabase speichert nur den
SHA-256-Hash. Ein systemd-Timer startet den Reporter alle 60 Sekunden und
meldet über HTTPS an `groomlake-health.php`.

Der Tower liest die Zustände ausschließlich owner-authentifiziert. Ein
fehlgeschlagener Pflicht-Check macht den Server rot (`FAILED`); fehlende oder
zu alte Meldungen werden als `STALE`/`HOLDING` sichtbar. Dieser Kanal ist
bewusst nur Server → Tower. Steueraufträge, Shell-Befehle und Log-Streaming
gehören in einen späteren, separat signierten Dispatcher.
