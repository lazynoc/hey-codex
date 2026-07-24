import Foundation

enum WakeSensitivity: String, CaseIterable, Sendable {
    case strict
    case normal
    case loose

    static let defaultsKey = "wakeSensitivity"

    var displayName: String {
        rawValue.capitalized
    }
}

enum PhraseParser {
    /// Returns the action of the first binding whose phrase appears in the
    /// transcript, or nil when no wake phrase was heard.
    static func matchedAction(
        _ transcript: String,
        bindings: [WakePhraseBinding],
        sensitivity: WakeSensitivity = .normal
    ) -> WakeAction? {
        for binding in bindings where containsWakePhrase(
            transcript,
            wakePhrase: binding.phrase,
            sensitivity: sensitivity
        ) {
            return binding.action
        }
        return nil
    }

    static func containsWakePhrase(
        _ transcript: String,
        wakePhrase: String,
        sensitivity: WakeSensitivity = .normal
    ) -> Bool {
        let transcriptWords = tokens(in: transcript)
        let wakeWords = tokens(in: wakePhrase)
        if contains(wakeWords, in: transcriptWords) {
            return true
        }

        guard sensitivity != .strict else { return false }
        guard wakeWords.count == 2, wakeWords[0] == "hey" else { return false }

        let name = wakeWords[1]
        let aliases = aliases(for: name)

        if sensitivity == .loose {
            let greetings = ["hey", "hi", "hy", "hay", "hei"]
            for index in transcriptWords.indices
            where greetings.contains(transcriptWords[index]) {
                let next = transcriptWords.index(after: index)
                guard next < transcriptWords.endIndex else { continue }

                if matchesName(
                    transcriptWords,
                    at: next,
                    name: name,
                    aliases: aliases
                ) {
                    return true
                }
            }
            return false
        }

        for index in transcriptWords.indices where transcriptWords[index] == "hey" {
            let next = transcriptWords.index(after: index)
            guard next < transcriptWords.endIndex else { continue }

            if matchesName(transcriptWords, at: next, name: name, aliases: aliases) {
                return true
            }
        }

        return false
    }

    /// Common misrecognitions of the built-in names. Any two-word "hey …"
    /// phrase also tolerates small transcription errors via edit distance.
    private static func aliases(for name: String) -> [String] {
        switch name {
        case "codex":
            ["codex", "codec", "codecs", "kodak", "coded", "cortex"]
        case "jarvis":
            ["jarvis", "jervis", "jarves", "jarvus", "travis"]
        default:
            [name]
        }
    }

    private static func matchesName(
        _ words: [String],
        at index: Int,
        name: String,
        aliases: [String]
    ) -> Bool {
        // "codex" is often split into "code x"; bare "code" must not match.
        if name == "codex", words[index] == "code" {
            let afterNext = words.index(after: index)
            return afterNext < words.endIndex && words[afterNext] == "x"
        }

        return aliases.contains(words[index]) || editDistance(words[index], name) <= 2
    }

    private static func tokens(in text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byWords, .substringNotRequired]
        ) { _, range, _, _ in
            result.append(String(text[range]).lowercased())
        }
        return result
    }

    private static func contains(_ needle: [String], in haystack: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }

        for start in 0...(haystack.count - needle.count) {
            let end = start + needle.count
            if Array(haystack[start..<end]) == needle {
                return true
            }
        }

        return false
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)

        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]

            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                ))
            }

            previous = current
        }

        return previous[right.count]
    }
}
