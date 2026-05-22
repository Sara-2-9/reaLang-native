import SwiftUI
import Translation

struct ConversationView: View {
    let session: ConversationSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            messageList
            statusBanner
            phaseLogView
            controls
        }
        .translationTask(session.translationConfig) { translationSession in
            guard let text = await MainActor.run(body: { session.pendingTranslationText }) else { return }
            do {
                let response = try await Task {
                    try await translationSession.translate(text)
                }.value
                await MainActor.run {
                    session.finalizeTranslation(response: response)
                }
            } catch {
                await MainActor.run {
                    session.handleTranslationError(error)
                }
            }
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
        .alert("Errore", isPresented: errorBinding) {
            Button("OK") { session.clearError() }
        } message: {
            Text(session.errorMessage ?? "")
        }
        .onDisappear {
            session.stopListening()
        }
    }

    // MARK: - Subviews

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(session.messages) { message in
                        MessageBubbleView(message: message)
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

    private var statusBanner: some View {
        Text(session.phase.rawValue)
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(phaseColor)
            .animation(.easeInOut, value: session.phase)
    }

    private var phaseColor: Color {
        switch session.phase {
        case .idle:
            return .green
        case .listening:
            return .red
        case .transcribed:
            return .orange
        case .translating:
            return .blue
        case .speaking:
            return .purple
        case .error:
            return .red
        }
    }

    private var phaseLogView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cronologia stati")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(session.phaseHistory) { entry in
                        Text(entry.text)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 80)
        }
        .padding(.vertical, 4)
    }

    private var controls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                PushToTalkButton(
                    label: languageName(for: session.languageA),
                    isListening: session.isListeningA,
                    onPress: { Task { await session.startListening(userA: true) } },
                    onRelease: { session.stopListening() }
                )

                PushToTalkButton(
                    label: languageName(for: session.languageB),
                    isListening: session.isListeningB,
                    onPress: { Task { await session.startListening(userA: false) } },
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

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.clearError() } }
        )
    }
}
