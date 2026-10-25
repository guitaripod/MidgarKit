import Foundation

extension MidgarSignals {
    /// What this install remembers between launches: the uniqueness ledger and the cohort. Read from disk the first time an event needs either, so no launch reads files that a plain `record` call never uses.
    struct InstallState {
        var ledger: MidgarSignalsLedger
        let ledgerStore: MidgarSignalsLedgerStore
        let cohort: String
    }

    /// Sends one generated event, if the registry lets this install send it now.
    ///
    /// The event's uniqueness decides: `each` always goes; `daily`, `weekly` and `monthly` go once per calendar period of the device's ISO calendar for each distinct combination of props; `lifetime` goes once per install for each combination; `per-period` goes once per calendar period named by its `period` prop. Events that carry a cohort get the install's `cohort` prop. Nothing is sent or remembered while the kill switch is on or ``isEnabled`` is off.
    ///
    /// The call does no disk work and no network work: it looks the event up in memory and appends it to the queue. The ledger reaches disk at most every 5 seconds, and on ``flush()``.
    public func send(_ signal: MidgarSignal) {
        deliver(name: signal.name, props: signal.props, uniqueness: signal.uniqueness, carriesCohort: signal.carriesCohort)
    }

    /// The path every send takes, with the event's registry facts given apart from the event so a test can drive the periodic kinds no event uses yet.
    func deliver(name: String, props: [String: MidgarSignalValue], uniqueness: MidgarSignal.Uniqueness, carriesCohort: Bool) {
        guard !isSuppressed else {
            clearQueue()
            return
        }
        var props = props
        if uniqueness != .each || carriesCohort {
            let date = now()
            ensureInstall(at: date)
            if let mark = Self.mark(uniqueness, props: props, keys: currentPeriodKeys(at: date)),
               !claim(key: MidgarSignalsLedger.key(name: name, props: props), mark: mark) {
                return
            }
            if carriesCohort, let cohort = install?.cohort {
                props["cohort"] = .string(cohort)
            }
        }
        guard let event = MidgarSignalEvent(name: name, props: props) else {
            return
        }
        enqueue(event)
    }

    /// Whether usage counts are sent. On until the person turns them off; the choice is kept per app on disk.
    public nonisolated var isEnabled: Bool {
        consent.isEnabled
    }

    /// Turns usage counts on or off. Off stops ``send(_:)`` and ``record(_:props:)`` at once and, a moment later, empties the queue and deletes the uniqueness ledger. It can be called from any thread, such as a settings switch.
    public nonisolated func setEnabled(_ enabled: Bool) {
        guard consent.update(enabled) else {
            return
        }
        Task { await self.applyConsent() }
    }

    /// Writes the choice to disk and, when counts are off, forgets everything queued and remembered.
    func applyConsent() {
        consent.persist()
        guard !consent.isEnabled else {
            return
        }
        install?.ledger = MidgarSignalsLedger()
        ledgerIsDirty = false
        MidgarSignalsLedgerStore(store: store).delete()
        discardQueue()
    }

    /// The period that makes a repeat of an event with this uniqueness a repeat, or nil when every send goes out: the current day, week or month for the periodic kinds, the lifetime mark for `lifetime`.
    static func mark(_ uniqueness: MidgarSignal.Uniqueness, props: [String: MidgarSignalValue], keys: MidgarSignalPeriodKeys) -> String? {
        switch uniqueness {
        case .each: return nil
        case .daily: return keys.day
        case .weekly: return keys.week
        case .monthly: return keys.month
        case .lifetime: return MidgarSignalsLedger.lifetimeMark
        case .perPeriod:
            guard case .string(let name)? = props["period"], let period = MidgarActivePeriod(rawValue: name) else {
                return nil
            }
            return keys.key(for: period)
        }
    }

    /// Records the send in the ledger and returns whether it is new.
    private func claim(key: String, mark: String) -> Bool {
        guard install?.ledger.claim(key: key, mark: mark) == true else {
            return false
        }
        ledgerIsDirty = true
        schedulePersist()
        return true
    }

    /// The names of the current day, week and month, worked out again only when the last answer has gone stale.
    func currentPeriodKeys(at date: Date) -> MidgarSignalPeriodKeys {
        if let periodKeys, periodKeys.contains(date) {
            return periodKeys
        }
        let fresh = MidgarSignalPeriodKeys(at: date)
        periodKeys = fresh
        return fresh
    }

    /// Loads the ledger and the cohort on first use. The cohort is decided here, once: `legacy` when the app says the install predates Lifestream or an earlier version had already been reporting activity, otherwise the ISO week of this launch. It is written at once, because losing it would move the install to another cohort.
    private func ensureInstall(at date: Date) {
        guard install == nil else {
            return
        }
        let ledgerStore = MidgarSignalsLedgerStore(store: store)
        let loaded = ledgerStore.load()
        let cohortStore = MidgarSignalsCohortStore(store: store)
        let cohort: String
        if let saved = cohortStore.load() {
            cohort = saved
        } else {
            cohort = existingInstall || loaded.migratedFromActivity
                ? MidgarSignalsCohortStore.legacy
                : currentPeriodKeys(at: date).week
            cohortStore.save(cohort)
        }
        install = InstallState(ledger: loaded.ledger, ledgerStore: ledgerStore, cohort: cohort)
        ledgerIsDirty = loaded.migratedFromActivity
        if ledgerIsDirty {
            schedulePersist()
        }
    }
}
