import Foundation

extension MidgarSignals {
    /// What the store module tells signals about money. The joining happens here, on the device, so no event needs an identifier to be read beside another.
    public enum StoreNote: Sendable, Equatable {
        /// Whether the install pays right now.
        case tier(MidgarSignal.Tier)
        /// A purchase was made on this install just now.
        case purchased
        /// A subscription that began at this date had its renewal turned off.
        case renewalOff(startedAt: Date)
    }

    /// Takes one fact from the store module. A tier is remembered and stamped on the events that declare it; a purchase and a renewal turned off become stories, filled from what this install remembers and held for some hours before they are sent. Nothing is remembered or sent while usage counts are off or killed.
    public func note(_ note: StoreNote) {
        guard !isSuppressed else {
            return
        }
        ensureContext()
        let date = now()
        switch note {
        case .tier(let tier):
            guard context?.tier != tier.rawValue else {
                return
            }
            context?.tier = tier.rawValue
            contextChanged()
            send(.appTier)
        case .purchased:
            let placement = context?.lastPlacement.flatMap(MidgarSignal.Placement.init(rawValue:))
            send(.purchaseStory(placement: placement, viewsBefore: MidgarSignalsBuckets.views(context?.paywallViews ?? 0)))
        case .renewalOff(let startedAt):
            let active = context?.activeDayCount(at: date) ?? 0
            send(.renewalOff(tenure: MidgarSignalsBuckets.tenure(startedAt: startedAt, now: date), activeDays: MidgarSignalsBuckets.activeDays(active)))
        }
    }

    /// Reports that the person got what the app is for, such as the first song played. Only the first call on an install sends anything: `value.first` with how soon after installing it came. Each app has one value moment, named in its registry entry.
    public func noteValue() {
        guard !isSuppressed else {
            return
        }
        ensureContext()
        guard context?.reachedValue == false else {
            return
        }
        context?.reachedValue = true
        contextChanged()
        let age = MidgarSignalsBuckets.age(installedAt: installDate(), now: now())
        send(.valueFirst(within: MidgarSignalsBuckets.within(age: age, isFirstRun: startedContextThisRun)))
    }

    /// Reports the value moment on the ``shared`` instance from any thread. Does nothing until signals are configured.
    public nonisolated static func noteValue() {
        Task { await shared?.noteValue() }
    }

    /// Reports that a feature was used, on the ``shared`` instance from any thread: `feature.use`, once a week per feature, with whether the install pays. The id must be one the app's registry entry lists; the server counts any other as `other`.
    public nonisolated static func noteFeature(_ id: String) {
        Task { await shared?.send(.featureUse(feature: id)) }
    }

    /// Notes that a screen came on, from any thread: it goes on the crash trail (``MidgarTrail``), and with `feature` true it also counts as using that feature this week (``noteFeature(_:)``). The id must be one the app's registry entry lists under `[lifestream]`. Call it where the screen is really shown, such as `viewDidAppear`, never where its view is only built.
    public nonisolated static func noteScreen(_ id: String, feature: Bool = false) {
        MidgarTrail.mark(id)
        if feature {
            noteFeature(id)
        }
    }

    /// What a send of this event changes in what the install remembers, before the event itself goes out: a purchase screen is counted with where it was opened from.
    func remember(_ signal: MidgarSignal) {
        guard case .paywallView(let placement) = signal, !isSuppressed else {
            return
        }
        ensureContext()
        context?.countPaywall(placement: placement.rawValue)
        contextChanged()
    }

    /// Adds the context an event declares: the tier last heard from the store, and how long ago the app was installed.
    func stamp(_ wanted: [MidgarSignal.Context], on props: inout [String: MidgarSignalValue], at date: Date) {
        guard !wanted.isEmpty else {
            return
        }
        ensureContext()
        for item in wanted {
            switch item {
            case .tier:
                props[item.rawValue] = .string(context?.tier ?? MidgarSignal.Tier.unknown.rawValue)
            case .age:
                props[item.rawValue] = .string(MidgarSignalsBuckets.age(installedAt: installDate(), now: date).rawValue)
            }
        }
    }

    /// Keeps a story for a random time inside the policy's range, so that when it reaches the server says nothing about when it happened and it cannot be lined up with a sale.
    func hold(_ event: MidgarSignalEvent, at date: Date) {
        ensureContext()
        context?.hold(event, until: date.addingTimeInterval(TimeInterval.random(in: policy.storyDelay)))
        contextChanged()
    }

    /// Queues the stories whose wait is over. While nothing may be sent they are dropped instead.
    func releaseDueStories() {
        ensureContext()
        guard context?.held.isEmpty == false else {
            return
        }
        if isSuppressed {
            context?.held.removeAll()
            contextChanged()
            return
        }
        let due = context?.releaseDue(at: now()) ?? []
        guard !due.isEmpty else {
            return
        }
        contextChanged()
        due.forEach(enqueue)
    }

    /// Marks today as a day the app was active and, once the store has said whether the install pays, counts it among the week's installs of that tier.
    func noteActiveContext() {
        guard !isSuppressed else {
            return
        }
        ensureContext()
        if context?.markActive(at: now()) == true {
            contextChanged()
        }
        if let tier = context?.tier, tier != MidgarSignal.Tier.unknown.rawValue {
            send(.appTier)
        }
    }

    /// Forgets the context, in memory and on disk, when the person turns usage counts off.
    func forgetContext() {
        context = nil
        contextIsDirty = false
        MidgarSignalsContextStore(store: store).delete()
    }

    /// Reads the context from disk on first use. A run that finds none is the first to keep it, which is how a first session is told from a later one.
    func ensureContext() {
        guard context == nil else {
            return
        }
        let saved = MidgarSignalsContextStore(store: store).load()
        startedContextThisRun = saved == nil
        context = saved ?? MidgarSignalsContext()
    }

    private func contextChanged() {
        contextIsDirty = true
        schedulePersist()
    }
}
