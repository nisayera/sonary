# Berechtigungen

Sonary fragt Berechtigungen erst an, wenn du ein Modul einschaltest, das sie braucht.

| Modul | Berechtigung | Wofür |
|---|---|---|
| Monitor | keine | Liest CPU, RAM, Netzwerk, Disk, Akku und Sensoren über Systemschnittstellen |
| Monitor (Warnungen, optional) | Mitteilungen | Zeigt Warnungen bei hoher Last, Temperatur, wenig Speicher oder leerem Akku |
| Maus | Bedienungshilfen | Beobachtet und ändert Mausereignisse (Scrollen, Zusatztasten, Klick-Filter). Ohne die Berechtigung startet das Modul nicht; bei Entzug meldet es einen Fehler und bleibt aus |

Die Zeigerbeschleunigung wird nur geändert, solange das Modul läuft. Der ursprüngliche Wert wird beim Ausschalten, beim Beenden und beim nächsten Start nach einem Absturz wiederhergestellt.

Weitere Module (Maus, Notch, ...) ergänzen diese Tabelle, sobald sie gebaut werden.
