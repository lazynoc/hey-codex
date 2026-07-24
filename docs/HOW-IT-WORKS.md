# How Hey Codex works

This document explains the product boundary, the native macOS bridge, and the design decisions behind it.

## Explain it to a five-year-old

Codex already knows how to listen and type.

But Codex does not know when you call its name.

Hey Codex is a tiny friend sitting in the Mac's menu bar. Its only job is:

1. Hear **“Hey Codex.”**
2. Stop using the microphone.
3. Tap Codex's hidden dictation button for you.
4. Remember where your typing cursor was.
5. When you press the stop shortcut (**Control+Option+D**), tell Codex to stop.
6. Put the cursor back so Codex can place the words in the right spot.

Or you can say **“Hey Jarvis”** to open or close Codex Voice Chat.

Hey Codex does not write the words itself. Codex still does the hard work.

## The real product boundary

Hey Codex only owns the wake phrases and the shortcut bridges into Codex.

Codex owns:

- audio recording after the wake phrase
- transcription
- native recovery history
- final insertion at the cursor

Hey Codex does not own:

- prompt transcription
- clipboard-based insertion
- “send it” detection
- automatic submission
- a server or API

That boundary is what keeps the app small and useful.

## Two wake phrases

The listener matches every enabled wake phrase in the same on-device recognition stream and reports which one was heard:

- **"Hey Codex"** starts native dictation at the cursor (the full flow below).
- **"Hey Jarvis"** sends Codex's own **Voice chat** hotkey (the `realtimeVoice` binding in `~/.codex/keybindings.json`). Because that hotkey is a toggle, Hey Codex resumes wake listening right after sending it — saying the phrase again ends the chat hands-free. No focus capture, stop bridge, or transcript watching is involved.

## The complete dictation flow

```text
User says "Hey Codex"
        |
Apple Speech recognises only the wake phrase
        |
Hey Codex releases the microphone for 700 ms
        |
Hey Codex captures the current app and focused text element
        |
Hey Codex triggers Codex's native global toggle
        |
Codex records and transcribes
        |
User presses the stop shortcut (default Control+Option+D)
        |
Hey Codex triggers the native stop and restores the captured cursor
        |
Codex inserts the transcript and saves native history
        |
Hey Codex resumes wake listening
```

## Why this was harder than it looked

Codex has two dictation surfaces:

| Surface | Command | Scope | What it does |
| --- | --- | --- | --- |
| Composer dictation | `composer.startDictation` | Codex app only | Opens the mic inside the Codex composer. |
| Global dictation | `globalDictationToggle` | macOS global | Dictates at a desktop cursor and uses the native dictation indicator. |

The global shortcut is not enough by itself. When Codex is already focused, Codex deliberately routes that command to the in-app composer mic.

Hey Codex works around that native choice:

1. Capture the original application and Accessibility-focused element.
2. Briefly focus a transparent 1×1 Hey Codex helper window positioned off-screen.
3. Trigger Codex's native global toggle while Codex is not focused.
4. Hide the helper after a brief handoff and restore the original application, window, and focused element.

The same detour is used when stopping a global session while Codex is focused.

## Why the stop key is different

Hey Codex reads the user's `globalDictationToggle` from Codex's `~/.codex/keybindings.json` at the start of every session. It parses the configured key, sends that exact native shortcut, and remembers it for the matching stop—even if the user changes the Codex setting while dictation is active. The menu watches the file and shows the detected shortcut.

The configured toggle can collide with Codex's composer command when Codex is frontmost. So the user-facing stop key is a separate fixed shortcut: **Control+Option+D**.

Hey Codex registers the stop shortcut as a real macOS global hotkey only while native dictation is active. The event is consumed, so it does not type a stray control character into the target document. Hey Codex then sends the remembered native Codex toggle through the correct desktop route. If the Codex toggle also uses Control+Option+D, Hey Codex refuses to start dictation and asks you to change the Codex setting because the hotkey would swallow the toggle.

If the stop key is not pressed, Hey Codex automatically stops native dictation after a configurable safety timeout (10, 20, or 30 minutes; 10 by default), restores the cursor, and lets Codex finish the transcript.

Optionally, **Stop after silence** (Settings > General) stops dictation hands-free once the microphone level stays below a quiet threshold for 10, 20, or 30 seconds. It is off by default. Hey Codex meters loudness for this feature but does not transcribe or save that meter audio. A spoken stop phrase was deliberately rejected because Codex would type the phrase into the transcript.

The active native-session marker, history baseline, start time, and exact shortcut are persisted. If Hey Codex relaunches while Codex is still recording, it restores the stop hotkey and continues the remaining safety timer instead of forgetting the session.

## Cursor restoration

Starting native dictation was only half the product. Codex pastes its finished transcript into whichever field owns focus at completion.

An earlier version used Finder for the routing detour. It visibly flashed Finder
over the user's work and could leave Finder focused for too long. The current
version uses an invisible helper window instead. It holds focus for only 60 ms
after the start shortcut and 20 ms after the stop shortcut.

The current version stores:

- the original `NSRunningApplication`
- the original Accessibility-focused window
- the original macOS `AXFocusedUIElement`

On stop it activates only the captured app and raises only the captured window, rather than bringing every window in that app forward. It then restores the exact Accessibility element before Codex performs its paste. After 80 ms it verifies the target again and uses System Events only if normal activation did not succeed.

## Why there are two menu-bar indicators

The ear or waveform is Hey Codex's own status item. The orange microphone indicator is rendered and controlled by macOS whenever an app uses the microphone. Hey Codex cannot merge with or suppress that system privacy indicator.

