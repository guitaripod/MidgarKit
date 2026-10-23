import SwiftUI

/// How the device's fold divides the paywall's window. Read from the reserved regions UIKit reports, never from the hinge angle, and read again on every layout pass because the regions arrive after the first one and flip to active only while the device is partially folded.
struct MidgarFoldDivision: Equatable {
    enum Axis: Equatable {
        case columns
        case rows
    }

    let axis: Axis
    /// The fold's region in the paywall's coordinates.
    let frame: CGRect
    let isActive: Bool
}

#if os(iOS)
import UIKit

/// Reports the fold across the view it is the background of, and asks for a new report whenever the fold moves. Reserved regions change without any size or trait change, so the hinge interaction only schedules the pass; what the pass reports still comes from the regions.
@available(iOS 17.0, *)
struct MidgarFoldReader: UIViewRepresentable {
    let onChange: @MainActor (MidgarFoldDivision?) -> Void

    func makeUIView(context: Context) -> MidgarFoldReaderView {
        let view = MidgarFoldReaderView()
        view.onChange = onChange
        view.isUserInteractionEnabled = false
        view.installHingeInteraction()
        return view
    }

    func updateUIView(_ view: MidgarFoldReaderView, context: Context) {
        view.onChange = onChange
    }
}

@available(iOS 17.0, *)
final class MidgarFoldReaderView: UIView {
    var onChange: (@MainActor (MidgarFoldDivision?) -> Void)?
    private var reported: MidgarFoldDivision?

    override func layoutSubviews() {
        super.layoutSubviews()
        let division = currentDivision()
        guard division != reported else {
            return
        }
        reported = division
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            MainActor.assumeIsolated { self.onChange?(division) }
        }
    }

    func installHingeInteraction() {
        #if canImport(UIKit, _version: 9127.0.85)
        if #available(iOS 27.1, *) {
            addInteraction(UIHingeInteraction { [weak self] _, _ in
                self?.setNeedsLayout()
            })
        }
        #endif
    }

    private func currentDivision() -> MidgarFoldDivision? {
        #if canImport(UIKit, _version: 9127.0.85)
        if #available(iOS 27.1, *) {
            guard let region = reservedRegions(kind: .division, options: .includeInactive).first, !region.frame.isEmpty else {
                return nil
            }
            let axis: MidgarFoldDivision.Axis = region.frame.height > region.frame.width ? .columns : .rows
            guard Self.foldSplits(bounds, along: axis, at: region.frame) else {
                return nil
            }
            return MidgarFoldDivision(axis: axis, frame: region.frame, isActive: region.isActive)
        }
        #endif
        return nil
    }

    /// A view that sits on one page is told about the fold only as a sliver clipped to its edge. That is not a fold across the view, so it is ignored unless both sides keep at least a fifth of the view.
    private static func foldSplits(_ bounds: CGRect, along axis: MidgarFoldDivision.Axis, at frame: CGRect) -> Bool {
        switch axis {
        case .columns:
            let margin = bounds.width * 0.2
            return frame.minX >= bounds.minX + margin && frame.maxX <= bounds.maxX - margin
        case .rows:
            let margin = bounds.height * 0.2
            return frame.minY >= bounds.minY + margin && frame.maxY <= bounds.maxY - margin
        }
    }
}
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
extension View {
    /// Calls `onChange` with the fold across this view, or nil where the device has none. Only an iPhone Duo on iOS 27.1 or later reports one.
    @ViewBuilder
    func midgarFold(_ onChange: @escaping @MainActor (MidgarFoldDivision?) -> Void) -> some View {
        #if os(iOS)
        background(MidgarFoldReader(onChange: onChange))
        #else
        self
        #endif
    }
}
