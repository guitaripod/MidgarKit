import Foundation

struct MidgarChatMessageWire: Encodable, Sendable {
    let role: String
    let content: String
}

/// The body of mako's `POST /v1/run/chat.completion` in its plain (non-alias) form.
struct MidgarChatRequestWire: Encodable, Sendable {
    let messages: [MidgarChatMessageWire]
    let images: [String]?
    let model: String?

    init(prompt: MidgarPrompt, model: String?) {
        var messages: [MidgarChatMessageWire] = []
        if let instructions = prompt.instructions, !instructions.isEmpty {
            messages.append(MidgarChatMessageWire(role: "system", content: instructions))
        }
        messages.append(MidgarChatMessageWire(role: "user", content: prompt.text))
        self.messages = messages
        self.images = prompt.images.isEmpty ? nil : prompt.images.map(\.dataURL)
        self.model = model
    }
}

struct MidgarChatResponseWire: Decodable, Sendable {
    let content: String
    let model: String
    let creditsCharged: Int

    enum CodingKeys: String, CodingKey {
        case content
        case model
        case creditsCharged = "credits_charged"
    }
}

struct MidgarBalanceWire: Decodable, Sendable {
    struct Bucket: Decodable, Sendable {
        let limit: Int
        let remaining: Int
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case limit
            case remaining
            case resetsAt = "resets_at"
        }
    }

    let balance: Int
    let weekly: [String: Bucket]?
}
