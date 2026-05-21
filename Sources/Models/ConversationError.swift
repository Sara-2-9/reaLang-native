import Foundation

enum ConversationError: Error, LocalizedError {
    case speechNotAuthorized
    case microphoneNotAuthorized
    case translationNotSupported
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .speechNotAuthorized:
            return "Autorizzazione riconoscimento vocale negata."
        case .microphoneNotAuthorized:
            return "Autorizzazione microfono negata."
        case .translationNotSupported:
            return "Traduzione non supportata per questa coppia di lingue."
        case .recognitionFailed(let message):
            return message
        }
    }
}
