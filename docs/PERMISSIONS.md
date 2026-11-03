# Berechtigungen

Sonary fragt Berechtigungen erst an, wenn du ein Modul einschaltest, das sie braucht.

| Modul | Berechtigung | Wofür |
|---|---|---|
| Monitor | keine | Liest CPU, RAM, Netzwerk, Disk, Akku und Sensoren über Systemschnittstellen |
| Monitor (Warnungen, optional) | Mitteilungen | Zeigt Warnungen bei hoher Last, Temperatur, wenig Speicher oder leerem Akku |
| Maus | Bedienungshilfen | Beobachtet und ändert Mausereignisse (Scrollen, Zusatztasten, Klick-Filter). Ohne die Berechtigung startet das Modul nicht; bei Entzug meldet es einen Fehler und bleibt aus |
| Notch | keine (Modul) | Die Insel selbst braucht nichts |
| Notch: Musik | Automation (Music/Spotify) | Abspielen, Pause, Überspringen; macOS fragt beim ersten Klick |
| Notch: Kalender | Kalender (Vollzugriff) | Heutige Termine; wird beim Einschalten des Kalender-Widgets angefragt |
| Notch: Downloads | Ordner „Downloads" | Zeigt die neuesten Dateien; macOS fragt beim ersten Zugriff |
| Zwischenablage | keine | Liest die Zwischenablage, um den Verlauf zu führen; Passwort-Einträge werden übersprungen |
| Zwischenablage: Einsetzen als reiner Text | Bedienungshilfen | Drückt ⌘V für dich |
| Zwischenablage: Finder-Helfer | Automation (Finder) | Pfad kopieren, Terminal öffnen, neue Datei |
| Apps | keine | Aufräumen und Deinstallieren legen Dateien nur in den Papierkorb; Ports über `lsof`, Updates über Homebrew |

Die Zeigerbeschleunigung wird nur geändert, solange das Modul läuft. Der ursprüngliche Wert wird beim Ausschalten, beim Beenden und beim nächsten Start nach einem Absturz wiederhergestellt.

Weitere Module (Maus, Notch, ...) ergänzen diese Tabelle, sobald sie gebaut werden.
