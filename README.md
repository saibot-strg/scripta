# Scripta

Lokale Transkription für den Mac. Scripta nimmt Sprachnotizen und Meetings auf, importiert Audio- und Videodateien und macht daraus Text. Außerdem kannst du in jeder App diktieren. Die Spracherkennung läuft komplett auf deinem Mac: Audio und Text verlassen ihn nie.

- **Aufnehmen:** Sprachnotizen über das Mikrofon
- **Meetings:** Mikrofon („Ich“) und Systemaudio („Andere“) als getrennte Spuren, z. B. für Zoom, Teams oder Meetings im Browser
- **Importieren:** Audio- und Videodateien per Menü oder einfach ins Fenster ziehen
- **Transkribieren:** mit NVIDIA Parakeet, erkennt Deutsch, Englisch und 23 weitere europäische Sprachen automatisch
- **Diktat in allen Apps:** Tastenkürzel halten, sprechen, loslassen. Der Text erscheint dort, wo der Cursor steht.
- **Exportieren:** als Text, Markdown, Untertitel (SRT, WebVTT) oder JSON mit Zeitstempeln

## Voraussetzungen

- Ein Mac mit **Apple Silicon** (M1 oder neuer). Intel-Macs werden nicht unterstützt.
- **macOS 26** oder neuer
- **Xcode 26** oder neuer, kostenlos im Mac App Store (getestet mit Xcode 27.1). Ein Apple-Developer-Account ist nicht nötig.
- Internet für den Build und einmalig für das Sprachmodell (ca. 640 MB). Danach arbeitet Scripta offline.

Eine fertige App zum Herunterladen gibt es noch nicht. Du baust Scripta selbst aus dem Quellcode, das dauert nur wenige Minuten.

## Installation

### 1. Xcode einrichten

1. Installiere **Xcode** aus dem Mac App Store.
2. Öffne Xcode einmal und bestätige die Lizenz. Zusätzliche Plattformen (iOS usw.) brauchst du nicht. Danach kannst du Xcode wieder schließen.
3. Öffne das **Terminal** (Programme → Dienstprogramme → Terminal) und prüfe:

   ```sh
   xcodebuild -version
   ```

   Steht dort eine Versionsnummer, ist alles bereit. Kommt stattdessen eine Fehlermeldung zu den „Command Line Tools“, stell Xcode als Entwicklerumgebung ein:

   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

### 2. Repository klonen

Im Terminal:

```sh
git clone https://github.com/saibot-strg/scripta.git
cd scripta
```

Damit liegt der Quellcode im Ordner `scripta` in deinem Benutzerordner.

### 3. Bauen und installieren

```sh
Scripts/install.sh
```

