import Foundation

extension MidgarSignals {
    /// Which version of an experiment to show on this install, or nil when the app's remote config does not carry the experiment, usage counts are off or signals are killed. Show what ships today for nil. It can be read from any thread and gives the same answer in every launch.
    ///
    /// Reading it sends nothing. The install enters the experiment when it next sends the event the experiment names as its exposure (for a paywall test, `paywall.view`), and its outcome counts when the outcome event follows.
    public nonisolated func variant(of experiment: String) -> String? {
        guard consent.isEnabled, !isKilledNow else {
            return nil
        }
        return activeExperiments().first { $0.id == experiment }.map(lab.variant(of:))
    }

    /// ``variant(of:)`` on the ``shared`` instance; nil until signals are configured.
    public nonisolated static func variant(of experiment: String) -> String? {
        shared?.variant(of: experiment)
    }

    /// Shows one version on this install until the process ends, whatever its seed picks, or lifts that with nil. For a debug screen and for looking at a version on a TestFlight build, which is never counted.
    public nonisolated func forceVariant(_ variant: String?, of experiment: String) {
        lab.force(variant, for: experiment)
    }

    /// The experiments the app's remote config carries right now.
    nonisolated func activeExperiments() -> [MidgarExperiment] {
        MidgarExperiment.all(in: currentConfig())
    }

    /// What sending this event means to the experiments that are running: the one that names it as its exposure takes the install in, once, and the one that names it as its outcome counts it when the install was exposed before. Both leave as events that are unique for the life of the install.
    func noteLab(_ name: String) {
        guard !isSuppressed, !name.hasPrefix(MidgarExperiment.keyPrefix) else {
            return
        }
        for experiment in activeExperiments() {
            let variant = lab.variant(of: experiment)
            if name == experiment.exposed, lab.markExposed(experiment.id) {
                send(.labExposed(experiment: experiment.id, variant: variant))
            }
            if name == experiment.converted, lab.wasExposed(experiment.id) {
                send(.labConverted(experiment: experiment.id, variant: variant))
            }
        }
    }
}
