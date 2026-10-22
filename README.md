# Scripta

Local transcription for the Mac. Scripta records voice notes and meetings, imports audio and video files and turns them into text. You can also dictate into any app. Speech recognition runs entirely on your Mac: your audio and text never leave it.

- **Record** voice notes with your microphone
- **Record meetings** with your microphone ("Me") and system audio ("Others") on separate tracks, e.g. for Zoom, Teams or browser meetings
- **Import** audio and video files from the menu or by dragging them into the window
- **Transcribe** with NVIDIA Parakeet Ultra, which detects English, German and 23 other European languages automatically
- **Tell speakers apart:** each voice in a meeting or recording gets its own label ("Speaker 1", "Speaker 2" …), which you can rename
- **Dictate in any app:** hold a shortcut, speak, let go, and the text appears at your cursor
- **Organize** recordings in folders: create them in the sidebar and drag recordings or audio files onto them; swipe left on a recording to delete it
- **Export** as plain text, Markdown, subtitles (SRT, WebVTT) or JSON with timestamps

## Requirements

- A Mac with **Apple silicon** (M1 or later). Intel Macs are not supported.
- **macOS 26** or later
- An internet connection, once, for the speech model (about 640 MB). After that, Scripta works offline.

Building from source also needs **Xcode 26** or later, free on the Mac App Store. You don't need an Apple Developer account.

## Installation

### Option 1: Download (recommended)

1. Go to the [latest release](https://github.com/saibot-strg/scripta/releases/latest) and download **Scripta-x.y.z.dmg**.
2. Open the DMG and drag **Scripta** onto the **Applications** folder.
3. Open Scripta from your Applications folder. macOS says it can't verify the app. Click **Done**.
4. Open **System Settings → Privacy & Security** and scroll down to **Security**. Next to "Scripta was blocked to protect your Mac", click **Open Anyway**. Confirm with **Open Anyway** and your password or Touch ID.

Step 4 is needed because Scripta isn't notarized by Apple, which requires a paid developer membership. You only need to do it once per version. Each release is built by [GitHub Actions](.github/workflows/release.yml) directly from the source code in this repository.

To check that your download is intact, compare its checksum with the `.sha256` file attached to the release:

```sh
shasum -a 256 ~/Downloads/Scripta-*.dmg
```

### Option 2: Build from source

#### 1. Set up Xcode

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

#### 2. Clone the repository

In Terminal:

```sh
git clone https://github.com/saibot-strg/scripta.git
cd scripta
```

This puts the source code in a folder called `scripta` in your home folder.

#### 3. Build and install

```sh
Scripts/install.sh
```

The script builds Scripta, copies the app to **/Applications** and registers it with Spotlight. The first run also downloads the [FluidAudio](https://github.com/FluidInference/FluidAudio) library, so it takes a few minutes. When it's done, you'll see:

```text
Done: Scripta is in /Applications and can be found with Spotlight.
```

#### 4. Launch

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

Click **Record Meeting** (⇧⌘N). Scripta records two separate tracks: your microphone as "Me" and your Mac's audio for everyone else. The transcript shows the conversation like a chat.

When transcribing, Scripta tells the voices apart: each remote participant becomes "Speaker 1", "Speaker 2" and so on. Your own voice stays "Me". If other people sit at your Mac with you, turn on **Several People at the Microphone** in Settings → Transcription; in a meeting where no one can be heard online, Scripta does this on its own. To give a speaker a name, right-click one of their passages and choose **Rename**. If one person was split into several speakers, give them all the same name (or one speaker another speaker's name, e.g. "Me") and they are merged. You can turn this off under Settings → Transcription → Speakers.

If two people ended up as one speaker, choose **Correct Number of Others** in the same window to detect the voices again with the right number, or click the name above a single bubble (or the person button that appears when you point at it) to give just that bubble to another speaker.

**Recognize people.** Click **Assign …** above the transcript (or a speaker's name) to listen to each voice and name it. Turn on **Recognize Voices** there or in Settings → People, and Scripta remembers the voices you name: next time it fills in its guess, marked with "?" until you confirm or correct it, and after three confirmations it names the person with confidence. Voice profiles stay on your Mac; Settings → People lists them and deletes them. Ask people before you keep their voice profile.

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
- Scripta runs in the macOS App Sandbox. It connects to the internet for two things only: the one-time download of the speech model, and a daily check on GitHub for a new version. The update check sends no data about your recordings or your usage, and you can turn it off under **Settings → General → Check for updates automatically**.

## Updating

Scripta checks GitHub once a day for a new version. When one is available, a note appears at the bottom of the sidebar and in the menu bar menu. You can also check yourself with **Scripta → Check for Updates …**. Scripta doesn't install updates by itself; the note takes you to the download page.

To get an email for every new version, click **Watch → Custom → Releases** at the top of this repository (requires a GitHub account).

Your recordings and settings are kept when you update.

**Downloaded version:** Download the new DMG from the [latest release](https://github.com/saibot-strg/scripta/releases/latest), quit Scripta (⌘Q) and drag the new version into Applications, replacing the old one. Confirm the first launch with **Open Anyway** again, as described above.

**Built from source:**

```sh
cd ~/scripta
git pull
Scripts/install.sh --wait
```

With `--wait`, the script builds the new version first, then waits until you quit Scripta (⌘Q), installs the update and opens it. A recording in progress is never interrupted. `--force` quits Scripta without waiting.

After an update, macOS may ask for permissions again. Scripta isn't signed with an Apple Developer ID, so macOS treats each new version as a different app.

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
3. If you built from source, move the folder `~/scripta` to the Trash.

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

To publish a release, push a version tag such as `git tag v0.2.0 && git push origin v0.2.0`. The [Release workflow](.github/workflows/release.yml) builds the app with `Scripts/package-release.sh` and attaches the DMG and its checksum to a new GitHub release. You can also run the script locally; release builds are always ad-hoc signed, even if `Local.xcconfig` sets a team.

## Acknowledgments

- Speech recognition: [Parakeet Ultra](https://huggingface.co/moondream/parakeet-ultra) by moondream, a post-training of [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3). Both are licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Scripta uses the [CoreML conversion by FluidInference](https://huggingface.co/FluidInference/parakeet-ultra-coreml).
- Speaker separation: [pyannote speaker-diarization-community-1](https://huggingface.co/pyannote/speaker-diarization-community-1) with the [WeSpeaker ResNet34](https://huggingface.co/pyannote/wespeaker-voxceleb-resnet34-LM) voice embedding, licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Scripta uses the [CoreML conversion by FluidInference](https://huggingface.co/FluidInference/speaker-diarization-coreml).
- [FluidAudio](https://github.com/FluidInference/FluidAudio) by FluidInference, Apache License 2.0
