# Speaker recognition: plan and status

Scripta tells the voices in a recording apart and learns who they are. After a few
meetings it names people on its own ("Max"); before that it suggests ("Max?").
Everything runs on the Mac; voice profiles never leave it.

## Steps

| # | Step | What it delivers |
|---|------|------------------|
| A | Speed and heat | Microphone track is only split when needed; diarization runs in parallel with speech recognition; honest progress |
| S1 | Separate voices | "Speaker 1", "Speaker 2" … per voice; rename, assign and merge speakers (done) |
| S2 | Voice library | People with voice samples, suggestions and automatic names, assignment sheet with listening, "People" settings, opt-in, delete all |
| S3 | Calibration | "Detect again with N speakers", score logging to tune thresholds on real meetings |
| W | Mac + Windows office app | Separate project; see the roadmap below |

### A – Speed and heat

- Measured (optimized build, M5 Pro, 60 min audio): speech recognition 7 s, diarization 16 s per track.
- Microphone track in meetings: only diarized when the setting "Several people at the microphone" is on,
  or automatically when the system track is (nearly) silent, i.e. an in-person meeting recorded in meeting mode.
  Saves half of the diarization work in online meetings.
- Diarization of a track runs in parallel with its transcription.
- Progress weights match the measured durations.
- Diarization runs on the Neural Engine and CPU only (no GPU): same speed, less heat.

### S2 – Voice library

- Separate SwiftData store `Voices` (people, voice samples, the voice of each transcript speaker), so the
  biometric data stays apart from the library and can be deleted in one step. No library migration needed.
- Matching: mean of the top 3 cosine similarities between a speaker's voice and a person's samples;
  exclusive assignment per transcript.
  - Automatic name: score ≥ τ_auto, clear margin to the second-best person, the person has ≥ 3 confirmed samples,
    the speaker talked ≥ 10 s.
  - Suggestion ("Max?"): score ≥ τ_suggest.
  - Otherwise unknown ("Speaker 2").
- Learning: naming a speaker adds its voice as a sample (if it talked ≥ 5 s); automatic names add samples too,
  corrections move them. At most 40 samples per person, near-duplicates are dropped first.
- UI: banner "3 voices – assign" in the recording; sheet with each speaker's color, share of speech, a sample
  sentence, ▶︎ to listen, a name field with known people and the suggestion, "guest – don't remember".
- Settings tab "People": opt-in "Recognize voices" (off by default, explains that voice profiles are biometric
  data), list of people with sample count, rename, delete, "Delete all voice profiles".

### S3 – Calibration

- "Detect again with N speakers" re-transcribes the recording with a fixed number of speakers.
- Scores and margins are logged (private) to tune τ_auto and τ_suggest on real meetings.
- Rule: rather a suggestion than a wrong automatic name.

### W – Office app for Mac and Windows (roadmap)

- Separate project. Scripta (SwiftUI, CoreML, Core Audio taps) cannot run on Windows.
- First a 1–2 day spike on a typical office laptop: fork of Meetily (MIT, Tauri 2 + Rust, Mac + Windows,
  Parakeet via ONNX, microphone + system audio). Check build, Teams capture, speed, heat, code quality.
- Speech stack: sherpa-onnx (Parakeet TDT v3 int8, pyannote segmentation, WeSpeaker embeddings); port the
  matching logic and thresholds from Scripta.
- Set expectations with every user (state it in onboarding and docs):
  - Names improve with use: each person is named by hand once, then guessed ("?"), and after about three
    confirmed meetings recognized with confidence.
  - Voice separation does not learn by itself: how well it tells people apart depends on the model and the audio
    (similar voices, one shared microphone, compressed calls are hard). Mistakes are corrected by hand (correct the
    number of speakers, merge, move single bubbles) until profile-guided separation exists.
  - Lessons from Scripta to carry over: apply names in the assignment dialog together (swaps must not merge);
    learn only from confirmed names; one voice belongs to one person; merging teaches only if the voice matches.
- Weak laptops: transcribe when plugged in / later, or a central machine that transcribes for everyone
  (weigh against privacy), or smaller models.
