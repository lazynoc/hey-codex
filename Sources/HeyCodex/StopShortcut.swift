import Carbon
import CoreGraphics
import Foundation

enum StopShortcutError: LocalizedError, Equatable {
    case bareModifierUnsupported

    var errorDescription: String? {
        "The stop shortcut needs a modifier plus a key, for example Ctrl+Option+D"
    }
}

enum StopShortcut {
    static let defaultsKey = "stopShortcut"
    static let defaultRawValue = "Ctrl+Option+D"

    static func resolve(rawValue: String?) throws -> CodexShortcut {
        let shortcut = try CodexShortcut.parse(rawValue ?? defaultRawValue)
        guard !shortcut.isBareModifier else {
            throw StopShortcutError.bareModifierUnsupported
        }
        return shortcut
    }

    static func conflicts(_ stop: CodexShortcut, with codex: CodexShortcut) -> Bool {
        stop.keyCode == codex.keyCode
            && carbonModifiers(from: stop.flags) == carbonModifiers(from: codex.flags)
    }

    static func carbonModifiers(from flags: CGEventFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
        if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }
}
