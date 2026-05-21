import SwiftUI

struct MessageBubbleView: View {
    let message: Message

    var body: some View {
        HStack {
            if !message.isUserA {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.isUserA ? .leading : .trailing, spacing: 4) {
                Text(message.originalText)
                    .font(.body)

                Text(message.translatedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(message.isUserA ? Color(.systemGray5) : Color.accentColor.opacity(0.15))
            .clipShape(.rect(cornerRadius: 16))

            if message.isUserA {
                Spacer(minLength: 40)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.isUserA ? "Utente A" : "Utente B"): \(message.originalText). Traduzione: \(message.translatedText)")
    }
}
