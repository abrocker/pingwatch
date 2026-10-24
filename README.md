# PingWatch

Eine native Mac-App, die Hosts und Webseiten überwacht und sich bemerkbar macht, wenn sich etwas ändert: Ton, Systembanner und eine Oberfläche im Stil von [PingPlotter](https://www.pingplotter.com) mit Route, Latenz-Graph und Timeline.

Geschrieben in Swift und SwiftUI, ohne Fremdbibliotheken. Die Oberfläche nutzt Liquid Glass von macOS 26.

## Funktionen

**Überwachen**
- **Ping:** IP-Adressen und Hostnamen (IPv4 und IPv6) werden per `ping` geprüft.
- **Web:** Eine Seite wird per HTTP oder HTTPS geladen. Als „OK“ gilt ein 2xx-Status. Die App zeigt Statuscode und Ladezeit.
- **Art der Prüfung bei der Eingabe wählbar:** Ping oder Web. Bei Web reicht `example.com`, daraus wird `https://example.com`. Bei Ping wird aus `https://www.example.com/seite` der Host `www.example.com`.
- **Intervall pro Host:** Standardwerte für Ping (5 s) und Web (30 s) in den Einstellungen, dazu ein eigener Wert pro Host in der Tabelle.
- **Verlauf der Eingaben:** Die letzten 50 Hosts und Web-Adressen werden gespeichert und beim Tippen vorgeschlagen.

**Melden**
- **Ton:** Beim Wechsel zu „erreichbar“ spielt die App PING, beim Wechsel zu „nicht erreichbar“ DOWN, jeweils in einstellbarer Anzahl (1 bis 20) und mit frei wählbarem Systemton. Beim Auswählen eines Tons hörst du ihn einmal.
- **Fehlversuche bis DOWN:** Ein Host gilt erst nach einer einstellbaren Zahl fehlgeschlagener Prüfungen in Folge als nicht erreichbar (Standard 2), damit ein einzelner verlorener Ping keinen Alarm auslöst.
- **Systembanner:** Bei „wieder erreichbar“, „nicht erreichbar“ und bei Web-Hosts auch, wenn sich der HTTP-Status ändert, zum Beispiel 200 → 503.
- **Mute-Knopf** (⇧⌘M): schaltet die Alarmtöne stumm. Banner bleiben aktiv.

**Analysieren**
- **Hosttabelle** mit aktueller, durchschnittlicher, minimaler und maximaler Antwortzeit, Verlust in Prozent, HTTP-Status und einem Mini-Verlauf.
- **Trace Graph:** Für den gewählten Host wird die Route per Traceroute ermittelt. Jede Zeile ist ein Router mit IP, Name, Ø, Min, aktuell und Verlust. Daneben zeigt ein Graph pro Zeile den Bereich von Min bis Max, den Verlust und den Durchschnitt. Eine Linie verbindet die Durchschnitte der Hops, sodass man sieht, welcher Hop wie viel Latenz dazubringt.
- **Timeline:** Latenz des gewählten Hops oder des Ziels über die Zeit. Verlorene Pings erscheinen als rote Linien. Die Höhe lässt sich verstellen oder die Timeline ausblenden.
- **Zeitraum:** 5 Minuten, 15 Minuten, 1 Stunde oder alles.
- **Farbzonen** wie bei PingPlotter: grün bis 100 ms, gelb bis 200 ms, rot darüber.

Hosts, Einstellungen, die Auswahl und die Eingabe-Historie bleiben nach einem Neustart erhalten. Die Messwerte selbst werden nicht gespeichert.

## Voraussetzungen

- macOS 26 oder neuer
- Xcode mit Swift-Toolchain (entwickelt und getestet mit Xcode 27.1, Swift 6.4)

## Bauen und starten

```bash
./build_app.sh
open build/PingWatch.app
```

Das Skript baut die App im Release-Modus, legt das App-Bundle mit Icon in `build/PingWatch.app` an und signiert es ad hoc. Beim ersten Start fragt macOS, ob PingWatch Mitteilungen senden darf. Ohne Erlaubnis arbeitet die App weiter, nur die Banner fehlen. Die Einstellungen zeigen dann einen Hinweis.

Tests laufen mit:

```bash
swift test
```

## Bedienung

1. Oben **Ping** oder **Web** wählen, Adresse eintragen, mit Enter oder **Hinzufügen** bestätigen. Mehrere Einträge lassen sich mit Leerzeichen oder Komma trennen.
2. In der Tabelle einen Host anklicken: Darunter erscheinen Route und Timeline.
3. In der Route einen Hop anklicken, um dessen Timeline zu sehen. Die Zeile „Round Trip“ ist das Ziel selbst, bei Web-Hosts die HTTP-Ladezeit.
4. Das Zahnrad öffnet die Einstellungen: Standard-Intervalle, Töne, Wiederholungen, Fehlversuche bis DOWN und die Systembanner.

## Wie es funktioniert

- **Ping** ruft `/sbin/ping` auf (`ping6` bei IPv6), mit einer Zeitüberschreitung von zwei Sekunden.
- **Web** lädt die Seite per `URLSession` (GET, Weiterleitungen werden verfolgt, Zeitüberschreitung 10 s). Jede Prüfung baut eine neue Verbindung auf, sodass DNS- und TLS-Zeit in der Ladezeit stecken. Geladen wird nur das HTML, keine Bilder oder Skripte.
- **Route** nutzt `/usr/sbin/traceroute`. Der Hop-Bereich wird in kleine Teile zerlegt, die gleichzeitig laufen. Die Messung dauert dadurch meist ein bis drei Sekunden statt bis zu 20. Gemessen wird nur für den gerade gewählten Host. Router, die nicht auf Traceroute antworten, erscheinen als „keine Antwort“. Das ist normal und bedeutet nicht, dass die Verbindung gestört ist.
- **Oberfläche** wird höchstens viermal pro Sekunde aktualisiert, auch wenn viele Hosts gleichzeitig messen. Diagramme zeichnen höchstens etwa 400 Punkte, die Mini-Verläufe in der Tabelle sind eine einfache Canvas-Zeichnung.

## Projektstruktur

```
Package.swift
build_app.sh            baut build/PingWatch.app
Resources/              Info.plist, AppIcon.icns
tools/make_icon.swift   erzeugt das App-Icon
Sources/
  PingCore/             Logik ohne Oberfläche: Ping, Traceroute, Web-Prüfung,
                        Statuswechsel, Statistik, Historie (mit Unit-Tests)
  PingWatch/            SwiftUI-App: Oberfläche, Monitor, Töne, Banner
Tests/PingCoreTests/    Unit-Tests für PingCore
```

## Hinweise

- Die App läuft **ohne App-Sandbox**, weil sie `ping` und `traceroute` als Programme startet.
- Für Web-Prüfungen per `http://` erlaubt die Info.plist unverschlüsselte Verbindungen (`NSAllowsArbitraryLoads`).
- Fremde Webseiten solltest du nicht im Sekundentakt abrufen. Der Standard für Web ist deshalb 30 Sekunden.
- Die gespeicherten Daten liegen in den Benutzereinstellungen unter `local.pingwatch.app`. Zurücksetzen geht mit:

  ```bash
  defaults delete local.pingwatch.app
  ```

## Für Entwickler

- **Icon neu erzeugen:**

  ```bash
  swift tools/make_icon.swift Resources/AppIcon.iconset
  iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
  ```

- **Last testen:** Mit der Umgebungsvariable `PINGWATCH_PREFILL=3600` startet die App mit simulierten Messwerten (eine Stunde Verlauf pro Host und zehn Hops pro Route). So lässt sich die Oberfläche unter Last prüfen:

  ```bash
  open --env PINGWATCH_PREFILL=3600 build/PingWatch.app
  ```

- Ein Test der Web-Prüfung startet einen lokalen Webserver mit `python3` und wird übersprungen, wenn `python3` fehlt.

## Lizenz

Apache License 2.0, siehe [LICENSE](LICENSE).
