import ApplicationServices
import Foundation

struct CodexShortcut: Equatable, Sendable {
    enum ParseError: LocalizedError, Equatable {
        case empty
        case unsupportedModifier(String)
        case unsupportedKey(String)
        case unsupportedBareKey(String)
        case modifierNeedsKey

        var errorDescription: String? {
            switch self {
            case .empty:
                "Codex global dictation shortcut is empty"
            case let .unsupportedModifier(modifier):
                "Unsupported Codex shortcut modifier: \(modifier)"
            case let .unsupportedKey(key):
                "Unsupported Codex shortcut key: \(key)"
            case let .unsupportedBareKey(key):
                "Codex shortcut \(key) needs a modifier"
            case .modifierNeedsKey:
                "A modifier shortcut must use Left or Right, for example LeftOption"
            }
        }
    }

    enum SendError: LocalizedError {
        case eventCreationFailed

        var errorDescription: String? {
            "Could not create the configured Codex shortcut event"
        }
    }

    let rawValue: String
    let keyCode: CGKeyCode
    let flags: CGEventFlags
    let displayName: String
    let isBareModifier: Bool

    var pressDuration: Duration {
        isBareModifier ? .milliseconds(350) : .milliseconds(35)
    }

    static func parse(_ rawValue: String) throws -> CodexShortcut {
        let cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ParseError.empty }

        let parts = cleaned.split(separator: "+", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !parts.contains(where: \.isEmpty) else { throw ParseError.empty }

        if parts.count == 1, let modifier = sidedModifier(parts[0]) {
            return CodexShortcut(
                rawValue: cleaned,
                keyCode: modifier.keyCode,
                flags: modifier.flag,
                displayName: modifier.displayName,
                isBareModifier: true
            )
        }

        guard let keyName = parts.last else { throw ParseError.empty }
        if genericModifier(keyName) != nil {
            throw ParseError.modifierNeedsKey
        }
        guard let keyCode = keyCode(for: keyName) else {
            throw ParseError.unsupportedKey(keyName)
        }
        if parts.count == 1, !isFunctionKey(keyName) {
            throw ParseError.unsupportedBareKey(keyName)
        }

        var flags: CGEventFlags = []
        var displayModifiers: [String] = []
        for modifierName in parts.dropLast() {
            guard let modifier = genericModifier(modifierName) else {
                throw ParseError.unsupportedModifier(modifierName)
            }
            flags.insert(modifier.flag)
            if !displayModifiers.contains(modifier.displayName) {
                displayModifiers.append(modifier.displayName)
            }
        }

        let displayKey = displayKeyName(for: keyName)
        let displayName = (displayModifiers + [displayKey]).joined(separator: "+")
        return CodexShortcut(
            rawValue: cleaned,
            keyCode: keyCode,
            flags: flags,
            displayName: displayName,
            isBareModifier: false
        )
    }

    func send() async throws {
        guard let keyDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: false
        ) else {
            throw SendError.eventCreationFailed
        }

