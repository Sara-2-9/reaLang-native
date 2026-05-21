import SwiftUI

@main
struct ConversationTranslatorApp: App {
    @State private var session = ConversationSession()

    var body: some Scene {
        WindowGroup {
            LanguageSetupView(session: session)
        }
    }
}
