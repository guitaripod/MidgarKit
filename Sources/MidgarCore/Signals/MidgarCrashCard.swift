import Foundation

/// One stack frame of a crash card: the binary's name and UUID, the offset into its text segment, and whether the binary ships inside the app. It is sent as `[name, uuid, offset, 0 or 1]`.
struct MidgarCrashFrame: Sendable, Equatable, Codable {
    let binary: String
    let uuid: String
    let offset: Int
    let inApp: Bool

    init(binary: String, uuid: String, offset: Int, inApp: Bool) {
        self.binary = binary
        self.uuid = uuid
        self.offset = offset
        self.inApp = inApp
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        binary = try container.decode(String.self)
        uuid = try container.decode(String.self)
        offset = try container.decode(Int.self)
        inApp = try container.decode(Int.self) == 1
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(binary)
        try container.encode(uuid)
        try container.encode(offset)
        try container.encode(inApp ? 1 : 0)
    }
}

/// What MidgarKit keeps of one MetricKit diagnostic and sends to `POST /v1/signals/diagnostics`: the kind of fault, the exception, code addresses, the app's own trail of screens, and the build, OS and device model it happened on. It carries no identifier, no memory contents, no path and none of the exception's message, and every field is cut to the shape the server's allowlist accepts.
struct MidgarCrashCard: Sendable, Equatable, Codable {
    enum Kind: String, Sendable, Codable {
        case crash, hang, cpu, disk, launch
    }

    let kind: Kind
    var type: String?
    var signal: String?
    var code: String?
    var objcName: String?
    var objcClass: String?
    var frames: [MidgarCrashFrame]
    var trail: [String]?
    var build: String?
    var os: String?
    var device: String?

    enum CodingKeys: String, CodingKey {
        case kind, type, signal, code, frames, trail, build, os, device
        case objcName = "objc_name"
        case objcClass = "objc_class"
    }

    /// What tells this fault from another on this device: its kind, its exception and its first frames in the app (the first of any binary when none is the app's). Two cards with one key are the same fault, sent once a day.
    var key: String {
        let own = frames.filter(\.inApp)
        let chosen = (own.isEmpty ? frames : own).prefix(MidgarCrashCards.keyFrames).map { "\($0.uuid):\($0.offset)" }
        return ([kind.rawValue, type ?? "", objcName ?? ""] + chosen).joined(separator: "|")
    }
}

/// Reads the JSON MetricKit gives for a diagnostic payload (`MXDiagnosticPayload.jsonRepresentation()`) into crash cards. It works on the JSON, not on MetricKit's classes, so it runs and is tested wherever Foundation does.
enum MidgarCrashCards {
    static let maximumFrames = 16
    static let maximumTrail = 20
    static let keyFrames = 5
    static let trailSlack: TimeInterval = 3_600

