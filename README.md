# Scripta

Local transcription for the Mac. Scripta records voice notes and meetings, imports audio and video files and turns them into text. You can also dictate into any app. Speech recognition runs entirely on your Mac: your audio and text never leave it.

- **Record** voice notes with your microphone
- **Record meetings** with your microphone ("Me") and system audio ("Others") on separate tracks, e.g. for Zoom, Teams or browser meetings
- **Import** audio and video files from the menu or by dragging them into the window
- **Transcribe** with NVIDIA Parakeet, which detects English, German and 23 other European languages automatically
- **Dictate in any app:** hold a shortcut, speak, let go, and the text appears at your cursor
- **Export** as plain text, Markdown, subtitles (SRT, WebVTT) or JSON with timestamps

## Requirements

- A Mac with **Apple silicon** (M1 or later). Intel Macs are not supported.
- **macOS 26** or later
- **Xcode 26** or later, free on the Mac App Store (tested with Xcode 27.1). You don't need an Apple Developer account.
- An internet connection for the build and, once, for the speech model (about 640 MB). After that, Scripta works offline.

There is no prebuilt download yet. You build Scripta from source, which only takes a few minutes.

## Installation

### 1. Set up Xcode

1. Install **Xcode** from the Mac App Store.
2. Open Xcode once and accept the license. You don't need any additional platforms (iOS etc.). You can quit Xcode afterwards.
3. Open **Terminal** (Applications → Utilities → Terminal) and check:

   ```sh
   xcodebuild -version
   ```

   If it prints a version number, you're all set. If you get an error about the "command line tools" instead, select Xcode as your developer directory:

   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

### 2. Clone the repository

In Terminal:

```sh
git clone https://github.com/saibot-strg/scripta.git
cd scripta
```

This puts the source code in a folder called `scripta` in your home folder.

### 3. Build and install

```sh
Scripts/install.sh
```

