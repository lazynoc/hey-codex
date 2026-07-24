import Foundation

enum WakeAction: Equatable, Sendable {
    case dictation
    case voiceChat
}

/// One wake phrase and the action it starts. The listener matches every
/// binding at once and reports which one was heard.
struct WakePhraseBinding: Equatable, Sendable {
    let phrase: String
    let action: WakeAction
}