    /// The cards of one payload, in the order crashes, launches, hangs, processor and disk faults. A diagnostic with no usable frame gives no card.
    ///
    /// - Parameters:
    ///   - data: The payload's JSON.
    ///   - appBinaries: The names of the binaries that ship inside the app (its executable, frameworks and extensions), which mark a frame as the app's own.
    ///   - trail: The screens of the run that ended before this launch, with the time of the last one. It is attached to a crash only when that time falls inside the payload's window, give or take an hour, so a trail is never put on a crash from another run.
    static func cards(fromDiagnosticJSON data: Data, appBinaries: Set<String>, trail: MidgarTrailSnapshot?) -> [MidgarCrashCard] {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return []
        }
        let crashTrail = trailFor(payload, trail)
        let groups: [(MidgarCrashCard.Kind, [Diagnostic]?, [String]?)] = [
            (.crash, payload.crashDiagnostics, crashTrail),
            (.launch, payload.appLaunchDiagnostics, nil),
            (.hang, payload.hangDiagnostics, nil),
            (.cpu, payload.cpuExceptionDiagnostics, nil),
            (.disk, payload.diskWriteExceptionDiagnostics, nil)
        ]
        return groups.flatMap { kind, diagnostics, trail in
            (diagnostics ?? []).compactMap { card(kind, $0, appBinaries: appBinaries, trail: trail) }
        }
    }

    private static func card(_ kind: MidgarCrashCard.Kind, _ diagnostic: Diagnostic, appBinaries: Set<String>, trail: [String]?) -> MidgarCrashCard? {
        let frames = frames(of: diagnostic.callStackTree, kind: kind, appBinaries: appBinaries)
        guard !frames.isEmpty else {
            return nil
        }
        let meta = diagnostic.diagnosticMetaData
        let objc = meta?.objectiveCexceptionReason
        return MidgarCrashCard(
            kind: kind,
            type: meta?.exceptionType?.value.map(exceptionName),
            signal: meta?.signal?.value.map(signalName),
            code: meta?.terminationReason.flatMap(cleanCode),
            objcName: objc?.exceptionName.flatMap(cleanSymbol),
            objcClass: objc?.className.flatMap(cleanSymbol),
            frames: frames,
            trail: trail,
            build: meta?.appBuildVersion.flatMap { matching($0, #"^\d{1,10}$"#) },
            os: meta?.osVersion.flatMap { firstMatch(in: $0, #"\d{1,3}(\.\d{1,3}){0,2}"#) },
            device: meta?.deviceType.flatMap { matching($0, #"^[A-Za-z][A-Za-z0-9]{0,23}(,\d{1,3})?$"#) }
        )
    }

    /// The trail to put on this payload's crashes: the last twenty screens of the run before this launch, when its last mark falls inside the payload's window.
    private static func trailFor(_ payload: Payload, _ trail: MidgarTrailSnapshot?) -> [String]? {
        guard let trail, !trail.screens.isEmpty, let begin = payload.timeStampBegin.flatMap(date), let end = payload.timeStampEnd.flatMap(date) else {
            return nil
        }
        guard trail.at >= begin.addingTimeInterval(-trailSlack), trail.at <= end.addingTimeInterval(trailSlack) else {
            return nil
        }
        return Array(trail.screens.filter(MidgarTrail.isScreenID).suffix(maximumTrail))
    }

    /// The first sixteen frames nearest the fault. A crash's per-thread tree is one chain that starts at the frame the fault happened in; the attributed thread's is taken. A sampled tree starts at the thread's entry, so its heaviest path is walked to its end and turned round. Launch, hang, processor and disk trees are always sampled, whatever `callStackPerThread` says: launch trees arrive marked per-thread yet start at `libsystem_pthread`.
    private static func frames(of tree: Tree?, kind: MidgarCrashCard.Kind, appBinaries: Set<String>) -> [MidgarCrashFrame] {
        guard let tree, let stacks = tree.callStacks, !stacks.isEmpty else {
            return []
        }
        let stack = stacks.first { $0.threadAttributed == true } ?? stacks[0]
        guard let root = (stack.callStackRootFrames ?? []).max(by: { ($0.sampleCount ?? 0) < ($1.sampleCount ?? 0) }) else {
            return []
        }
        var path: [Node] = []
        var next: Node? = root
        while let node = next, path.count < 512 {
            path.append(node)
            next = (node.subFrames ?? []).max { ($0.sampleCount ?? 0) < ($1.sampleCount ?? 0) }
        }
        let sampled = kind != .crash || tree.callStackPerThread == false
        let nearestFirst = sampled ? Array(path.reversed()) : path
        return Array(nearestFirst.compactMap { frame($0, appBinaries: appBinaries) }.prefix(maximumFrames))
    }

    private static func frame(_ node: Node, appBinaries: Set<String>) -> MidgarCrashFrame? {
        guard let uuid = node.binaryUUID.flatMap({ matching($0, #"^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$"#) }),
              let offset = node.offsetIntoBinaryTextSegment, offset >= 0, offset <= 1 << 40
        else {
            return nil
        }
        let name = node.binaryName ?? ""
        return MidgarCrashFrame(binary: cleanBinary(name), uuid: uuid.uppercased(), offset: offset, inApp: appBinaries.contains(name))
    }

    private static let exceptionNames = [
        1: "EXC_BAD_ACCESS", 2: "EXC_BAD_INSTRUCTION", 3: "EXC_ARITHMETIC", 4: "EXC_EMULATION", 5: "EXC_SOFTWARE", 6: "EXC_BREAKPOINT", 7: "EXC_SYSCALL",
        8: "EXC_MACH_SYSCALL", 9: "EXC_RPC_ALERT", 10: "EXC_CRASH", 11: "EXC_RESOURCE", 12: "EXC_GUARD", 13: "EXC_CORPSE_NOTIFY"
    ]
    private static let signalNames = [
        1: "SIGHUP", 2: "SIGINT", 3: "SIGQUIT", 4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 7: "SIGEMT", 8: "SIGFPE", 9: "SIGKILL", 10: "SIGBUS",
        11: "SIGSEGV", 12: "SIGSYS", 13: "SIGPIPE", 14: "SIGALRM", 15: "SIGTERM"
    ]

    private static func exceptionName(_ number: Int) -> String {
        exceptionNames[number] ?? "EXC_\(max(0, min(number, 999_999)))"
    }

    private static func signalName(_ number: Int) -> String {
        signalNames[number] ?? "SIG\(max(0, min(number, 999_999)))"
    }

    /// A binary's name with only the characters the server takes, cut to 64, or `unknown`.
    private static func cleanBinary(_ name: String) -> String {
        let kept = String(name.unicodeScalars.filter { isBinaryCharacter($0) }.prefix(64))
        return kept.isEmpty ? "unknown" : kept
    }

    private static func isBinaryCharacter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "_.+ -".unicodeScalars.contains(scalar))
    }

    /// The system's termination reason with every character outside letters, digits and plain punctuation removed, cut to 120. The system writes it, not the app, but nothing else is let through either way.
    private static func cleanCode(_ reason: String) -> String? {
        let kept = String(reason.unicodeScalars.filter { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || " _,.:()<>-".unicodeScalars.contains($0)) }.prefix(120))
        let trimmed = kept.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// An exception or class name that is a plain identifier, or nil. An Objective-C exception's message and its format string are never read.
    private static func cleanSymbol(_ name: String) -> String? {
        matching(name, #"^[A-Za-z_][A-Za-z0-9_.]{0,79}$"#)
    }

    private static func matching(_ text: String, _ pattern: String) -> String? {
        text.range(of: pattern, options: .regularExpression) == nil ? nil : text
    }

    private static func firstMatch(in text: String, _ pattern: String) -> String? {
        text.range(of: pattern, options: .regularExpression).map { String(text[$0]) }
    }

    private static func date(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: text)
    }

    private struct Payload: Decodable {
        var timeStampBegin: String?
        var timeStampEnd: String?
        var crashDiagnostics: [Diagnostic]?
        var hangDiagnostics: [Diagnostic]?
        var cpuExceptionDiagnostics: [Diagnostic]?
        var diskWriteExceptionDiagnostics: [Diagnostic]?
        var appLaunchDiagnostics: [Diagnostic]?
    }

    private struct Diagnostic: Decodable {
        var callStackTree: Tree?
        var diagnosticMetaData: Meta?
    }

    private struct Tree: Decodable {
        var callStackPerThread: Bool?
        var callStacks: [Stack]?
    }

    private struct Stack: Decodable {
        var threadAttributed: Bool?
        var callStackRootFrames: [Node]?
    }

    private struct Node: Decodable {
        var binaryUUID: String?
        var offsetIntoBinaryTextSegment: Int?
        var sampleCount: Int?
        var binaryName: String?
        var subFrames: [Node]?
    }

    private struct Meta: Decodable {
        var appBuildVersion: String?
        var osVersion: String?
        var deviceType: String?
        var exceptionType: Number?
        var signal: Number?
        var terminationReason: String?
        var objectiveCexceptionReason: ObjectiveCReason?
    }

    private struct ObjectiveCReason: Decodable {
        var exceptionName: String?
        var className: String?
    }

    /// A number MetricKit writes as a number in some versions and as text in others.
    private struct Number: Decodable {
        let value: Int?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int.self) {
                value = number
            } else {
                value = (try? container.decode(String.self)).flatMap { Int($0) }
            }
        }
    }
}
