#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if canImport(SwiftUI)
import SwiftUI
#endif

/// Identifies the MidgarUI module: shared UIKit, AppKit and SwiftUI scaffolding lands here.
public enum MidgarUIModule {
    public static let name = "MidgarUI"
}
