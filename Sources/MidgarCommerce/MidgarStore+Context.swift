import Foundation
import MidgarCore

extension MidgarStore {
    /// Tells signals what only the store knows, after every refresh: whether the install pays, and which running subscriptions had their renewal turned off. Signals turns both into closed-set words on the device, so the counts can be read by tier and a cancellation can be counted without anything that names the customer.
    func noteContext() async {
        await note(.tier(currentTier()))
        await noteRenewalsOff()
    }

    /// Free until an entitlement was ever held, lapsed after one ended, a trial while every active entitlement is a free introductory period, paid otherwise. Credits and other consumables grant no entitlement, so an install that only bought those stays free.
    func currentTier() -> MidgarSignal.Tier {
        let active = entitlements
        guard !active.isEmpty else {
            return state.hadEntitlement == true ? .lapsed : .free
        }
        if state.hadEntitlement != true {
            state.hadEntitlement = true
            persist()
        }
        return active.allSatisfy { trialProducts.contains($0.productID) } ? .trial : .paid
    }

    /// Tells signals once about each running subscription whose renewal is off. Turning it back on, or the subscription ending, forgets it, so a later change of mind counts again.
    private func noteRenewalsOff() async {
        guard configuration.mode == .purchases else {
            return
        }
        let renewals = await storeKit.renewals().filter { handledProducts.contains($0.productID) }
        let told = Set(state.renewalsOff ?? [])
        var off: Set<String> = []
        for renewal in renewals where !renewal.willAutoRenew {
            let key = String(renewal.originalID)
            off.insert(key)
            if !told.contains(key) {
                await note(.renewalOff(startedAt: renewal.startedAt))
            }
        }
        if off != told {
            state.renewalsOff = off.isEmpty ? nil : off.sorted()
            persist()
        }
    }
}
