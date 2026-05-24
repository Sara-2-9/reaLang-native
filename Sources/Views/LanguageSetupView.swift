import SwiftUI

struct LanguageSetupView: View {
    @Bindable var session: ConversationSession
    @State private var path = NavigationPath()
    @State private var audioRouteService = AudioRouteService()

    private let availableLanguages: [Locale] = [
        .init(identifier: "it_IT"),
        .init(identifier: "en_US"),
        .init(identifier: "en_GB"),
        .init(identifier: "es_ES"),
        .init(identifier: "fr_FR"),
        .init(identifier: "de_DE"),
        .init(identifier: "ja_JP"),
        .init(identifier: "zh_Hans_CN"),
        .init(identifier: "pt_BR"),
        .init(identifier: "ru_RU"),
        .init(identifier: "ko_KR"),
        .init(identifier: "ar_SA")
    ]

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                languageSection(title: "Utente A", selection: $session.languageA)
                languageSection(title: "Utente B", selection: $session.languageB)
            }
            .navigationTitle("ReaLang")
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 16) {
                    Button {
                        path.append(Destination.conversation)
                    } label: {
                        Label("Conversazione", systemImage: "bubble.left.and.bubble.right.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(session.languageA.identifier == session.languageB.identifier)

                    Button {
                        path.append(Destination.realTimeTranslation)
                    } label: {
                        Label("Real-Time", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(session.languageA.identifier == session.languageB.identifier || !audioRouteService.isHeadsetConnected)
                }
                .padding()
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .conversation:
                    ConversationView(session: session)
                case .realTimeTranslation:
                    RealTimeTranslationView(
                        sourceLanguage: session.languageA,
                        targetLanguage: session.languageB
                    )
                }
            }
        }
    }

    // MARK: - Subviews

    private func languageSection(title: String, selection: Binding<Locale>) -> some View {
        Section(title) {
            Picker("Lingua", selection: selection) {
                ForEach(availableLanguages, id: \.identifier) { locale in
                    Text(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                        .tag(locale)
                }
            }
        }
    }
}

// MARK: - Navigation

private enum Destination: Hashable {
    case conversation
    case realTimeTranslation
}
