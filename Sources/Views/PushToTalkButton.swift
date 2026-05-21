import SwiftUI

struct PushToTalkButton: View {
    let label: String
    let isListening: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    var body: some View {
        let gesture = DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isListening {
                    onPress()
                }
            }
            .onEnded { _ in
                onRelease()
            }

        VStack(spacing: 8) {
            Image(systemName: isListening ? "waveform" : "mic.fill")
                .font(.system(size: 32, weight: .semibold))
                .symbolEffect(.bounce, options: .repeating, value: isListening)

            Text(label)
                .font(.caption.bold())
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(isListening ? Color.red.opacity(0.15) : Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isListening ? Color.red : Color.clear, lineWidth: 2)
        )
        .gesture(gesture)
        .sensoryFeedback(.impact, trigger: isListening)
        .accessibilityLabel("Parla in \(label)")
        .accessibilityHint("Tieni premuto per parlare. Rilascia per inviare.")
    }
}
