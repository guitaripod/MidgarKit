import Foundation

/// What a task needs from the model that answers it.
public enum MidgarModelRequirement: Sendable, Equatable {
    /// Either route may answer. The on-device model is preferred.
    case any
    /// Only the cloud model may answer: long context, images, or anything the on-device model cannot do.
    case cloudOnly
}

/// One image sent with a prompt. Only the cloud model reads images, so a prompt that carries one is cloud only.
public struct MidgarPromptImage: Sendable, Equatable {
    public let data: Data
    public let mediaType: String

    public init(data: Data, mediaType: String = "image/jpeg") {
        self.data = data
        self.mediaType = mediaType
    }

    var dataURL: String {
        "data:\(mediaType);base64,\(data.base64EncodedString())"
    }
}

/// One request to a language model: instructions, the user's text, and hints about the answer.
public struct MidgarPrompt: Sendable, Equatable {
    public var instructions: String?
    public var text: String
    public var images: [MidgarPromptImage]
    public var maxOutputTokens: Int?
    public var temperature: Double?
    public var requirement: MidgarModelRequirement

    /// - Parameters:
    ///   - maxOutputTokens: A hint the on-device model honors. mako's plain chat endpoint sets its own limit and ignores it.
    ///   - temperature: A hint the on-device model honors. mako's plain chat endpoint ignores it.
    public init(
        instructions: String? = nil,
        text: String,
        images: [MidgarPromptImage] = [],
        maxOutputTokens: Int? = nil,
        temperature: Double? = nil,
        requirement: MidgarModelRequirement = .any
    ) {
        self.instructions = instructions
        self.text = text
        self.images = images
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.requirement = requirement
    }

    /// The requirement after the prompt's content is taken into account: images force the cloud.
    public var effectiveRequirement: MidgarModelRequirement {
        images.isEmpty ? requirement : .cloudOnly
    }
}

/// Which route produced an answer.
public enum MidgarRoute: String, Sendable, Equatable {
    case onDevice
    case cloud
}

/// A finished answer and where it came from.
public struct MidgarCompletion: Sendable, Equatable {
    public let text: String
    public let route: MidgarRoute
    /// The cloud model id that answered. Nil on device.
    public let model: String?
    /// Credits mako charged for this call. Nil on device, where nothing is metered; 0 when a Pass or free bucket covered it.
    public let creditsCharged: Int?

    public init(text: String, route: MidgarRoute, model: String? = nil, creditsCharged: Int? = nil) {
        self.text = text
        self.route = route
        self.model = model
        self.creditsCharged = creditsCharged
    }
}