        keyDown.flags = flags
        keyUp.flags = isBareModifier ? [] : flags
        keyDown.post(tap: .cghidEventTap)
        try? await Task.sleep(for: pressDuration)
        keyUp.post(tap: .cghidEventTap)
    }

    private struct ModifierDefinition {
        let flag: CGEventFlags
        let displayName: String
    }

    private struct SidedModifierDefinition {
        let keyCode: CGKeyCode
        let flag: CGEventFlags
        let displayName: String
    }

    private static func genericModifier(_ name: String) -> ModifierDefinition? {
        switch normalized(name) {
        case "ctrl", "control":
            ModifierDefinition(flag: .maskControl, displayName: "Control")
        case "alt", "option":
            ModifierDefinition(flag: .maskAlternate, displayName: "Option")
        case "shift":
            ModifierDefinition(flag: .maskShift, displayName: "Shift")
        case "cmd", "command", "meta", "super", "cmdorctrl", "commandorcontrol":
            ModifierDefinition(flag: .maskCommand, displayName: "Command")
        default:
            nil
        }
    }

    private static func sidedModifier(_ name: String) -> SidedModifierDefinition? {
        switch normalized(name) {
        case "leftoption", "leftalt":
            SidedModifierDefinition(keyCode: 58, flag: .maskAlternate, displayName: "Left Option")
        case "rightoption", "rightalt":
            SidedModifierDefinition(keyCode: 61, flag: .maskAlternate, displayName: "Right Option")
        case "leftcontrol", "leftctrl":
            SidedModifierDefinition(keyCode: 59, flag: .maskControl, displayName: "Left Control")
        case "rightcontrol", "rightctrl":
            SidedModifierDefinition(keyCode: 62, flag: .maskControl, displayName: "Right Control")
        case "leftshift":
            SidedModifierDefinition(keyCode: 56, flag: .maskShift, displayName: "Left Shift")
        case "rightshift":
            SidedModifierDefinition(keyCode: 60, flag: .maskShift, displayName: "Right Shift")
        case "leftcommand", "leftcmd", "leftmeta":
            SidedModifierDefinition(keyCode: 55, flag: .maskCommand, displayName: "Left Command")
        case "rightcommand", "rightcmd", "rightmeta":
            SidedModifierDefinition(keyCode: 54, flag: .maskCommand, displayName: "Right Command")
        case "function", "fn":
            SidedModifierDefinition(keyCode: 63, flag: .maskSecondaryFn, displayName: "Function")
        default:
            nil
        }
    }

    private static func keyCode(for name: String) -> CGKeyCode? {
        switch normalized(name) {
        case "a": 0
        case "s": 1
        case "d": 2
        case "f": 3
        case "h": 4
        case "g": 5
        case "z": 6
        case "x": 7
        case "c": 8
        case "v": 9
        case "b": 11
        case "q": 12
        case "w": 13
        case "e": 14
        case "r": 15
        case "y": 16
        case "t": 17
        case "1": 18
        case "2": 19
        case "3": 20
        case "4": 21
        case "6": 22
        case "5": 23
        case "=", "equal", "equals": 24
        case "9": 25
        case "7": 26
        case "-", "minus": 27
        case "8": 28
        case "0": 29
        case "]", "rightbracket": 30
        case "o": 31
        case "u": 32
        case "[", "leftbracket": 33
        case "i": 34
        case "p": 35
        case "return", "enter": 36
        case "l": 37
        case "j": 38
        case "'", "quote": 39
        case "k": 40
        case ";", "semicolon": 41
        case "\\", "backslash": 42
        case ",", "comma": 43
        case "/", "slash": 44
        case "n": 45
        case "m": 46
        case ".", "period": 47
        case "tab": 48
        case "space": 49
        case "`", "backtick": 50
        case "backspace", "delete": 51
        case "escape", "esc": 53
        case "f17": 64
        case "f18": 79
        case "f19": 80
        case "f20": 90
        case "f5": 96
        case "f6": 97
        case "f7": 98
        case "f3": 99
        case "f8": 100
        case "f9": 101
        case "f11": 103
        case "f13": 105
        case "f16": 106
        case "f14": 107
        case "f10": 109
        case "f12": 111
        case "f15": 113
        case "help", "insert": 114
        case "home": 115
        case "pageup": 116
        case "forwarddelete": 117
        case "f4": 118
        case "end": 119
        case "f2": 120
        case "pagedown": 121
        case "f1": 122
        case "left", "leftarrow": 123
        case "right", "rightarrow": 124
        case "down", "downarrow": 125
        case "up", "uparrow": 126
        default: nil
        }
    }

    private static func displayKeyName(for name: String) -> String {
        switch normalized(name) {
        case "esc": "Escape"
        case "return", "enter": "Return"
        case "space": "Space"
        case "tab": "Tab"
        case "backspace", "delete": "Delete"
        case "forwarddelete": "Forward Delete"
        case "left", "leftarrow": "Left Arrow"
        case "right", "rightarrow": "Right Arrow"
        case "up", "uparrow": "Up Arrow"
        case "down", "downarrow": "Down Arrow"
        case "pageup": "Page Up"
        case "pagedown": "Page Down"
        default: name.uppercased()
        }
    }

    private static func isFunctionKey(_ name: String) -> Bool {
        let value = normalized(name)
        guard value.first == "f", let number = Int(value.dropFirst()) else { return false }
        return (1...20).contains(number)
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
    }
}

enum CodexShortcutConfigurationError: LocalizedError, Equatable {
    case missingFile
    case invalidJSON
    case missingToggle
    case missingKey
    case missingRealtimeVoice
    case missingRealtimeVoiceKey
    case invalidShortcut(String)

    var errorDescription: String? {
        switch self {
        case .missingFile:
            "Open Codex and set a Toggle dictation hotkey in Settings → Voice"
        case .invalidJSON:
            "Codex keybindings file is invalid JSON"
        case .missingToggle:
            "Set a Toggle dictation hotkey in Codex Settings → Voice"
        case .missingKey:
            "Codex Toggle dictation hotkey has no key"
        case .missingRealtimeVoice:
            "Set a Voice chat hotkey in Codex Settings → Voice"
        case .missingRealtimeVoiceKey:
            "Codex Voice chat hotkey has no key"
        case let .invalidShortcut(message):
            message
        }
    }
}

struct CodexKeybindings {
    static func globalDictationToggle(in data: Data) throws -> CodexShortcut {
        try shortcut(
            command: "globalDictationToggle",
            in: data,
            missingCommand: .missingToggle,
            missingKey: .missingKey
        )
    }

    static func realtimeVoice(in data: Data) throws -> CodexShortcut {
        try shortcut(
            command: "realtimeVoice",
            in: data,
            missingCommand: .missingRealtimeVoice,
            missingKey: .missingRealtimeVoiceKey
        )
    }

    private static func shortcut(
        command: String,
        in data: Data,
        missingCommand: CodexShortcutConfigurationError,
        missingKey: CodexShortcutConfigurationError
    ) throws -> CodexShortcut {
        let bindings: [KeyBinding]
        do {
            bindings = try JSONDecoder().decode([KeyBinding].self, from: data)
        } catch {
            throw CodexShortcutConfigurationError.invalidJSON
        }

        guard let binding = bindings.last(where: { $0.command == command }) else {
            throw missingCommand
        }
        guard let key = binding.key, !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw missingKey
        }

        do {
            return try CodexShortcut.parse(key)
        } catch {
            throw CodexShortcutConfigurationError.invalidShortcut(error.localizedDescription)
        }
    }
}

private struct KeyBinding: Decodable {
    let command: String
    let key: String?
}
