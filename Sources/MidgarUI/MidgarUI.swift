#if canImport(UIKit)
@_exported import UIKit
#elseif canImport(AppKit)
@_exported import AppKit
#endif

#if canImport(SwiftUI)
@_exported import SwiftUI
#endif

@_exported import CoreGraphics
@_exported import CoreText
@_exported import ImageIO

#if canImport(QuartzCore)
@_exported import QuartzCore
#endif

/// Identifies the MidgarUI module: shared UIKit, AppKit and SwiftUI scaffolding lands here. It
/// re-exports the system UI frameworks so products above it import MidgarUI instead of them.
public enum MidgarUIModule {
    public static let name = "MidgarUI"
}
