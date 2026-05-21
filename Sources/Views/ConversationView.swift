import SwiftUI

struct ConversationView: View {
    let session: ConversationSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            messageList
            controls
        }
        .navigationTitle("Conversazione")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fine") {
                    session.endConversation()
                    dismiss()
                }
            }
        }
        .alert("Errore", isPresented: .constant(session.errorMessage != nil)) {
            Button("OK") { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    // MARK: - Subviews

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(session.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: session.messages.count) { _, _ in
                if let last = session.messages.last {
                    withAnimation(.smooth) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                PushToTalkButton(
                    label: languageName(for: session.languageA),
                    isListening: session.isListeningA,
                    onPress: { session.startListening(userA: true) },
                    onRelease: { session.stopListening() }
                )

                PushToTalkButton(
                    label: languageName(for: session.languageB),
                    isListening: session.isListeningB,
                    onPress: { session.startListening(userA: false) },
                    onRelease: { session.stopListening() }
                )
            }
            .padding(.horizontal)

            Button("Termina Conversazione") {
                session.endConversation()
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.bottom)
        }
        .padding(.vertical)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func languageName(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
}
