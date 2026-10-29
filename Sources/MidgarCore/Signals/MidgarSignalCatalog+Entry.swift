import Foundation

extension MidgarSignalCatalog {
    /// One event of the registry as a person should see it: what it is for, how often one install may send it, what it carries and which apps may send it.
    public struct Entry: Sendable, Equatable, Identifiable {
        /// The event name on the wire.
        public let name: String
        /// Why the event is sent, in the registry's words.
        public let purpose: String
        /// How often one install may send the event.
        public let uniqueness: MidgarSignal.Uniqueness
        /// Whether MidgarKit adds the week the app was installed to the event.
        public let carriesCohort: Bool
        /// True while no code sends the event, so a screen that lists what an app sends leaves it out.
        public let isReserved: Bool
        /// The string props the event carries, each with the values it may take.
        public let props: [Prop]
        /// The measurements the event carries, each with the range it must stay in.
        public let measurements: [Measurement]
        /// The registry slugs of the apps allowed to send the event. Empty when every app may.
        public let apps: [String]

        public var id: String { name }

        public init(
            name: String,
            purpose: String,
            uniqueness: MidgarSignal.Uniqueness,
            carriesCohort: Bool = false,
            isReserved: Bool = false,
            props: [Prop] = [],
            measurements: [Measurement] = [],
            apps: [String] = []
        ) {
            self.name = name
            self.purpose = purpose
            self.uniqueness = uniqueness
            self.carriesCohort = carriesCohort
            self.isReserved = isReserved
            self.props = props
            self.measurements = measurements
            self.apps = apps
        }

        /// Whether the app with this registry slug may send the event: any app when the event has no app limit, otherwise only the apps it names. Without a slug only the events with no limit qualify.
        public func isAllowed(for appID: String?) -> Bool {
            apps.isEmpty || appID.map(apps.contains) == true
        }
    }

    /// A string prop of an event and the values it may take.
    public struct Prop: Sendable, Equatable {
        /// Where the allowed values come from.
        public enum Values: Sendable, Equatable {
            /// A closed set listed here.
            case list([String])
            /// The registry slug or App Store id of a Midgar app.
            case apps
            /// A product id from the app registry.
            case products
        }

        public let name: String
        public let values: Values
        /// True when the event may leave the prop out.
        public let isOptional: Bool

        public init(name: String, values: Values, isOptional: Bool = false) {
            self.name = name
            self.values = values
            self.isOptional = isOptional
        }
    }

    /// A number an event carries and the range the server accepts it in.
    public struct Measurement: Sendable, Equatable {
        public let name: String
        public let minimum: Double
        public let maximum: Double
        /// True when only whole numbers are accepted.
        public let isInteger: Bool

        public init(name: String, minimum: Double, maximum: Double, isInteger: Bool = false) {
            self.name = name
            self.minimum = minimum
            self.maximum = maximum
            self.isInteger = isInteger
        }
    }

    /// The events the app with this registry slug sends: those with no app limit and those limited to this slug, in registry order. Events no code sends yet (``Entry/isReserved``) are left out unless `includingReserved` is true. Without a slug only the events with no app limit qualify.
    public static func entries(for appID: String?, includingReserved: Bool = false) -> [Entry] {
        entries.allowed(for: appID, includingReserved: includingReserved)
    }

    /// The entry of the event with this name, or nil when the registry has no such event.
    public static func entry(named name: String) -> Entry? {
        entries.first { $0.name == name }
    }
}

extension Sequence where Element == MidgarSignalCatalog.Entry {
    /// The entries the app with this registry slug may send, in the order given. See ``MidgarSignalCatalog/entries(for:includingReserved:)``.
    public func allowed(for appID: String?, includingReserved: Bool = false) -> [Element] {
        filter { $0.isAllowed(for: appID) && (includingReserved || !$0.isReserved) }
    }
}