- Distribution: Windows code signing or Intune; Mac notarization or MDM.
- Before any office rollout: data protection officer, works council (co-determination for monitoring-capable
  systems), data protection impact assessment, consent of everyone recorded. Voice profiles are biometric data
  (Art. 9 GDPR).

## Status

Updated as work progresses. If work stops, the last entry says where to continue.

- S1 done: diarization, numbered speakers, rename/assign/merge, right-click fixed, GPU off for diarization.
- A done: microphone track only split when needed (setting or silent system track); parallel diarization was
  measured (21 s vs. 22 s per hour, higher memory peak) and dropped; progress weights 30 % / 70 %;
  utility priority dropped (slower, no cooler). One hour online meeting ≈ 30 s on an M5 Pro.
- S2 done: separate `Voices` store (Scripta/Voices), VoiceMatcher (thresholds 0.5 / 0.7, margin 0.1, ≥ 3 confirmed
  samples), learning on naming/merging, assignment sheet with listening ("Wer spricht hier?"), banner, "Max?"
  chips, People settings tab with opt-in and deletion. Real-model check: same synthetic voice across recordings
  0.97 (clean) / 0.88–0.90 (Teams-like), different voices 0.13–0.16. 129 tests green.
- S3 done (code part): "Anzahl korrigieren" in the assignment sheet re-transcribes with an exact number of
  voices (system track in meetings); matching scores go to the private debug log (category "Voices").
  131 tests green. Nothing committed, not installed.
- After the first 4-person test (two people merged into one speaker): per-passage correction "Nur diesen
  Abschnitt ▸ other speaker / new speaker"; a speaker with moved-out passages drops its (mixed) voice sample.
  Fix for whole meetings remains "Anzahl korrigieren". Idea for later: detect mixed speakers automatically from
  the per-chunk embeddings (`exposeChunkEmbeddings`) and offer to split them. 132 tests green.
- User wish: guesses are filled in right away (marked "?", click confirms; banner "N Namen vermutet"); only
  confirmed names teach. 132 tests green.
- Single bubbles: a click on the name above a bubble (or the person button shown on hover) opens "Diese
  Sprechblase gehört zu": other speakers, known people, new speaker – changes only that bubble; plus confirm and
  "Alle von … benennen". 133 tests green.
- Real meetings (2026-10-22, analysed locally):
  - A meeting with 3 remote voices: community-1 and Sortformer independently find the same 3 voices → separation
    works. Wrong guesses came from poisoned profiles: two people held the same sample (swap bug).
  - An 80-minute call with one remote person: both models hear one voice; community-1 still split it into 3
    clusters (over-splitting).
  - Fixed: swapping names in the sheet merged speakers (names are now applied together); merging only teaches if
    the voice sounds like the person; one voice belongs to one person. 135 tests green.
  - Profiles poisoned before the fix should be deleted once in Settings → People and the meeting transcribed again.
- Mac: feature-complete for testing (2026-10-22). Open: user testing, commit, optional features below.
- Proposed next: merge clusters automatically when they all match the same well-known person (≥ 3 confirmed samples,
  score ≥ τ_auto) – fixes "one person split into several speakers" for known people.
- Dropped at the user's request: a People sidebar with photos and uploading audio of people (privacy).
- Idea, not built: profile-guided separation – once colleagues are known, assign each diarization chunk
  (`chunkEmbeddings`) to the closest known person among those in the meeting, so separation improves over time too.
- Next (needs the user, not code):
  1. Install (`Scripts/install.sh --wait`), turn on Settings → People → "Stimmen wiedererkennen", use it in
     5–10 real meetings with the same colleagues. Watch: wrong automatic names (must not happen), missing
     suggestions, people split into several speakers.
  2. Then calibrate `VoiceMatcher` thresholds (Scripta/Voices/VoiceMatcher.swift) and
     `TranscriptBuilder.minimumVoiceSpeech` from what happened.
  3. W: spike on a typical office Windows laptop (needs that laptop); talk to data protection officer and works
     council early.