Das Skript baut Scripta, legt die App unter **/Programme** ab und meldet sie bei Spotlight an. Beim ersten Mal lädt es zusätzlich die Bibliothek [FluidAudio](https://github.com/FluidInference/FluidAudio) herunter und braucht deshalb ein paar Minuten. Am Ende steht:

```text
Done: Scripta is in /Applications and can be found with Spotlight.
```

### 4. Starten

Drück **⌘ Leertaste**, tipp „Scripta“ und drück Return. Oder öffne die App aus dem Ordner Programme. Weil du sie selbst gebaut hast, startet sie ohne Gatekeeper-Warnung.

## Erste Schritte

### Sprachmodell laden

Bei der ersten Transkription lädt Scripta das Sprachmodell einmalig von Hugging Face (ca. 640 MB). Du kannst das auch vorher erledigen: **Scripta → Einstellungen (⌘,) → Transkription → Jetzt laden**. Danach braucht Scripta kein Internet mehr.

### Berechtigungen

macOS fragt nach jeder Berechtigung, sobald Scripta sie zum ersten Mal braucht. Einen Überblick und direkte Links in die Systemeinstellungen findest du unter **Einstellungen → Berechtigungen**.

| Berechtigung | Wofür | Wo in den Systemeinstellungen |
| --- | --- | --- |
| Mikrofon | Aufnahmen, Meetings („Ich“), Diktat | Datenschutz & Sicherheit → Mikrofon |
| Systemaudio | Meetings („Andere“) | Datenschutz & Sicherheit → Bildschirm- & Systemaudioaufnahme |
| Bedienungshilfen | Diktierten Text in andere Apps einfügen | Datenschutz & Sicherheit → Bedienungshilfen |

## Verwenden

### Aufnehmen

Klick in der Symbolleiste auf **Neue Aufnahme** (⌘N). Mit **⌘↩** beendest du die Aufnahme und speicherst sie. Pausieren kannst du im Menü **Ablage**. Während der Aufnahme wird laufend gespeichert. Wird Scripta unterbrochen, etwa durch einen Absturz, holt die App die Aufnahme beim nächsten Start zurück.

### Meetings aufnehmen

Klick auf **Meeting aufnehmen** (⇧⌘N). Scripta nimmt dann zwei getrennte Spuren auf: dein Mikrofon als „Ich“ und den Ton des Macs als „Andere“. Im Transkript erscheint das Gespräch wie ein Chatverlauf.

- Über den kleinen Pfeil neben dem Button wählst du, ob das **gesamte Systemaudio** oder **nur eine App** aufgenommen wird (z. B. Zoom, Teams oder dein Browser).
- **Trag Kopfhörer:** Dann landet der Ton der anderen nicht zusätzlich in deinem Mikrofon, und die Spuren bleiben sauber getrennt.

### Dateien importieren

Klick auf **Importieren** (⌘I) oder zieh Audio- oder Videodateien einfach ins Scripta-Fenster.

### Transkribieren

Wähl eine Aufnahme aus und klick auf **Transkribieren** (⌘T). Mit **⇧⌘T** transkribierst du alle ausstehenden auf einmal. Die Sprache wird automatisch erkannt.

Wenn neue Aufnahmen und Importe sofort transkribiert werden sollen: **Einstellungen → Allgemein → Automatisch transkribieren**.

### Diktat in allen Apps

1. Öffne **Einstellungen → Diktat** und schalte **Diktat in allen Apps** ein.
2. Klick bei **Text in andere Apps einfügen** auf **Erlauben** und aktiviere Scripta unter Bedienungshilfen. Ohne diese Freigabe landet der Text nur in der Zwischenablage.
3. Setz den Cursor in ein beliebiges Textfeld, **halte ⌃⌥ Leertaste**, sprich und lass los. Der Text erscheint nach einem Sekundenbruchteil.

Gut zu wissen:

- Tastenkürzel und Modus („Gedrückt halten“ oder „Ein-/Ausschalten“) lassen sich in den Diktat-Einstellungen ändern. Dort gibt es auch ein Feld zum Ausprobieren.
- Das Diktat funktioniert, solange Scripta läuft. Unter **Einstellungen → Allgemein** kannst du **Beim Anmelden starten** und das **Symbol in der Menüleiste** einschalten.
- Diktat-Audio bleibt nur im Arbeitsspeicher und wird nicht gespeichert.
- In Passwortfeldern fügt macOS keinen Text ein. Er liegt dann in der Zwischenablage.

### Exportieren und teilen

In der Symbolleiste einer Aufnahme, per Rechtsklick in der Liste oder über **Ablage → Exportieren**:

- Text (.txt)
- Markdown (.md)
- Untertitel SRT (.srt) und WebVTT (.vtt)
- JSON mit Zeitstempeln (.json)

Mit **⇧⌘C** kopierst du das Transkript in die Zwischenablage.

### Tastenkürzel

| Kürzel | Aktion |
| --- | --- |
| ⌘N | Neue Aufnahme |
| ⌘↩ | Aufnahme beenden |
| ⇧⌘N | Meeting aufnehmen |
| ⌘I | Importieren |
| ⌘T | Ausgewählte Aufnahme transkribieren |
| ⇧⌘T | Alle ausstehenden transkribieren |
| ⇧⌘C | Transkript kopieren |
| ⌘F | In der Bibliothek suchen |
| Leertaste | Abspielen / Pause |
| ⌃⌥ Leertaste (halten) | Diktat in jeder App |

## Deine Daten

- Aufnahmen, Transkripte und das Sprachmodell liegen im App-Container:
  `~/Library/Containers/io.github.saibot-strg.Scripta/`
- Den Speicherort für Aufnahmen kannst du ändern: **Einstellungen → Aufnahme → Speicherort**. Ordner in iCloud Drive oder auf externen Platten funktionieren auch.
- Scripta läuft in der App Sandbox von macOS. Die einzige Netzwerkverbindung ist der einmalige Download des Sprachmodells.

## Aktualisieren

```sh
cd ~/scripta
git pull
Scripts/install.sh --wait
```

Mit `--wait` baut das Skript zuerst die neue Version. Dann wartet es, bis du Scripta beendest (⌘Q), installiert sie und öffnet sie direkt. Eine laufende Aufnahme wird also nie abgebrochen. Mit `--force` wird Scripta ohne Nachfrage beendet.

Nach einem Update fragt macOS die Berechtigungen eventuell erneut ab. Der Grund: Selbst gebaute Apps sind nur lokal signiert, und macOS erkennt die neue Version als andere App.

## Deinstallieren

1. Schalte **Beim Anmelden starten** in den Einstellungen aus und beende Scripta (⌘Q).
2. Lösche die App und, wenn du willst, alle Daten:

   ```sh
   rm -rf /Applications/Scripta.app
   # Achtung: löscht alle Aufnahmen, Transkripte und das Sprachmodell
   rm -rf ~/Library/Containers/io.github.saibot-strg.Scripta
   # Berechtigungen zurücksetzen
   tccutil reset All io.github.saibot-strg.Scripta
   ```

   Falls du einen eigenen Speicherort gewählt hast, lösch diesen Ordner separat.
3. Den Quellcode-Ordner `~/scripta` kannst du einfach in den Papierkorb legen.

## Probleme lösen

**`xcodebuild: error: tool 'xcodebuild' requires Xcode …`**
Xcode ist nicht als Entwicklerumgebung eingestellt. Führ `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` aus.

**`You have not agreed to the Xcode license agreements`**
Öffne Xcode einmal oder führ `sudo xcodebuild -license accept` aus.

**`Scripta is running. Quit it first …`**
Beende Scripta mit ⌘Q oder nutze `Scripts/install.sh --wait`.

**Die Spur „Andere“ ist im Meeting stumm**
Scripta fehlt die Berechtigung für Systemaudio. Erlaube sie unter Datenschutz & Sicherheit → Bildschirm- & Systemaudioaufnahme und starte das Meeting neu. Ohne Berechtigung liefert macOS Stille statt einer Fehlermeldung.

**Das Diktat fügt keinen Text ein (oder nur in die Zwischenablage)**
Prüf unter Datenschutz & Sicherheit → Bedienungshilfen, ob Scripta eingeschaltet ist. Nach einem Update hilft es oft, Scripta dort mit „–“ zu entfernen und neu zu erlauben.

**Das Tastenkürzel fürs Diktat reagiert nicht**
Eine andere App nutzt es bereits. Scripta zeigt das in den Diktat-Einstellungen an. Wähl dort ein anderes Kürzel.

## Für Entwickler

Öffne `Scripta.xcodeproj` in Xcode und starte das Schema **Scripta**. Debug-Builds verwenden eine eigene Bundle-ID (`….Scripta.debug`). Ihre Daten und Berechtigungen bleiben dadurch von der installierten App getrennt.

Ohne weitere Einstellungen wird lokal signiert („Sign to Run Locally“). Mit einer festen Signatur bleiben die Berechtigungen über Builds hinweg erhalten. Kopier dafür `Config/Local.xcconfig.template` nach `Config/Local.xcconfig` und trag deine Team-ID ein. Eine kostenlose Apple-ID in Xcode reicht. `Local.xcconfig` ist in `.gitignore` und landet nie im Repository.

## Danksagung

- Spracherkennung: [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), lizenziert unter [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Verwendet wird die [CoreML-Fassung von FluidInference](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml).
- [FluidAudio](https://github.com/FluidInference/FluidAudio) von FluidInference, Apache License 2.0
