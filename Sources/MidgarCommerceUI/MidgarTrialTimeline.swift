import Foundation
import MidgarCommerce
import MidgarUI
import SwiftUI

/// The three days a free trial is really about, so a paywall says exactly what happens and when instead of burying it in the fine print.
struct MidgarTrialTimelineSteps: Equatable {
    struct Step: Equatable, Identifiable {
        enum Kind: Equatable {
            case today
            case reminder
            case charge
        }

        let kind: Kind
        let date: Date
        let title: String
        let detail: String

        var id: Kind { kind }

        var symbol: String {
            switch kind {
            case .today: return "lock.open.fill"
            case .reminder: return "bell.fill"
            case .charge: return "star.fill"
            }
        }
    }

    let steps: [Step]
    let endsAt: Date

    /// The timeline of the offer in `presentation`, or nil when it is not a free trial. A presentation exists only when StoreKit says this customer may use the offer, so the timeline is never shown to a customer who used it.
    ///
    /// - Parameters:
    ///   - includesReminder: Whether to promise a reminder step. Pass false when the app does not post one.
    init?(
        presentation: MidgarTrialPresentation,
        start: Date = .now,
        includesReminder: Bool = true,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        guard presentation.isFreeTrial, let end = Self.end(of: presentation.offer, from: start, calendar: calendar) else {
            return nil
        }
        endsAt = end
        var steps = [Step(kind: .today, date: start, title: MidgarCommerceUIStrings.timelineToday, detail: MidgarCommerceUIStrings.timelineTodayDetail)]
        if includesReminder, let reminder = Self.reminderDate(start: start, end: end) {
            steps.append(Step(
                kind: .reminder,
                date: reminder,
                title: Self.dayTitle(reminder, calendar: calendar, locale: locale),
                detail: MidgarCommerceUIStrings.timelineReminderDetail
            ))
        }
        steps.append(Step(
            kind: .charge,
            date: end,
            title: Self.dayTitle(end, calendar: calendar, locale: locale),
            detail: MidgarCommerceUIStrings.timelineChargeDetail(presentation.renewalDescription)
        ))
        self.steps = steps
    }

    /// Two days' notice for a trial of five days or more, one day for a shorter one, none for a trial too short to leave room for it.
    static func reminderDate(start: Date, end: Date) -> Date? {
        let length = end.timeIntervalSince(start)
        let lead: TimeInterval = length >= 5 * 86_400 ? 2 * 86_400 : 86_400
        guard length > lead else {
            return nil
        }
        return end.addingTimeInterval(-lead)
    }

    private static func end(of offer: MidgarIntroOffer, from start: Date, calendar: Calendar) -> Date? {
        let period = offer.totalDuration
        let component: Calendar.Component
        switch period.unit {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        return calendar.date(byAdding: component, value: period.value, to: start)
    }

    private static func dayTitle(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day().format(date)
    }
}

/// The free trial as a vertical timeline: each step a symbol in a circle, joined to the next by a thin line, saying what happens today, when the reminder comes and the day billing starts. Draws nothing when the offer is not a free trial.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
public struct MidgarTrialTimeline: View {
    private let steps: MidgarTrialTimelineSteps?

    @Environment(\.midgarTheme) private var theme

    /// - Parameters:
    ///   - presentation: The offer from ``MidgarTrialPolicy``. It exists only for a customer StoreKit says may use the offer.
    ///   - start: The day the trial would start.
    ///   - includesReminder: Whether the app posts a reminder before billing starts. The paywall promises one only when this is true.
    public init(presentation: MidgarTrialPresentation, start: Date = .now, includesReminder: Bool = true) {
        steps = MidgarTrialTimelineSteps(presentation: presentation, start: start, includesReminder: includesReminder)
    }

    init(steps: MidgarTrialTimelineSteps?) {
        self.steps = steps
    }

    @ViewBuilder
    public var body: some View {
        if let steps {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                Text(MidgarCommerceUIStrings.timelineHeader)
                    .midgarFont(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.label.color)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.steps.enumerated()), id: \.element.id) { index, step in
                        row(step, isLast: index == steps.steps.count - 1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(MidgarTimelineCard())
        }
    }

    private static var markerDiameter: CGFloat {
        #if os(tvOS)
        56
        #else
        28
        #endif
    }

    private static var markerSymbolSize: CGFloat {
        #if os(tvOS)
        24
        #else
        12
        #endif
    }

    private static var stepTitleStyle: MidgarTextStyle {
        #if os(tvOS)
        .title3
        #else
        .subheadline
        #endif
    }

    private static var stepDetailStyle: MidgarTextStyle {
        #if os(tvOS)
        .callout
        #else
        .footnote
        #endif
    }

    private func row(_ step: MidgarTrialTimelineSteps.Step, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.m) {
            marker(step.symbol)
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(verbatim: step.title)
                    .midgarFont(Self.stepTitleStyle)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.label.color)
                Text(verbatim: step.detail)
                    .midgarFont(Self.stepDetailStyle)
                    .foregroundStyle(theme.secondaryLabel.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, theme.spacing.xxs)
            .padding(.bottom, isLast ? 0 : theme.spacing.l)
            Spacer(minLength: 0)
        }
        .background(alignment: .topLeading) {
            if !isLast {
                Capsule()
                    .fill(theme.accent.color.opacity(0.35))
                    .frame(width: 2)
                    .padding(.top, Self.markerDiameter + theme.spacing.xxs)
                    .padding(.leading, Self.markerDiameter / 2 - 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(step.title), \(step.detail)"))
    }

    private func marker(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: Self.markerSymbolSize, weight: .semibold))
            .foregroundStyle(theme.accent.color)
            .frame(width: Self.markerDiameter, height: Self.markerDiameter)
            .background(theme.accent.color.opacity(0.2), in: Circle())
            .accessibilityHidden(true)
    }
}

/// On a TV the timeline sits on a card, so it reads as one block beside the plans; elsewhere it sits on the page.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
private struct MidgarTimelineCard: ViewModifier {
    @Environment(\.midgarTheme) private var theme

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(tvOS)
        content
            .padding(theme.spacing.xl)
            .background(theme.surface.color, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        #else
        content
        #endif
    }
}
