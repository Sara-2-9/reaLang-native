import Foundation

struct Message: Identifiable, Equatable {
    let id = UUID()
    let originalText: String
    let translatedText: String
    let sourceLanguage: String
    let targetLanguage: String
    let isUserA: Bool
    let timestamp: Date
}