Continuous hands-free wake listening keeps Apple Speech connected to the microphone, so the orange indicator remains visible while listening is enabled. Turning listening off releases the microphone and removes the indicator. If another app is also using the microphone, macOS may continue showing its single system indicator. [Apple describes the indicator in its macOS menu-bar documentation](https://support.apple.com/guide/mac-help/mchlp1446/mac).

## Microphone handoff

Apple Speech listens only for the wake phrase. It must release the microphone before Codex starts recording.

The current handoff waits 700 ms after ending the Apple Speech task and audio tap. This prevents Codex from capturing the tail of “Hey Codex.”

The wake parser also rejects the incomplete partial transcript **“Hey code.”** Earlier, that partial fired before the user had finished saying “Codex,” which caused the native transcript to contain the wake phrase.

## Completion and recovery

The main completion signal is a change to:

```text
~/.codex/transcription-history.jsonl
```

Hey Codex watches that file (and Codex's `keybindings.json`) with kernel file events instead of polling, so completion and shortcut changes are detected promptly without a polling loop.

After native history changes, Hey Codex waits briefly for Codex to release the microphone and then resumes wake listening.

The registered stop hotkey also gives the app a known stop event. If history is slow or the transcript is empty, a short fallback restores wake listening instead of waiting forever.

## Permissions

| Permission | Why it is needed |
| --- | --- |
| Microphone | Hear the local wake phrase. |
| Speech Recognition | Recognise the wake phrase on-device. |
| Accessibility | Trigger shortcuts and restore the exact focused element. |
| Automation | Use System Events only as a fallback when normal focus restoration fails. |

Hey Codex has no Full Disk Access, backend, analytics, account, or API key.

## Signing lesson

macOS permissions are tied to an app's signed identity. Rebuilding with changing ad-hoc identities can make Accessibility access look enabled while the running binary is treated as different.

Local builds use the first available Apple Development identity and fall back to ad-hoc signing only when no development identity exists.

Public builds use the minimum Hardened Runtime entitlements needed for audio input and Apple Events, require Developer ID signing, notarise the DMG, staple the ticket, and verify Gatekeeper before publishing.

## Bugs we found in order

1. We first tried to make Hey Codex act like a dictation app. Wrong product. It should only bridge into Codex's native dictation.
2. We activated Codex before sending the shortcut. That guaranteed the bottom composer mic.
3. We reused a shortcut that Codex could route to the composer when Codex was frontmost.
4. We accepted the partial wake transcript “Hey code,” so native dictation captured the wake phrase.
5. The first stop listener was not reliable enough. We replaced it with a registered macOS global hotkey.
6. Native dictation stopped, but Finder still owned focus. History was correct and the text disappeared. We now capture and restore the exact target.

## Release tests

A build is not ready because the microphone indicator appeared. It must pass the whole flow.

### Normal desktop test

1. Focus a TextEdit document.
2. Say “Hey Codex.”
3. Speak a unique sentence.
4. Press the stop shortcut (Control+Option+D).
5. Confirm TextEdit stayed the target.
6. Confirm the sentence appears in TextEdit.
7. Confirm the same sentence appears in Codex native history.

### Forced focus-detour test

1. Start with TextEdit focused.
2. Start global dictation and speak.
3. Move focus to Codex before stopping.
4. Press the stop shortcut (Control+Option+D).
5. Confirm Hey Codex restores TextEdit.
6. Confirm Codex pastes into the original TextEdit cursor.

The final forced-detour proof inserted:

> Original cursor restored before paste.

### Two-cycle test

Run the full wake, dictate, stop, and insert flow twice without restarting Hey Codex. This proves wake listening resumes correctly.

## Current source map

- `VoiceController.swift`: the state machine — phases, microphone handoff, completion, and recovery.
- `VoiceDependencies.swift`: injectable seams (permissions, trigger, listener, session store, file watchers) so the state machine is fully testable.
- `WakeWordListener.swift`: continuous on-device speech recognition and locale selection. Recognition sessions rotate with a one-second overlap on a running microphone tap to minimise missed wake phrases.
- `AudioBufferRouter.swift`: thread-safe fan-out from the single microphone tap to the overlapping recognition sessions.
- `SilenceDetector.swift` and `MicrophoneLevelMeter.swift`: the optional hands-free silence stop — RMS level metering plus the once-only silence-window decision.
- `PhraseParser.swift`: wake phrase and safe aliases.
- `NativeDictationTrigger.swift`: native start and stop routing plus cursor capture and restoration.
- `StopHotKeyMonitor.swift`: the temporary global stop hotkey.
- `StopShortcut.swift`: stop-shortcut parsing, Carbon modifier mapping, and Codex-shortcut collision detection.
- `FileChangeWatcher.swift`: kernel file-event watching for history and keybindings.
- `LaunchAtLogin.swift`: SMAppService wrapper for the start-at-login toggle.
- `SoundCues.swift`: optional wake/stop sound feedback.
- `TranscriptionHistory.swift`: tolerant tail reader for recent dictations shown in the menu, plus a full read for the history window.
- `DictationStats.swift` and `DictationStatsModel.swift`: running word/dictation totals folded idempotently from Codex's history file; persisted as a small JSON aggregate in `~/Library/Application Support/Hey Codex/`.
- `HistoryWindowView.swift`: the searchable all-history window.
- `UpdateChecker.swift`: version comparison and the GitHub latest-release check.
- `AudioInputDevices.swift`: CoreAudio input enumeration for the microphone picker.
- `MenuBarView.swift`: small status, settings, and recovery UI.
- `scripts/build-app.sh`: release build and stable signing.
- `scripts/install.sh`: local installation.
