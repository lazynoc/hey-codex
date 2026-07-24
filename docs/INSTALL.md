# Install Hey Codex on a Mac

Hey Codex 1.0.0 is distributed as a Developer ID-signed and Apple-notarised disk image. Building from source remains available for developers and testers.

## What you need

- An Apple-silicon Mac running macOS 14 or newer
- The Codex desktop app
- A Mac that supports on-device Speech Recognition

Hey Codex has no server, account, API key, or third-party runtime.

## Install the signed app

1. Download [Hey Codex 1.0.0](https://github.com/lazynoc/hey-codex/releases/latest/download/Hey-Codex-1.0.0.dmg).
2. Open the DMG.
3. Drag **Hey Codex** to **Applications**.
4. Open **Hey Codex** from Applications.

The app is signed with Developer ID and notarised by Apple, so a normal public download passes Gatekeeper without the unsigned-app warning.

## Build from source instead

### 1. Install current Apple developer tools

Source builds require Xcode 16.3 or newer, or Swift 6.1-compatible Command Line Tools. If you do not already have a current toolchain, open Terminal and run:

```bash
xcode-select --install
```

If tools are already installed, macOS will tell you. Confirm they provide Swift 6.1 or newer with `swift --version`.

### 2. Download and install Hey Codex

```bash
curl -fsSL https://raw.githubusercontent.com/lazynoc/hey-codex/main/scripts/install-latest.sh | zsh
```

This builds the app, installs it at `~/Applications/Hey Codex.app`, opens it, and discards the temporary source. Existing folders such as `~/hey-codex` cannot interfere with it.

To install a newer version later, run the same command again. Settings are preserved; macOS permissions remain only when the signing identity stays stable.

For a completely fresh onboarding and permission test:

```bash
curl -fsSL https://raw.githubusercontent.com/lazynoc/hey-codex/main/scripts/install-latest.sh | zsh -s -- --fresh
```

The build script uses an Apple Development signing identity when one is available. Otherwise it uses ad-hoc signing. Stable signing matters because macOS permissions are tied to the app's identity.

### 3. Configure Codex's native shortcuts

In Codex, open **Settings > Voice** and set **Toggle dictation hotkey** to the shortcut you prefer. **Left Option**, a key combination such as **Control+Shift+D**, and function keys are supported.

Hey Codex reads this setting directly from `~/.codex/keybindings.json`; nothing needs to be copied or hardcoded. The detected shortcut appears in the Hey Codex menu and refreshes when the Codex setting changes.

To use **“Hey Jarvis”**, also configure Codex’s **Voice chat hotkey** on the same page. You can skip the Voice Chat test during setup if you only want dictation.

### 4. Grant macOS permissions

Open the installed Hey Codex copy from Applications (`/Applications` for the DMG or `~/Applications` for a source install). Its first-run Setup Guide checks each requirement and updates it live.

Allow these permissions when macOS asks:

1. **Microphone**: only for hearing the wake phrase.
2. **Speech Recognition**: only for recognising the wake phrase on the Mac.
3. **Accessibility**: for triggering the native shortcut and restoring the original cursor.
4. **Automation**: allow Hey Codex to use System Events as a fallback when restoring the original app and cursor.

You can check them in **System Settings > Privacy & Security**.

If a Privacy & Security pane opens, enable Hey Codex and return to the Setup Guide. Continue once all four rows show **Granted**, confirm the detected Codex shortcuts, then complete the dictation and Voice Chat wake-phrase tests.

The guide closes after completion and can be reopened later from **Settings > General > Help**.

## Use it

1. Keep Codex running.
2. Click wherever you want the final text to appear.
3. Say **“Hey Codex.”**
4. Wait for the desktop dictation indicator.
5. Speak.
6. Press the stop shortcut (**Control+Option+D**) once to stop.
7. Codex finishes the transcript and puts it back at the captured cursor.

Hey Codex does not understand “send it.” It starts native dictation and gives you one reliable stop key. Codex owns the recording, transcription, history, and insertion. A configurable safety limit (10, 20, or 30 minutes; 10 by default) prevents a forgotten session from recording forever. For a hands-free finish, turn on **Stop after silence** in Settings (off by default) and dictation ends on its own after 10, 20, or 30 seconds of quiet.

## Troubleshooting

### It opens the bottom composer mic

Install the latest build. The current version temporarily routes around Codex's in-app branch, starts desktop dictation, and restores the original Codex cursor.

### The stop shortcut does nothing

Quit and reopen Hey Codex. Make sure no other app owns Control+Option+D. The current version registers it as a real macOS global hotkey only while dictation is active.

### The detected Codex shortcut is wrong

Confirm that **Toggle dictation hotkey** is set in Codex settings. Hey Codex follows that setting automatically. If you changed the shortcut while dictation was already active, finish that session first; the next session uses the new setting.

### Dictation stops but no text appears

Make sure Accessibility and Automation access are enabled. The current build captures the original app, window, and focused text element, then restores that exact target before Codex performs its paste.

### It still asks for Accessibility after permission was granted

Quit Hey Codex and open the installed copy from Applications. Do not run a second copy from the DMG or build folder. If needed, remove the old Accessibility entry, add the installed app again, and reopen it.

### The wake phrase is not heard

Check Microphone and Speech Recognition access. Hey Codex requires on-device recognition and refuses to send wake audio to a server.

## Remove it

Run the clean uninstaller:

```bash
curl -fsSL https://raw.githubusercontent.com/lazynoc/hey-codex/main/scripts/uninstall.sh | zsh
```

For a completely fresh onboarding and permission test:

```bash
curl -fsSL https://raw.githubusercontent.com/lazynoc/hey-codex/main/scripts/uninstall.sh | zsh -s -- --purge
```

To preview the full clean reset:

```bash
curl -fsSL https://raw.githubusercontent.com/lazynoc/hey-codex/main/scripts/uninstall.sh | zsh -s -- --dry-run --purge
```

The default command removes Hey Codex from `/Applications` and `~/Applications`. `--purge` also removes Hey Codex preferences, cache, saved stats, and its Accessibility, Automation, Microphone, and Speech Recognition permissions. Both keep any source checkout, Codex settings, and Codex transcription history.
