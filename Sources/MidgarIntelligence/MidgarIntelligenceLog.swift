import MidgarCore

extension MidgarLog.Category {
    static let intelligence = MidgarLog.Category("intelligence")
}

/// Receives one line per routing decision. Lines carry route names and error type names, never prompt or completion text.
public typealias MidgarIntelligenceLogger = @Sendable (String) -> Void

public enum MidgarIntelligenceLogging {
    public static let standard: MidgarIntelligenceLogger = { line in
        MidgarLog.info(line, category: .intelligence)
    }
}
