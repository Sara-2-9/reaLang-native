import SwiftUI

struct PushToTalkButton: View {
    let label: String
    let isListening: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    @GestureState private var isPressed = false

    var body: some View {
        let gesture = DragGesture(minimumDistance: 0)
            .updating($isPressed) { _, state, _ in
                state = true
            }
            .onEnded { _ in
                onRelease()
            }

        VStack(spacing: 8) {
            Image(systemName: isListening ? "waveform" : "mic.fill")
                .font(.system(size: 32, weight: .semibold))
                .scaleEffect(isListening ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.3), value: isListening)

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
        .simultaneousGesture(gesture)
        .onChange(of: isPressed) { _, newValue in
            if newValue {
                onPress()
            }
        }
        .sensoryFeedback(.impact, trigger: isListening)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Parla in \(label)")
        .accessibilityHint("Tieni premuto per parlare. Rilascia per inviare.")
    }
}
