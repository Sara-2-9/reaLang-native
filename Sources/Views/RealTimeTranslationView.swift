import SwiftUI

struct RealTimeTranslationView: View {
    @State private var session: RealTimeSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(sourceLanguage: Locale, targetLanguage: Locale) {
        _session = State(wrappedValue: RealTimeSession(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            textAreas
            Spacer()
            controls
        }
        .navigationTitle("Traduzione Real-Time")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Chiudi") {
                    session.stop()
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
            session.stop()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                session.stop()
            }
        }
    }

    // MARK: - Subviews

    private var statusBar: some View {
        HStack(spacing: 20) {
            StatusIndicator(
                icon: "headphones.circle.fill",
                label: "Cuffie",
                isActive: session.audioRouteService.isHeadsetConnected,
                activeColor: .green
            )
            StatusIndicator(
                icon: "mic.fill",
                label: "Microfono",
                isActive: session.isRunning,
                activeColor: .red
            )
            StatusIndicator(
                icon: "globe",
                label: "Traduzione",
                isActive: !session.liveTranslation.isEmpty,
                activeColor: .blue
            )
            StatusIndicator(
                icon: "speaker.wave.2.fill",
                label: "Audio",
                isActive: session.isSpeaking,
                activeColor: .purple
            )
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var textAreas: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    textCard(
                        title: "Trascrizione Originale (\(languageName(for: session.sourceLanguage)))",
                        text: session.liveTranscription,
                        color: .secondary
                    )

                    textCard(
                        title: "Traduzione Live (\(languageName(for: session.targetLanguage)))",
                        text: session.liveTranslation,
                        color: .primary
                    )

                    Spacer().id("bottom")
                }
                .padding()
            }
            .onChange(of: session.liveTranscription) { _, _ in
                withAnimation(.smooth) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: session.liveTranslation) { _, _ in
                withAnimation(.smooth) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func textCard(title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Text(text.isEmpty ? "In attesa di audio..." : text)
                .font(.body)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 12))
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button(action: {
                if session.isRunning {
                    session.stop()
                } else {
                    Task {
                        await session.start()
                    }
                }
            }) {
                ZStack {
                    Circle()
                        .fill(session.isRunning ? Color.red : Color.green)
                        .frame(width: 80, height: 80)
                        .shadow(radius: 8)

                    Image(systemName: session.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(!session.audioRouteService.isHeadsetConnected && !session.isRunning)
            .accessibilityLabel(session.isRunning ? "Ferma traduzione" : "Avvia traduzione")
            .accessibilityHint(session.isRunning ? "Interrompe l'ascolto e la traduzione" : "Inizia l'ascolto e la traduzione in tempo reale")

            Text(session.isRunning ? "Tocca per fermare" : "Tocca per iniziare")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 24)
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

// MARK: - Status Indicator

private struct StatusIndicator: View {
    let icon: String
    let label: String
    let isActive: Bool
    let activeColor: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isActive ? activeColor : .gray)
                .symbolEffect(.pulse, isActive: isActive)

            Text(label)
                .font(.caption2)
                .foregroundStyle(isActive ? activeColor : .gray)
        }
        .accessibilityLabel("\(label): \(isActive ? "attivo" : "non attivo")")
    }
}
