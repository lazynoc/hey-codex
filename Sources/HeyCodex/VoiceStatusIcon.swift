import SwiftUI

struct VoiceStatusIcon: View {
    let phase: VoicePhase

    var body: some View {
        ZStack {
            Image(systemName: phase.symbolName)

            if phase.showsListeningSlash {
                Image(systemName: "slash")
                    .fontWeight(.semibold)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase.title)
    }
}