The script builds Scripta, copies the app to **/Applications** and registers it with Spotlight. The first run also downloads the [FluidAudio](https://github.com/FluidInference/FluidAudio) library, so it takes a few minutes. When it's done, you'll see:

```text
Done: Scripta is in /Applications and can be found with Spotlight.
```

### 4. Launch

Press **⌘ Space**, type "Scripta" and press Return, or open the app from your Applications folder. Because you built it yourself, it opens without a Gatekeeper warning.

## Getting started

### Download the speech model

The first time you transcribe something, Scripta downloads the speech model from Hugging Face (about 640 MB, one time only). You can also do this up front: **Scripta → Settings (⌘,) → Transcription → Download Now**. After that, Scripta doesn't need the internet anymore.

### Permissions

macOS asks for each permission the first time Scripta needs it. For an overview with direct links to System Settings, go to **Settings → Permissions**.

| Permission | Used for | Where in System Settings |
| --- | --- | --- |
| Microphone | Recordings, meetings ("Me"), dictation | Privacy & Security → Microphone |
| System audio | Meetings ("Others") | Privacy & Security → Screen & System Audio Recording |
| Accessibility | Inserting dictated text into other apps | Privacy & Security → Accessibility |

## Usage

### Record

Click **New Recording** (⌘N) in the toolbar. Press **⌘↩** to stop and save the recording. To pause, use the **File** menu. Scripta saves continuously while recording. If it gets interrupted, for example by a crash, the recording is recovered the next time Scripta launches.

### Record meetings

Click **Record Meeting** (⇧⌘N). Scripta records two separate tracks: your microphone as "Me" and your Mac's audio as "Others". The transcript shows the conversation like a chat.

- Use the small arrow next to the button to record either **All System Audio** or **Only One App** (e.g. Zoom, Teams or your browser).
- **Wear headphones.** That keeps the other people's voices out of your microphone, so the tracks stay cleanly separated.

### Import files

Click **Import** (⌘I) or drag audio or video files into the Scripta window.

### Transcribe

Select a recording and click **Transcribe** (⌘T). Press **⇧⌘T** to transcribe everything that's still pending. The language is detected automatically.

To have new recordings and imports transcribed right away, turn on **Settings → General → Transcribe automatically**.

### Dictate in any app

1. Open **Settings → Dictation** and turn on **Dictation in All Apps**.
2. Next to **Insert Text into Other Apps**, click **Allow** and enable Scripta under Accessibility. Without this permission, the text only goes to the clipboard.
3. Put your cursor in any text field, **hold ⌃⌥ Space**, speak and let go. The text appears a split second later.

Good to know:

- You can change the shortcut and the mode (**Hold to Talk** or **Press to Start and Stop**) in the Dictation settings. There's also a field to try it out.
- Dictation works as long as Scripta is running. Under **Settings → General** you can turn on **Open at Login** and the menu bar icon.
- Dictation audio stays in memory only and is never saved.
- macOS doesn't allow inserting text into password fields. In that case the text is on the clipboard.

### Export and share

From a recording's toolbar, by right-clicking it in the list, or via **File → Export**:

- Text (.txt)
- Markdown (.md)
- Subtitles SRT (.srt) and WebVTT (.vtt)
- JSON with timestamps (.json)

Press **⇧⌘C** to copy the transcript to the clipboard.

### Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘N | New recording |
| ⌘↩ | Stop recording |
| ⇧⌘N | Record meeting |
| ⌘I | Import |
| ⌘T | Transcribe selected recording |
| ⇧⌘T | Transcribe all pending |
| ⇧⌘C | Copy transcript |
| ⌘F | Search library |
| Space | Play / pause |
| ⌃⌥ Space (hold) | Dictate in any app |

## Your data

- Recordings, transcripts and the speech model are stored in the app's container:
  `~/Library/Containers/io.github.saibot-strg.Scripta/`
- You can choose a different folder for recordings under **Settings → Recording → Storage Location**. Folders in iCloud Drive or on external drives work too.
- Scripta runs in the macOS App Sandbox. Its only network connection is the one-time download of the speech model.

## Updating

```sh
cd ~/scripta
git pull
Scripts/install.sh --wait
```

With `--wait`, the script builds the new version first, then waits until you quit Scripta (⌘Q), installs the update and opens it. A recording in progress is never interrupted. `--force` quits Scripta without waiting.

After an update, macOS may ask for permissions again. Self-built apps are only signed locally, so macOS treats the new version as a different app.

## Uninstalling

1. Turn off **Open at Login** in the settings and quit Scripta (⌘Q).
2. Delete the app and, if you like, all of its data:

   ```sh
   rm -rf /Applications/Scripta.app
   # Warning: this deletes all recordings, transcripts and the speech model
   rm -rf ~/Library/Containers/io.github.saibot-strg.Scripta
   # Reset permissions
   tccutil reset All io.github.saibot-strg.Scripta
   ```

   If you chose a custom storage location, delete that folder separately.
3. Move the source folder `~/scripta` to the Trash.

## Troubleshooting

**`xcodebuild: error: tool 'xcodebuild' requires Xcode …`**
Xcode isn't selected as your developer directory. Run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

**`You have not agreed to the Xcode license agreements`**
Open Xcode once, or run `sudo xcodebuild -license accept`.

**`Scripta is running. Quit it first …`**
Quit Scripta with ⌘Q, or run `Scripts/install.sh --wait`.

**The "Others" track is silent in a meeting**
Scripta doesn't have permission to record system audio. Allow it under Privacy & Security → Screen & System Audio Recording and start the meeting again. Without the permission, macOS delivers silence instead of an error.

**Dictation doesn't insert any text, or only copies it to the clipboard**
Check that Scripta is turned on under Privacy & Security → Accessibility. After an update, it often helps to remove Scripta there with "–" and allow it again.

**The dictation shortcut doesn't respond**
Another app is already using it. Scripta shows this in the Dictation settings. Pick a different shortcut there.

## For developers

Open `Scripta.xcodeproj` in Xcode and run the **Scripta** scheme. Debug builds use their own bundle ID (`….Scripta.debug`), so their data and permissions stay separate from the installed app.

By default, builds are signed to run locally. With a stable signature, permissions persist across builds. To set one up, copy `Config/Local.xcconfig.template` to `Config/Local.xcconfig` and enter your team ID. A free Apple ID in Xcode is enough. `Local.xcconfig` is in `.gitignore` and never ends up in the repository.

## Acknowledgments

- Speech recognition: [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Scripta uses the [CoreML conversion by FluidInference](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml).
- [FluidAudio](https://github.com/FluidInference/FluidAudio) by FluidInference, Apache License 2.0
